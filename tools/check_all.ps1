# One-stop check: TS export + TS tests + deps + format + lint + GdUnit4 + parity
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_all.ps1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$srcDirs = @("scripts", "tests")
$dirs = @()
foreach ($d in $srcDirs) {
    $p = Join-Path $root $d
    if (Test-Path $p) { $dirs += $p }
}
$generatedConfigTypes = Join-Path $root "scripts\config\config_types.gd"
$formatFiles = Get-ChildItem $dirs -Recurse -Filter "*.gd" -File |
    Where-Object { $_.FullName -ne $generatedConfigTypes } |
    ForEach-Object { $_.FullName }
$failed = $false
$uvx = $null
if (Get-Command uvx -ErrorAction SilentlyContinue) { $uvx = (Get-Command uvx).Source }
if (-not $uvx) {
    $uvxCandidate = Join-Path $env:USERPROFILE ".local\bin\uvx.exe"
    if (Test-Path -LiteralPath $uvxCandidate) { $uvx = $uvxCandidate }
}

Write-Host "=== 1/7 TS table export (npm run export) ===" -ForegroundColor Cyan
Push-Location $root
& npm run export
if ($LASTEXITCODE -ne 0) { $failed = $true }
Write-Host "=== 2/7 TS numeric tests (npm test) ===" -ForegroundColor Cyan
& npm test
if ($LASTEXITCODE -ne 0) { $failed = $true }
Pop-Location

Write-Host "=== 3/7 dep_check ===" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "dep_check.ps1")
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "=== 4/7 gdformat --check ===" -ForegroundColor Cyan
if (Get-Command gdformat -ErrorAction SilentlyContinue) {
    & gdformat --check $formatFiles
    if ($LASTEXITCODE -ne 0) { $failed = $true }
} else {
    if ($uvx) {
        & $uvx --from "gdtoolkit==4.*" gdformat --check $formatFiles
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    } else {
        Write-Host "SKIP: gdformat not installed (install uv or gdtoolkit)" -ForegroundColor Yellow
    }
}

Write-Host "=== 5/7 gdlint ===" -ForegroundColor Cyan
if (Get-Command gdlint -ErrorAction SilentlyContinue) {
    & gdlint $dirs
    if ($LASTEXITCODE -ne 0) { $failed = $true }
} else {
    if ($uvx) {
        & $uvx --from "gdtoolkit==4.*" gdlint $dirs
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    } else {
        Write-Host "SKIP: gdlint not installed (install uv or gdtoolkit)" -ForegroundColor Yellow
    }
}

Write-Host "=== 6/7 GdUnit4 ===" -ForegroundColor Cyan
$godot = $null
$godotCandidates = @(
    $env:GODOT_BIN,
    "D:\godot\Godot_v4.7.1-stable_win64.exe",
    (Join-Path (Split-Path -Parent $root) "Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe")
)
if (Get-Command godot -ErrorAction SilentlyContinue) { $godot = (Get-Command godot).Source }
if (-not $godot) {
    foreach ($candidate in $godotCandidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $godot = $candidate; break }
    }
}
if ($godot) {
    # GdUnit runner exit codes (addons/gdUnit4/src/core/runners/GdUnitTestSessionRunner.gd):
    # 0=success, 100=test failures/errors, 101=orphan warning,
    # 103=headless rejected, 104=godot version, 105=script errors at discovery.
    # Fake-green guard: GdUnit quits via an async chain (gc -> frames -> quit(code)),
    # so if the engine dies early the intended exit code never reaches the process.
    # We therefore verify the exit code against the known set AND the output shape.
    $gdunitKnownExitCodes = @(0, 100, 101, 103, 104, 105)
    $gdunitErrorMarkers = @("Abnormal exit", "SCRIPT ERROR", "Parse Error")
    $gdunitLines = @()
    $gdunitExit = -1
    Push-Location $root
    # Build import/class caches first: -s script mode cannot resolve addon
    # class_name types (e.g. GdUnitTestCIRunner) on a fresh .godot cache.
    & $godot --headless --path $root --import 2>&1 | Out-Null
    # Reset so a failed launch cannot inherit the previous step's exit code.
    $global:LASTEXITCODE = $null
    & $godot --headless --path $root -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/ --ignoreHeadlessMode 2>&1 | Tee-Object -Variable gdunitLines
    if ($null -ne $LASTEXITCODE) { $gdunitExit = $LASTEXITCODE }
    Pop-Location
    $gdunitText = ($gdunitLines | ForEach-Object { [string]$_ }) -join "`n"
    $gdunitFailReasons = @()
    if ($gdunitKnownExitCodes -notcontains $gdunitExit) {
        $gdunitFailReasons += "exit code $gdunitExit is not a known GdUnit exit code (engine died before reporting?)"
    }
    if ($gdunitExit -ne 0) {
        $gdunitFailReasons += "exit code $gdunitExit (GdUnit reports success as 0)"
    }
    foreach ($marker in $gdunitErrorMarkers) {
        if ($gdunitText.Contains($marker)) {
            $gdunitFailReasons += "output contains discovery-phase error marker '$marker'"
        }
    }
    if (-not $gdunitText.Contains("Exit code:")) {
        $gdunitFailReasons += "output is missing the 'Exit code:' completion line (test run did not reach its summary)"
    }
    if ($gdunitFailReasons.Count -gt 0) {
        $failed = $true
        Write-Host "GdUnit4: FAIL" -ForegroundColor Red
        foreach ($reason in $gdunitFailReasons) {
            Write-Host "  - $reason" -ForegroundColor Red
        }
    }

    # 7/7 Parity: regenerate TS expected logs (npm run parity also refreshes
    # resources/config), then run the GDScript engine on the same seeds and
    # diff line by line. Exit code nonzero or missing marker = formula drift.
    Write-Host "=== 7/7 Parity (TS vs GD) ===" -ForegroundColor Cyan
    & npm run parity
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    $global:LASTEXITCODE = $null
    & $godot --headless --path $root -s res://tests/parity_runner.gd 2>&1 | Tee-Object -Variable parityLines
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    $parityText = ($parityLines | ForEach-Object { [string]$_ }) -join "`n"
    if (-not $parityText.Contains("PARITY OK")) {
        $failed = $true
        Write-Host "parity: FAIL (missing PARITY OK marker)" -ForegroundColor Red
    }
} else {
    Write-Host "SKIP: godot not found (set GODOT_BIN or add godot to PATH)" -ForegroundColor Yellow
    Write-Host "SKIP: parity needs godot" -ForegroundColor Yellow
}

if ($failed) { Write-Host "check_all: FAILED" -ForegroundColor Red; exit 1 }
Write-Host "check_all: ALL OK" -ForegroundColor Green
exit 0
