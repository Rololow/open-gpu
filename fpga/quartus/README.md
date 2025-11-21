# Quartus FPGA flow (local)

This folder contains guidance to create a Quartus project and target an Intel/Altera FPGA.

Quick steps (Quartus GUI):
1. Open Quartus, create a new project, point to this repo root as project directory.
2. Add the `rtl/` files and any wrappers under `fpga/` you create.
3. Set the top-level entity to `top` (or your chosen wrapper name) in the Project > Settings.
4. Select your target device (family and part) and compile.

Command-line (example):

    quartus_sh --flow compile <project_name>

Notes:
- Replace behavioral RAM models with vendor RAM IP (or create wrappers) before synthesis.
- Quartus projects require device-specific constraints and pin assignments — provide your board's QSF settings.
- For FPGA prototyping we recommend a device with sufficient BRAM/DDR interface and PCIe soft IP if you plan to test PCIe.
