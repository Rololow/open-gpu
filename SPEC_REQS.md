# SPEC_REQS — Exigences fonctionnelles et scope (version initiale)

But : concevoir un GPU modulaire en SystemVerilog, incluant pipeline raster, RT cores, NPU/tensor cores et un moteur d'upscaling IA capable de passer du 1080p en entrée à une sortie 4K en temps réel. Interfaces hôtes via PCIe, DMA générique et MMU pour gestion de la mémoire graphique et de la résidence de meshlsets/ressources.

1. Contrainte d'usage et cibles principales
- Objectif principal : pipeline GPU complet conçu from-scratch (RTL SystemVerilog), paramétrable, testable sous Verilator et ciblable sur FPGA pour un prototype minimal.
- Upscaler IA : support natif d'un pipeline d'upscaling d'image (1080p → 4K). Mode cible : rendu / post-process en temps réel à 30–60 FPS (configurable). Première itération vise 30 FPS sur résolution 1080p→4K pour prototypage; objectif long-terme 60 FPS.
- Entrée : scène 3D fournie sous forme de meshes/meshlets (format optimisé, voir section 3).

2. Exigences non-fonctionnelles
- Langage : SystemVerilog (RTL + paramétrisation via `parameter`).
- Simulation : support Verilator + cocotb tests; UVM facultatif pour blocs complexes (RT core, MMU). CI GitHub Actions exécutant simulations rapides et lint.
- Modélisation mémoire : abstractions pour usage en simulation (behavioral RAM) et macros synthétisables via `ifdef` pour synthèse FPGA.
- Licence : code produit propriétaire du projet (ou licence choisie par l'équipe). Réutilisation d'inspiration open-source possible, mais design from-scratch.

3. Format d'entrée : mesh / meshlet (spécification paramétrable)
- Objectif : format le plus compact et facile à streamer pour HW.
- Concepts clés :
  - Meshlet = petit ensemble de triangles (paramètre : triangles_per_meshlet, par défaut 64).
  - Pour chaque meshlet on stocke : vertex buffer (list of vertex attributes), index buffer (triangles), bounding cone / AABB, optional LOD metadata, material id, and a small descriptor.
  - Meshlet descriptor (extrait) : {meshlet_id, vertex_offset, vertex_count, index_offset, index_count, bounds_min[3], bounds_max[3], lod_metric, residency_flag}
- Stockage : les meshlets sont paginés en unités de taille paramétrable `PAGE_SIZE` (par défaut 64 KiB). Chaque page contient plusieurs meshlets. Page size et meshlet size sont paramètres de synthèse.
- Residency : table de residency (bitset / per-page residency) gérée par la MMU/GPUMemoryManager — support pour host-pinned pages et streaming.

4. Interface hôte : PCIe endpoint (spécification minimale)
- PCIe config (version initiale) : Gen3 x8 recommended for target throughput; support Gen3 x4 for FPGA prototypes.
- BAR mapping :
  - BAR0 (MMIO) : control & status registers (command queues, doorbells, version, diagnostics).
  - BAR1 (optional) : host-visible descriptor ring / upload window.
  - BAR2+ : optional for memory mapping or device-specific regions.
- Interrupts : support MSI-X for event-driven completion notifications (configurable). Also support polling via MMIO doorbell.
- Host driver model (minimal) :
  - Host allocates and pins host pages (or uses IOMMU) et donne au device les adresses physiques/IO via des descriptors DMA.
  - Host soumet le travail via command buffer/queue (MMIO write + doorbell). Device lit les descriptors via DMA.

5. DMA engine & descriptor format
- DMA capabilities : scatter-gather, block transfers, simple copy, chained descriptors, stride transfers for image tiles.
- Descriptor (64-bit fields suggested):
  - 64b: src_addr
  - 64b: dst_addr
  - 32b: length_bytes
  - 16b: stride_bytes (optional)
  - 8b: flags (e.g. interrupt_on_complete, last_in_chain, direction, encryption/compression flags future)
  - 64b: next_descriptor_ptr (if chained, else 0)
- Command semantics : DMA engine can be programmed by host (via descriptor ring in host memory or via MMIO) or by device (internal usage for prefetch/residency). Support doorbell mechanism to kick DMA.

6. MMU / Memory residency model
- Objectives : permettre streaming de ressources (meshlets, textures, BVH nodes) depuis la mémoire système (host DRAM) et maintenir une translation/addressing cohérente côté GPU.
- Features minimalistes :
  - Page table (configurable page size, default 64 KiB). Small TLB (configurable entries) inside GPU for fast lookup.
  - Residency table per-page (bitmap or resident counter) : GPU checks residency bit before accessing meshlet page; if not resident it triggers DMA prefetch (or reports page-fault event to host if page-fault mode is used).
  - I/O address mapping: device uses 64-bit physical addresses for DMA; host driver is responsible pour pin/unpin.
  - MMU ops: map/unmap page, query residency, flush TLB, invalidate, pin/unpin via MMIO commands.
  - Page-fault handling: two modes
     * Host-assisted: device raises an interrupt when missing page detected; host pins/uploads and updates page table.
     * Device-prefetch: device autonomously issues DMA to bring page and retries access (preferred for high-performance streaming).
- Coherency: device-managed caches (L1 per-core, optional shared L2) have write-back policy; host writes must go through DMA or explicit flush ops.

7. Command processor & queues (aperçu)
- Host submits work via command buffers (rings) in host memory ou via MMIO.
- Command types (examples) : draw/dispatch, upload_meshlet_page, prefetch, compute_dispatch (NPU), upscaler_dispatch, flush, debug_read.
- Doorbell + completion queue model with MSI-X or MMIO polling.

8. Upscaler IA (1080→4K) — architecture & contraintes
- Pipeline : accepts rendered 1080p frame (or feature maps) as input, runs IA upscaler network (e.g., small convolutional NN optimized for HW) et outputs 4K frame.
- Dataflow : tiling of input frame (tiles sized to fit on-core buffer), streaming conv windows, reuse of weights via weight-cache, partial outputs stitched.
- Precision : support FP16/BF16 and INT8 inference; accumulate in FP32 or FP16 as needed — réglable par paramètre.
- Throughput target : pour 30 FPS real-time target convertir required MACs per second et dimensionner le tensor-core en conséquence. Première itération : réseau compact pour prototypage.

9. Verification & acceptance criteria
- Unit tests : cocotb/Verilator tests pour DMA, MMU, command processor, simple MAC array.
- Integration tests : pipeline bout-en-bout sur une scène minimale (quelques meshlets) et validation des pixels pour un shader simple + upscaler.
- Performance tests : tests synthetiques pour évaluer débit DMA et MAC/s performance (cycles/op).
- Compliance tests : PCIe BAR & MMIO access tests, descriptor stress tests, page-fault/residency stress tests.

10. Livrables sprint-1 (4 semaines cible)
- `SPEC_REQS.md` (this file) + `ROADMAP.md` avec milestones.
- Repo scaffold + `rtl/` top-level template `rtl/top.sv` et skeleton de simulation.
- Implémentation minimale : command processor + simple DMA engine + MMU stub + testbench vérifiant DMA+MMIO roundtrip.
- Exemple driver simple (user-space) pour écrire MMIO et soumettre une DMA (scripts d'exécution).

11. Prochaines étapes suggérées
- Valider ces exigences (confirmer page size, PCIe lane count, FPS cibles).
- Si validé : je génère le scaffold repo, crée `rtl/top.sv` template et implémente le proto DMA+MMU stub avec tests cocotb.

--
Fichier généré automatiquement dans le workspace local.
