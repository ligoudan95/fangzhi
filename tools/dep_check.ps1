# Layer dependency direction and pure-logic dependency check.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\dep_check.ps1
# Layers: infra -> config -> battle -> logic -> view. Higher may reference lower.
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $root "scripts"
$layers = @("infra", "config", "battle", "logic", "view")
$layerIndex = @{}
for ($i = 0; $i -lt $layers.Count; $i++) { $layerIndex[$layers[$i]] = $i }

$exempt = @(
    # "scripts\infra\boot.gd"
)
$classLayer = @{}
$gdEntries = @()
$tscnEntries = @()

foreach ($layer in $layers) {
    $dir = Join-Path $srcRoot $layer
    if (-not (Test-Path $dir)) { continue }
    foreach ($file in (Get-ChildItem -Path $dir -Recurse -Filter "*.gd")) {
        $rel = $file.FullName.Substring($root.Length + 1)
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $gdEntries += ,@($rel, $layer, $raw)
        $match = [regex]::Match($raw, '(?m)^class_name\s+(\w+)')
        if ($match.Success) { $classLayer[$match.Groups[1].Value] = $layer }
    }
}

# Scenes are view-owned composition roots, including nested scene directories.
$scenesRoot = Join-Path $root "scenes"
if (Test-Path $scenesRoot) {
    foreach ($file in (Get-ChildItem -Path $scenesRoot -Recurse -Filter "*.tscn")) {
        $rel = $file.FullName.Substring($root.Length + 1)
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $tscnEntries += ,@($rel, "view", $raw)
    }
}

$violations = @()
$engineTypes = @(
    "Node", "Node2D", "Node3D", "Control", "SceneTree", "PackedScene", "CanvasItem",
    "ResourceLoader", "Input", "DisplayServer", "RenderingServer", "PhysicsServer", "AudioServer"
)

foreach ($entry in $gdEntries) {
    $rel = $entry[0]
    $layer = $entry[1]
    $content = $entry[2]
    $normRel = $rel -replace "/", "\"
    if ($exempt -contains $normRel) { continue }

    foreach ($className in $classLayer.Keys) {
        $refLayer = $classLayer[$className]
        if ($layerIndex[$refLayer] -gt $layerIndex[$layer]) {
            $pattern = "(?<![\w.])" + [regex]::Escape($className) + "(?!\w)"
            if ($content -cmatch $pattern) {
                $violations += "${rel}: references upper-layer class $className ($refLayer)"
            }
        }
    }

    $loads = [regex]::Matches($content, '(?:preload|load)\s*\(\s*"([^"]+)"')
    foreach ($load in $loads) {
        $resourcePath = $load.Groups[1].Value
        $match = [regex]::Match($resourcePath, '^res://scripts/(\w+)/')
        if ($match.Success) {
            $target = $match.Groups[1].Value
            if ($layerIndex.ContainsKey($target) -and ($layerIndex[$target] -gt $layerIndex[$layer])) {
                $violations += "${rel}: cross-layer preload/load ${resourcePath} ($target)"
            }
        }
    }

    if ($layer -eq "battle" -or $layer -eq "logic") {
        foreach ($engineType in $engineTypes) {
            $pattern = "(?<![\w.])" + [regex]::Escape($engineType) + "(?!\w)"
            if ($content -cmatch $pattern) {
                $violations += "${rel}: pure $layer layer references engine type $engineType"
            }
        }
        if ($content -cmatch '(?m)^\s*extends\s+(?!RefCounted\b)\w+') {
            $violations += "${rel}: pure $layer layer must extend RefCounted when it declares extends"
        }
        if ($content -cmatch 'res://scenes/') {
            $violations += "${rel}: pure $layer layer references scene resources"
        }
    }
}

foreach ($entry in $tscnEntries) {
    $rel = $entry[0]
    $layer = $entry[1]
    $content = $entry[2]
    $refs = [regex]::Matches($content, '\[ext_resource[^\]]*?path="(res://scripts/[^\"]+)"')
    foreach ($ref in $refs) {
        $resourcePath = $ref.Groups[1].Value
        $match = [regex]::Match($resourcePath, '^res://scripts/(\w+)/')
        if ($match.Success) {
            $target = $match.Groups[1].Value
            if ($layerIndex.ContainsKey($target) -and ($layerIndex[$target] -gt $layerIndex[$layer])) {
                $violations += "${rel}: cross-layer tscn ext_resource ${resourcePath} ($target)"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host ("dep_check: " + $violations.Count + " violation(s)") -ForegroundColor Red
    foreach ($violation in $violations) { Write-Host ("  " + $violation) -ForegroundColor Red }
    exit 1
}
Write-Host ("dep_check: OK (checked " + $gdEntries.Count + " .gd files, " + $tscnEntries.Count + " scene files, " + $classLayer.Count + " classes)") -ForegroundColor Green
exit 0
