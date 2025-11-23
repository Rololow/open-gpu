# TODO

Feuille de route priorisée pour le projet Open-GPU

- [ ] Add descriptor-based DMA (scatter/gather)
  - Objectif: Supporter une ring de descripteurs en mémoire pour que le DMA réalise des transferts multi-segments pilotés par l'hôte.
  - Changements: ajouter le format de descripteur (src, dst, len, flags, next), logique de lecture de descripteur, et signal d'interruption par-descripteur.

- [ ] Implement MMU page-table translation
  - Objectif: Remplacer le stub `mmu` par un traducteur complet (TLB + page walker) gérant faults et bits de résidence.
  - Tests: traductions, fautes de page, invalidations TLB.

- [ ] Add control/interrupt block and AXI-lite MMIO
  - Objectif: Étendre la voie de contrôle: map de registres complète, sortie d'interruption, interface AXI4-Lite (ou alternative) pour l'accès hôte.
  - Tests: accès MMIO complets et comportement d'interruption.

- [ ] Add AXI4 master interface for external memory
  - Objectif: Remplacer `mem_model` par une interface AXI maître pour cibler de la DRAM/PCIe sur FPGA.
  - Changements: wrapper AXI master RTL + modèle de trafic AXI pour la simulation.

- [ ] Design compute cores (shader/compute units)
  - Objectif: Définir un petit coeur SIMD/mini-shader (ISA, registre, fetch/dispatch, ALU vectorielle).
  - Intégration: connexion DMA/MMU pour mouvement de données.

- [ ] Implement caches and memory ordering
  - Objectif: Ajouter un cache D-L1 pour les coeurs compute avec sémantique d'ordre et writeback.
  - Tests: cohérence, scénarios de course, invalidation.

- [ ] Host driver and software stack (emulation)
  - Objectif: Écrire un driver hôte simple (C/Python) pour programmer registres, charger descripteurs et valider les transferts.
  - Option: intégration QEMU pour émulation système.

- [ ] Verification & CI
  - Objectif: Ajouter régression cocotb (résoudre le mismatch PLI si nécessaire), GitHub Actions pour exécuter les simulations, rapports de couverture.
  - Remarque: sur Windows, cocotb + ModelSim peut nécessiter une correspondance de l'ABI PLI.

- [ ] Synthesis readiness and FPGA bringup
  - Objectif: Ajouter projet Quartus/constraints, notes de floorplanning, et valider la synthèse sur la cible FPGA.

- [ ] Documentation and SPEC updates
  - Objectif: Mettre à jour `SPECIFICATION.md` avec le format des descripteurs DMA, sémantique MMU, map de registres, API hôte et guide rapide pour exécuter les simulations sur Windows ModelSim.

---

Notes:
- Si vous voulez, je peux marquer certains items comme prioritaires et commencer l'implémentation immédiatement (par exemple: DMA par descripteur ou MMU).
- Voulez-vous que je crée aussi une branche git et un commit pour ces changements une fois validés ?
