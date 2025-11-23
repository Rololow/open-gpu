# Projet GPU modulaire en SystemVerilog — Spécifications

Ce document rassemble les objectifs, exigences et architecture initiale pour un projet ambitieux : implémenter en SystemVerilog un GPU complet, modulaire et hautement paramétrable, intégrant : un pipeline graphique classique, des RT-cores pour lancer des rayons et éventuellement de la simulation de collision, un NPU/tensor-core pour l'IA (notamment upscaling de 1080p -> 4K), et un système mémoire / interconnect robuste.

**Objectifs principaux**
- Concevoir des blocs SystemVerilog très génériques et paramétrables (paramètres de largeur de données, nombre de lanes, profondeur des pipelines, taille des caches, formats FP/INT, etc.).
- Permettre différentes cibles : simulation (Verilator/Questa), prototypage FPGA (Xilinx/Intel) et synthèse ASIC à long terme.
- Supporter un modèle d'intégration hébergé (host driver via PCIe / AXI host) et un modèle autonome pour tests.
- Fournir une stratégie de vérification complète (UVM + cocotb + formal).

**Livrables de la phase 1 (prioritaire)**
- `SPECIFICATION.md` (ce doc) : spécifications détaillées.
- Inventaire de projets open-source à analyser (ex : MIAOW GPU), avec critiques.
- Roadmap et découpage en sous-projets/priorités.

**Ressources / Référence à analyser**
- MIAOW GPU (étudier architecture, choix de microarchitecture, points d'amélioration).
- Projets open-source complémentaires : Nyuzi (GPU-like core), OpenSWR, open-source RT research repos, implémentations d'accélérateurs ML.
- Outils : Verilator, Questa/ModelSim, Synopsys VCS, Yosys+nextpnr, Vivado/Quartus, SymbiYosys pour formal.

**Architecture globale (haut niveau)**
- Command Processor / Command Queue
  - Reçoit commandes du host (DMA, descriptors), ordonne et dispatch vers moteurs (graphics, RT, NPU).
  - Interface paramétrable : PCIe endpoint / AXI slave / MMIO.
- Memory System
  - Interface DMA et coherence (AXI4/AXI4-Lite ou TileLink).
  - Cache(s): L1 per compute unit, shared L2 (configurable), optional LLC.
  - TLB/MMU support (optionnel), page-fault handling via host.
- Interconnect
  - Crossbar / NoC léger pour router transactions vers DRAM, caches, accelerators.
  - Support QoS/ordering si nécessaire.
- GPU Raster Pipeline
  - Vertex Processing (option: hardware vertex fetch + optional small shader core or host-side vertex processing).
  - Primitive Assembly & Clipping
  - Rasterizer (tile-based option possible) : programmable sample rate, MSAA support.
  - Fragment Shading: model programmable shaders via small ISA / compute kernels or offload to shader cores (SIMD lanes).
  - ROP / Blend / Depth/Stencil
- RT Core (Ray Tracing)
  - Accélération BVH (SAH build offline or hardware-friendly builder)
  - Traversal unit (stack-based or stackless) optimisé pour triangles
  - Intersection units (triangle intersection primitives) — pipelineable, paramétrable
  - Option: étendre pour simulation physique (collision triangle-triangle) en exposant primitives pour queries
- NPU / Tensor Cores
  - MatMul/Convolution accelerators (systolic array ou MAC arrays)
  - Support multi-precision (FP32, FP16, BF16, INT8)
  - Tensor memory tiling + DMA
  - Accélération réseau pour upscaling (ex: implementation d'un modèle SRCNN, ESRGAN-lite, ou un réseau custom pour 1080p->4K)
- Upscaler
  - Pipeline combinant NPU inference + temporal accumulation
  - Fallback non-IA (bilinear, bicubic) pour debug
  - API pour entraîner et déployer réseaux d'upscale (format de poids, quantization)

**Nanite-style Virtualized Geometry (LOD automatique / Mesh Streaming)**
- Objectif: supporter un pipeline matériel/firmware pour géométrie virtualisée à la manière de Nanite (Unreal Engine) permettant le rendu de modèles extrêmement détaillés via streaming de "clusters"/"meshlets" et sélection LOD automatique.
- Principes clés:
  - Virtualisation de géométrie: stocker géométrie en petits blocs (clusters/meshlets) indexés et paginés ; le GPU ne charge que les clusters visibles à la résolution requise.
  - Hardware-assisted streaming: unité de gestion mémoire (Geometry Page Manager) pour charger/décharger clusters depuis la mémoire principale/stockage, avec table de pages GPU-resident et politique de priorité (visible, proche caméra, importance).
  - LOD automatique: sélection de niveaux de détails basée sur distance caméra, taille à l'écran, et coût de rasterisation; prise en compte de culling (frustum + occlusion) pour éviter le chargement inutile.
  - Meshlets & compact indexation: supporter formats compacts (vertex deltas, 16-bit indices ou compressed index streams) et mapping meshlet->BVH pour accélérer intersection/occlusion.
  - Intégration RT: coopération avec le RT core — utiliser clusters/meshlets comme primitives BVH leaves, et permettre traversal efficace pour ray queries et occlusion rays.
  - GPU page table / residency: structure HW pour marquer la résidence des clusters (residency bitmaps, TLB-like cache), et mécanismes de stall/async load via command processor/DMA.

- Impacts sur l'architecture mémoire et interconnect:
  - Nécessité d'un path DMA haute-bande passante et de priorités QoS pour streaming continu.
  - Caches et prefetchers optimisés pour petits blocs (cluster-sized), et mécanismes pour minimiser fragmentation.
  - Mécanismes de compression/décompression hardware (optionnels) pour réduire bande passante stockage->DRAM.

- API et format d'intégration:
  - Commandes pour décrire virtual meshes: cluster table, cluster sizes, bounding volumes, material/primitive ranges.
  - Callbacks/MMIO pour requester préfetch explicite, hinting de streaming, et pour recevoir événements de page-fault/residency.
  - Support d'un format "meshlet" standard (vertex layout, index layout, optional adjacency/visibility masks).

- Vérification et critères d'acceptation:
  - Tests de qualité visuelle: vérifier continuité LOD, absence d'artefacts lors de streaming, et taux de stutter/pauses.
  - Stress tests de streaming: scénarios avec déplacements rapides de caméra, scènes très denses, et contraintes de bande passante.
  - Mesures de performance: temps de latence moyen pour chargement de cluster, bande passante de streaming, overhead CPU/host.

- Optimisations potentielles:
  - Offload de culling précoce (hierarchical occlusion culling) vers hardware pour réduire streaming.
  - Prefetch heuristics basées sur camera motion prediction (peut exploiter NPU pour pattern prediction).
  - Packing mémoire pour co-localiser clusters fréquemment utilisés (hot clusters) afin de réduire fragmentation et latence.

Cette extension permettrait au GPU d'adresser des scènes avec des milliards de triangles en ne maintenant en mémoire que les données nécessaires à l'instant t, tout en gardant la latence et la qualité visuelle acceptables pour un rendu temps réel.

**Principes de conception (généricité)**
- Paramétrage via `parameter`/`localparam` SystemVerilog (largeur bus, nombre d'éléments, profondeurs FIFO, formats FP).
- Blocs découplés par interfaces standardisées (AXI4, AXI-Stream, Avalon, TileLink) pour faciliter réutilisation.
- Contrats clairs : ready/valid handshakes, backpressure, timeouts pour host.
- Isolation des dépendances: chaque bloc testable indépendamment (testbench, mocks du bus).

**Interfaces recommandées**
- Mémoire & DMA: `AXI4` (32/64-bit data) et `AXI4-Stream` pour flux de données (vertices, fragments, tensor tiles).
- Control/MMIO: `AXI4-Lite` ou `APB` pour registres de contrôle.
- Host: PCIe endpoint + driver (phase FPGA: PCIe soft IP / Xillybus-like wrapper) ou simulation via mmap/pipe.

**Formats de données & précision**
- Graphics: FP32 pour computations, possibilité d'utiliser FP16 pour performances.
- RT + intersections: FP32 par défaut ; tolérances et eps contrôlables via paramètres.
- NPU: support multi-precision (INT8 quantized path, FP16/BF16, FP32)

**Mémoire & throughput cible (exemples de départ)**
- Bandwidth DRAM cible dépend du hardware : viser configurabilité 32-512 GB/s (pour FPGA prototyping, plus bas realisticement).
- Caches paramétrables : L1 per CU (4-64 KB), L2 shared (256 KB - multiple MBs paramétrables).

**Vérification & simulation**
- Simulation cycle-accurate: Verilator + cocotb pour tests haut-niveau et benchs.
- UVM pour verification modulaire des sous-systèmes critiques (DMA, interconnect, RT traversal).
- Coverage: code coverage (if outils le permettent), functional coverage plans.
- Formal: propriétés safety/liveness simples pour interconnect et arbiter, checks pour deadlock, AXI protocol compliance via SymbiYosys ou équivalent.

**Synthèse & prototypage**
- Cible FPGA : commencer par boards Xilinx Ultrascale+ (ex: VCU118) ou Alveo pour plus de DRAM BW, ou boards plus petites (Zynq Ultrascale+) pour budget réduit.
- Penser à contraintes de timing, ressources BRAM/URAM pour caches, DSP slices pour tensor cores.
- Scripts de build Vivado/Quartus et flows Yosys/nextpnr pour approches open-source.

**Méthodologie d'implémentation (phases)**
1. Phase Spec (actuelle) : documenter et lister projets à analyser.
2. Prototype minimal : un rasterizer simple (vertex fetch simplié -> raster -> simple fragment shader), validation via Verilator.
3. Memory/Interconnect : DMA, caches L1/L2, test vectors.
4. RT core minimal : traversal + triangle intersection pour simple primary rays.
5. NPU minimal : implémentation d'un petit systolic array pour matmul 16x16, support quantized inference d'un petit upscaler.
6. Intégration upscaler : pipeline 1080p -> 4K (évaluer latence, throughput, qualité).
7. Optimisations, synthèse FPGA, et tests sur hardware.

**Roadmap courte (quarterly)**
- Q1: Spécifications complètes, inventaire projets, prototype raster minimal.
- Q2: Memory system stable, simple shader model, testbench complet.
- Q3: RT core v0, basic NPU v0, simple upscaler inference running in sim.
- Q4: Integration, FPGA prototype, benchmarks, documentation.

**Qualité d'image & metrics pour l'upscaler**
- Mesures PSNR/SSIM/LPIPS sur dataset d'évaluation.
- Mesure latence et taux d'images/s pour pipeline complet (incluant copie host <-> device).

**Critères d'acceptation des modules**
- Chaque module doit être livrable avec : RTL SystemVerilog, testbench (cocotb or UVM), README d'utilisation, et scripts de simulation automatisés.
- Interfaces publiques documentées (registres, FIFO depths, handshake semantics).

**Outils & environnement de développement**
- Simulateurs : Verilator (fast, open), Questa/ModelSim pour features avancées.
- Linting : Verible / verilator lint.
- Build : Make/CMake + Python scripts pour orchestration.
- CI : GitHub Actions (sim + lint), containers Docker pour environnement reproductible.

**Sécurité & licence**
- Utiliser licences permissives (MIT/Apache-2.0) pour faciliter adoption, mais vérifier compatibilité des dépendances.

**Plan d'analyse de projets open-source**
- Cloner MIAOW et autres exemples pertinents.
- Produire pour chaque repo : résumé architecture, points forts, limites, idées d'amélioration (1-2 pages par projet).

**Prochaines actions immédiates**
- Lister les repos à cloner (MIAOW + 3 autres), lancer l'analyse comparative.
- Détailler l'architecture du command processor + format de commande.

## DMA: Format de descripteurs et mode chaîne (descriptor chaining)

Le design fournit un contrôleur DMA simple capable de deux modes d'opération :
- mode direct (programmer `SRC`, `DST`, `LEN`, puis pulser `START`),
- mode descriptor (le DMA lit une table de descripteurs en mémoire et exécute chaque segment en chaîne).

Points clés :
- Les registres MMIO exposés par le `top` (offsets en octets) :
  - `0x10` : `SRC_LO` (low 32 bits de l'adresse source)
  - `0x14` : `SRC_HI` (high 32 bits de l'adresse source)
  - `0x18` : `DST_LO` (low 32 bits de l'adresse destination)
  - `0x1C` : `DST_HI` (high 32 bits de l'adresse destination)
  - `0x20` : `LEN` (nombre de mots 32-bit à transférer)
  - `0x24` : `START` (écrire 1 pour démarrer; le bit est échantillonné et auto-clear)
  - `0x28` : `DESC_PTR` (adresse en octets du premier descripteur)
  - `0x30` : `DESC_MODE` (1 = activer lecture de descripteurs)
  - `0x2C` : `STATUS` (bit0 = `DONE` sticky — lecture pour savoir si l'opération est terminée)


Format d'un descripteur (chaque descripteur = 4 mots 32-bit consécutifs, stockés en mémoire):

- mot 0 : `SRC_ADDR` (adresse source en octets)
- mot 1 : `DST_ADDR` (adresse destination en octets)
- mot 2 : `LEN` (nombre de mots 32-bit à copier)
- mot 3 : `NEXT_DESC_PTR | FLAGS` (bits mixtes — pointeur + flags)

Disposition des bits du mot 3 (32 bits):

- bit 0 : `IRQ_ON_COMPLETE` — si 1, le DMA pulse une IRQ à la fin du traitement de ce descripteur (fin de chaîne).
- bit 1 : `IRQ_ON_EACH` — si 1, le DMA pulse une IRQ après la complétion de ce descripteur même s'il chaîne vers le suivant.
- bits [4:2] : `PRIO` — 3 bits de priorité (valeur 0..7) réservés pour usage futur.
- bits [31:5] : `ATTRS` — champs d'attributs (27 bits) pour hints (cache, ordering, extension future).

Note: Les champs `NEXT_DESC_PTR` et `FLAGS` sont packés dans ce mot. L'implémentation actuelle stocke l'adresse complète en octets dans `word3` et interprète les bits bas pour flags. Pour aligner les usages, évitez d'utiliser les bits bas de l'adresse pour des adresses non-alignées/packed si vous activez des flags.

Remarques d'implémentation :
- `DESC_PTR` et `NEXT_DESC_PTR` sont des adresses en octets mais la logique de lecture interne fait la lecture mot-par-mot (le contrôleur convertit en index mot en divisant par 4).
- Lorsqu'un descripteur est assemblé, le DMA exécute le transfert (avec sémantique `memmove` pour gérer le recouvrement source/destination en choissant la direction appropriée).
- Quand un transfert issu d'un descripteur est terminé, si `NEXT_DESC_PTR != 0` et que `DESC_MODE` est toujours actif, le DMA chaînera automatiquement vers le descripteur suivant (retour au state `FETCH_DESC`).
- Si `DESC_MODE` est désactivé pendant une lecture de descripteur, le contrôleur abandonne proprement le fetch et retourne à `IDLE` (prévention de blocage observée pendant le développement).

Exemple d'usage (inspiré du `sim/tb_top.sv` fourni) :

1. Préparer en mémoire deux descripteurs à l'adresse byte `0x8000` (on montre ici l'initialisation au niveau mot `mem[desc_base + i]` avec `desc_base = 0x8000 >> 2`):

```systemverilog
// descriptor 0
mem[desc_base + 0] = 32'h00005000; // src byte addr
mem[desc_base + 1] = 32'h00006000; // dst byte addr
mem[desc_base + 2] = 8;            // len (words)
mem[desc_base + 3] = 32'h00008010; // next_desc_ptr -> points to descriptor 1 (byte addr)

// descriptor 1
mem[desc_base + 4] = 32'h00005100; // src
mem[desc_base + 5] = 32'h00006200; // dst
mem[desc_base + 6] = 4;            // len
mem[desc_base + 7] = 32'h0;        // next = 0 (end)
```

2. Programmer les registres MMIO :

```systemverilog
write_reg(0x28, 32'h00008000); // DESC_PTR (byte addr)
write_reg(0x30, 32'h1);         // DESC_MODE = 1
write_reg(0x24, 32'h1);         // START (pulse; TB pulse deux fois pour robustesse)
```

3. Poller `STATUS` (`0x2C`) jusqu'à ce que `bit0 == 1` puis vérifier les destinations mémoire.

Conseils pratiques et limitations :
- Le modèle mémoire embarqué (`mem_model`) est synchrone et retourne la donnée l'itération suivante après `read_en` ; le DMA gère un petit pipeline d'ordres (FIFO) pour lier chaque lecture à son adresse d'écriture correspondante.
- Le format de descripteur est minimal — on peut étendre `word3` pour contenir des flags (e.g., IRQ on completion, priority) ou des attributs (cache hints, bypass), mais cela nécessitera un mapping défini et l'extension du TB.
- Pendant la phase de développement, des impressions debug (`DEBUG=1`) ont aidé à stabiliser la logique; après validation, il est recommandé de désactiver le bruit de trace (`rtl/config.sv`) pour des runs de regression plus propres.

Si vous voulez, je peux :
- formaliser une version étendue du descripteur (flags IRQ/prio/attributes),
- ajouter un exemple de driver hôte (Python/C) qui écrit les descripteurs via MMIO, ou
- rédiger une section de tests de stress pour vérifier l'atomicité et la résilience au recouvrement (memmove semantics).

---

Annexe : Questions ouvertes (à décider)
- Modèle de shader : exécuter des shaders sur hardware (small ISA / VM) ou tout faire côté host ?
- Tile-based renderer vs immediate rasterizer ? (tradeoffs mémoire vs bandwidth)
- Build hardware BVH / builder hardware ou build BVH offline sur host ?
- Choix d'interface bus: AXI4 vs TileLink selon l'écosystème ciblé.


Pour la suite, indiquez si vous voulez que je :
- commence à cloner et analyser des projets (j'extrais critiques et notes),
- ou que je commence directement à détailler l'architecture du `Command Processor` et du format de commandes pour piloter le GPU.
