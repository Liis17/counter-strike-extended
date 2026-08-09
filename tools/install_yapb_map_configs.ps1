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

$gameDir = Join-Path $Root 'runtime\cstrike'
$mapsDir = Join-Path $gameDir 'maps'
$sourceDir = Join-Path $Root 'src\cse\yapb\conf\maps'
$targetDir = Join-Path $gameDir 'addons\yapb\conf\maps'

if (-not (Test-Path -LiteralPath $gameDir -PathType Container)) {
    throw "Game directory not found: $gameDir"
}

$mapNames = @()
if (Test-Path -LiteralPath $mapsDir -PathType Container) {
    $mapNames += @(Get-ChildItem -LiteralPath $mapsDir -Filter '*.bsp' -File |
        ForEach-Object { $_.BaseName.ToLowerInvariant() })
}

$archives = @(Get-ChildItem -LiteralPath $gameDir -File |
    Where-Object { $_.Extension -ieq '.pk3' -or $_.Extension -ieq '.zip' })
if ($archives.Count -gt 0) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    foreach ($archive in $archives) {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($archive.FullName)
        try {
            foreach ($entry in $zip.Entries) {
                $mapMatch = [System.Text.RegularExpressions.Regex]::Match(
                    $entry.FullName,
                    '(^|[/\\])maps[/\\]([^/\\]+)\.bsp$',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
                if ($mapMatch.Success) {
                    $mapNames += $mapMatch.Groups[2].Value.ToLowerInvariant()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }
}

$mapNames = @($mapNames | Sort-Object -Unique)
if ($mapNames.Count -eq 0) {
    Write-Warning "No maps found as loose .bsp files or in .pk3/.zip archives under: $gameDir"
}

if ($mapNames.Count -gt 0 -and -not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    if ($DryRun) {
        Write-Output "DRY-RUN: create directory $sourceDir"
    }
    else {
        New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
    }
}

$createdCount = 0
$existingCount = 0

foreach ($mapName in $mapNames) {
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
    $mode, $mapNames.Count, $createdCount, $existingCount, $sourceConfigs.Count)
