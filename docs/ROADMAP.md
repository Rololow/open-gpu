# Roadmap - Open-GPU (high level)

This document outlines the initial milestones and sprint plan for the Open-GPU project.

Sprint 0 - Setup (1 week)
- Create repo scaffold, add top-level template (`rtl/top.sv`) and simulation harness (`sim/tb_top.sv`).
- Setup basic CI to run quick Verilator builds.

Sprint 1 - Core infra (4 weeks)
- Implement command processor minimal (MMIO + doorbell), simple DMA engine, MMU stub and testbench.
- Provide example host-side script to submit DMA.

Sprint 2 - Raster pipeline (6 weeks)
- Implement simple vertex processing and rasterization pipeline sufficient for basic triangle rendering to framebuffer.

Sprint 3 - RT core (8–12 weeks)
- Implement BVH traversal and intersection pipeline; simple shading pass.

Sprint 4 - NPU/Upscaler (8–12 weeks)
- Implement tensor-core MAC array and minimal upscaler network optimized for 1080->4K.

Sprint 5 - Integration & FPGA prototyping (6–8 weeks)
- Integrate components, replace behavioral RAMs with synthesizable macros, validate on target FPGA.

Notes:
- All durations are rough estimates; tasks will be broken down into smaller stories in the issue tracker.
- Prioritize simulation-first approach for early validation with Verilator + cocotb.
