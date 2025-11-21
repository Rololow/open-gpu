param(
    # Hard-coded ModelSim/Questa bin path for this user's environment.
    # Change this value if your installation is elsewhere.
    [string]$ModelSimBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [switch]$Clean
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")

# log file must be defined early so diagnostics can write to it
$logFile = Join-Path $repoRoot "sim_modelsim_native.log"

Write-Host "Repo root:" $repoRoot

# Determine simulator executables
if ($ModelSimBin) {
    $vlib = Join-Path $ModelSimBin "vlib.exe"
    $vlog = Join-Path $ModelSimBin "vlog.exe"
    $vsim = Join-Path $ModelSimBin "vsim.exe"
    # prepend to PATH
    $env:PATH = "$ModelSimBin;$env:PATH"
} else {
    $vlib = "vlib"
    $vlog = "vlog"
    $vsim = "vsim"
}

# If specified paths don't exist, try to auto-detect via PATH
function _try_detect_exe([string]$exeName, [string]$currentPath) {
    if ((Test-Path $currentPath) -and (Get-Item $currentPath).PSIsContainer -eq $false) {
        return $currentPath
    }
    try {
        $cmd = Get-Command $exeName -ErrorAction Stop
        return $cmd.Path
    } catch {
        return $null
    }
}

$vlib_detected = _try_detect_exe "vlib.exe" $vlib
$vlog_detected = _try_detect_exe "vlog.exe" $vlog
$vsim_detected = _try_detect_exe "vsim.exe" $vsim

if (-not $vlib_detected -or -not $vlog_detected -or -not $vsim_detected) {
    Write-Host "ModelSim executables not found at the configured location or on PATH." -ForegroundColor Yellow
    Write-Host "Attempting to locate simulator tools via PATH..."
    $vlib = $vlib_detected ?? (Get-Command vlib -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue)
    $vlog = $vlog_detected ?? (Get-Command vlog -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue)
    $vsim = $vsim_detected ?? (Get-Command vsim -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue)

    if (-not $vlib -or -not $vlog -or -not $vsim) {
        $errMsg = @"
Could not locate vlib/vlog/vsim.
Set the correct ModelSim bin directory in the environment variable `MODELSIM_BIN`, for example:
$env:MODELSIM_BIN='C:\intelFPGA_lite\...\modelsim_ase\win64\bin'
"@
        Write-Error $errMsg | Tee-Object -FilePath $logFile -Append
        exit 2
    } else {
        Write-Host "Found simulator tools:" $vlib, $vlog, $vsim | Tee-Object -FilePath $logFile -Append
    }
}

$logFile = Join-Path $repoRoot "sim_modelsim_native.log"
if ($Clean -or (Test-Path (Join-Path $repoRoot "sim_build"))) {
    Write-Host "Cleaning previous build directories..."
    if (Test-Path (Join-Path $repoRoot "work")) { Remove-Item -Recurse -Force (Join-Path $repoRoot "work") }
    if (Test-Path (Join-Path $repoRoot "sim_build")) { Remove-Item -Recurse -Force (Join-Path $repoRoot "sim_build") }
}

Write-Host "Compiling RTL with ModelSim/Questa..." | Tee-Object -FilePath $logFile
Write-Host "Running: $vlib work" | Tee-Object -FilePath $logFile -Append
$out = & $vlib work 2>&1
$out | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Write-Error "vlib returned exit code $LASTEXITCODE. Ensure ModelSim/Questa is installed and PATH/ModelSimBin is correct." | Tee-Object -FilePath $logFile -Append
    exit 2
}

# Collect source files
$rtlDir = Join-Path $repoRoot "rtl"
$simTb = Join-Path $scriptDir "tb_top.sv"
$sources = Get-ChildItem -Path $rtlDir -Filter "*.sv" | ForEach-Object { $_.FullName }
$allFiles = $sources + $simTb

Write-Host "Files to compile:" | Tee-Object -FilePath $logFile -Append
$allFiles | ForEach-Object { Write-Host "  $_" | Tee-Object -FilePath $logFile -Append }

Write-Host "Running: $vlog -incr -work work -sv [files]" | Tee-Object -FilePath $logFile -Append
$out = & $vlog -incr -work work -sv $allFiles 2>&1
$out | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Write-Error "vlog returned exit code $LASTEXITCODE. See $logFile for details." | Tee-Object -FilePath $logFile -Append
    exit 3
}

Write-Host "Running simulation (vsim)..." | Tee-Object -FilePath $logFile -Append
Write-Host "Running: $vsim -c -onfinish exit work.tb_top -do 'run -all; quit'" | Tee-Object -FilePath $logFile -Append
$out = & $vsim -c -onfinish exit work.tb_top -do "run -all; quit" 2>&1
$out | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Write-Error "vsim returned exit code $LASTEXITCODE. See $logFile for details." | Tee-Object -FilePath $logFile -Append
    exit 4
}

Write-Host "Simulation finished. See $logFile for full output." | Tee-Object -FilePath $logFile -Append
