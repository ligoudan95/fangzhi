# Layer dependency direction check (fangzhi AGENTS.md layering rule)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\dep_check.ps1
# Exit code 1 on violation
# Checks .gd files (class_name refs + preload/load paths) and .tscn files
# (ext_resource paths) for upward cross-layer references.
# Layers (docs/13 SS3): res://scripts/ infra -> config -> battle -> logic -> view
# Higher layer may reference lower; never the reverse.
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $root "scripts"
$layers = @("infra", "config", "battle", "logic", "view")
$layerIndex = @{}
for ($i = 0; $i -lt $layers.Count; $i++) { $layerIndex[$layers[$i]] = $i }

# Files exempt from the check ( autoload carriers that must reference all
# layers, e.g. a future boot injector ). Use relative path with backslashes.
$exempt = @(
    # "scripts\infra\boot.gd"
)

# class_name table is built from .gd files only.
$classLayer = @{}
# Each entry: @(relPath, layer, rawContent)
$gdEntries = @()
$tscnEntries = @()

foreach ($layer in $layers) {
    $dir = Join-Path $srcRoot $layer
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in (Get-ChildItem -Path $dir -Recurse -Filter "*.gd")) {
        $rel = $f.FullName.Substring($root.Length + 1)
        $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $gdEntries += ,@($rel, $layer, $raw)
        $m = [regex]::Match($raw, '(?m)^class_name\s+(\w+)')
        if ($m.Success) { $classLayer[$m.Groups[1].Value] = $layer }
    }
    foreach ($f in (Get-ChildItem -Path $dir -Recurse -Filter "*.tscn")) {
        $rel = $f.FullName.Substring($root.Length + 1)
        $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $tscnEntries += ,@($rel, $layer, $raw)
    }
}

$violations = @()

foreach ($entry in $gdEntries) {
    $rel = $entry[0]
    $layer = $entry[1]
    $content = $entry[2]
    $normRel = $rel -replace "/", "\"
    if ($exempt -contains $normRel) { continue }

    foreach ($cls in $classLayer.Keys) {
        $refLayer = $classLayer[$cls]
        if ($layerIndex[$refLayer] -gt $layerIndex[$layer]) {
            if ($content -cmatch "(?<![\w.])$cls(?!\w)") {
                $violations += "${rel}: references upper-layer class $cls ($refLayer)"
            }
        }
    }

    $preloads = [regex]::Matches($content, '(?:preload|load)\s*\(\s*"([^"]+)"')
    foreach ($p in $preloads) {
        $res = $p.Groups[1].Value
        $m2 = [regex]::Match($res, '^res://(?:scripts/)?(\w+)/')
        if ($m2.Success) {
            $target = $m2.Groups[1].Value
            if ($layerIndex.ContainsKey($target) -and ($layerIndex[$target] -gt $layerIndex[$layer])) {
                $violations += "${rel}: cross-layer preload/load ${res} ($target)"
            }
        }
    }
}

# .tscn check: tolerate any ext_resource attribute order/type (format 2/3);
# only flag paths whose scripts/ path segment is a higher layer than the file's own layer.
foreach ($entry in $tscnEntries) {
    $rel = $entry[0]
    $layer = $entry[1]
    $content = $entry[2]
    $normRel = $rel -replace "/", "\"
    if ($exempt -contains $normRel) { continue }

    $extRefs = [regex]::Matches($content, '\[ext_resource[^\]]*?path="(res://[^"]+)"')
    foreach ($er in $extRefs) {
        $res = $er.Groups[1].Value
        $m2 = [regex]::Match($res, '^res://(?:scripts/)?(\w+)/')
        if ($m2.Success) {
            $target = $m2.Groups[1].Value
            if ($layerIndex.ContainsKey($target) -and ($layerIndex[$target] -gt $layerIndex[$layer])) {
                $violations += "${rel}: cross-layer tscn ext_resource ${res} (${target})"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host ("dep_check: " + $violations.Count + " violation(s)") -ForegroundColor Red
    foreach ($v in $violations) { Write-Host ("  " + $v) -ForegroundColor Red }
    exit 1
}
Write-Host ("dep_check: OK (checked " + $gdEntries.Count + " .gd files, " + $tscnEntries.Count + " .tscn files, " + $classLayer.Count + " classes)") -ForegroundColor Green
exit 0
