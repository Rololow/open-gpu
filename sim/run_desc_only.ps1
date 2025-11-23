param(
    [switch]$Clean
)

Push-Location $PSScriptRoot
$repo = Split-Path -Parent $PSScriptRoot
Write-Host "Repo root: $repo"
# Auto-clean: always remove the `work` directory to avoid stale compiled artifacts
if (Test-Path work) {
    Write-Host "Auto-clean: removing existing 'work' directory..."
    Remove-Item -Recurse -Force work
}

# compile
$vlog = "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vlog.exe"
$vlib = "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vlib.exe"
$vsim = "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe"
& $vlib work
& $vlog -incr -work work -sv ..\rtl\config.sv ..\rtl\dma.sv ..\rtl\mem_model.sv ..\rtl\mmu.sv ..\rtl\top.sv ..\sim\tb_desc_only.sv
# run
& $vsim -c -onfinish exit work.tb_desc_only -do 'run -all; quit'

Pop-Location
