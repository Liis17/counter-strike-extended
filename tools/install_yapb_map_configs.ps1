[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

$mapsDir = Join-Path $Root 'runtime\cstrike\maps'
$sourceDir = Join-Path $Root 'src\cse\yapb\conf\maps'
$targetDir = Join-Path $Root 'runtime\cstrike\addons\yapb\conf\maps'

if (-not (Test-Path -LiteralPath $mapsDir -PathType Container)) {
    throw "Map directory not found: $mapsDir"
}

$maps = @(Get-ChildItem -LiteralPath $mapsDir -Filter '*.bsp' -File | Sort-Object BaseName)
if ($maps.Count -eq 0) {
    throw "No .bsp maps found in: $mapsDir"
}

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    if ($DryRun) {
        Write-Output "DRY-RUN: create directory $sourceDir"
    }
    else {
        New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
    }
}

$createdCount = 0
$existingCount = 0

foreach ($map in $maps) {
    $mapName = $map.BaseName.ToLowerInvariant()
    $sourcePath = Join-Path $sourceDir "$mapName.cfg"

    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        $existingCount++
        continue
    }

    if ($DryRun) {
        Write-Output "DRY-RUN: create $sourcePath"
        $createdCount++
        continue
    }

    [System.IO.File]::WriteAllText(
        $sourcePath,
        ('yb_difficulty 0' + [Environment]::NewLine),
        [System.Text.Encoding]::ASCII
    )
    $createdCount++
}

$sourceConfigs = @()
if (Test-Path -LiteralPath $sourceDir -PathType Container) {
    $sourceConfigs = @(Get-ChildItem -LiteralPath $sourceDir -Filter '*.cfg' -File | Sort-Object Name)
}

if ($DryRun) {
    foreach ($config in $sourceConfigs) {
        Write-Output "DRY-RUN: copy $($config.FullName) -> $(Join-Path $targetDir $config.Name)"
    }
}
else {
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    foreach ($config in $sourceConfigs) {
        Copy-Item -LiteralPath $config.FullName -Destination (Join-Path $targetDir $config.Name) -Force
    }
}

$mode = if ($DryRun) { 'DRY-RUN' } else { 'Complete' }
Write-Output ("{0}: maps found {1}; configs created {2}; configs already present {3}; configs installed {4}" -f `
    $mode, $maps.Count, $createdCount, $existingCount, $sourceConfigs.Count)
