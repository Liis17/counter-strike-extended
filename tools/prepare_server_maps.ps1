[CmdletBinding()]
param(
    [string]$Root,
    [string]$StartMap
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
    $Root = (Resolve-Path -LiteralPath $Root).Path
}

$source = Join-Path $Root 'src\cse\cstrike\mapcycle.txt'
$target = Join-Path $Root 'runtime\cstrike\mapcycle.txt'
$poolTarget = Join-Path $Root 'runtime\cstrike\cse_map_pool.txt'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Source map cycle not found: $source"
}

$maps = @(
    foreach ($line in Get-Content -LiteralPath $source) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('//') -or $line.StartsWith('#')) {
            continue
        }

        $map = ($line -split '\s+', 2)[0].ToLowerInvariant()
        if ($map -match '^[a-z0-9_]+$') {
            $map
        }
    }
)
$maps = @($maps | Select-Object -Unique)

if ($maps.Count -lt 2) {
    throw 'The map cycle must contain at least two map names.'
}

function Shuffle-MapNames {
    param([Parameter(Mandatory)][string[]]$Values)

    $result = @($Values)
    for ($i = $result.Count - 1; $i -gt 0; $i--) {
        $j = Get-Random -Minimum 0 -Maximum ($i + 1)
        $temporary = $result[$i]
        $result[$i] = $result[$j]
        $result[$j] = $temporary
    }

    $result
}

$requestedStart = $null
if (-not [string]::IsNullOrWhiteSpace($StartMap)) {
    $requestedStart = $StartMap.Trim().ToLowerInvariant()
    if ($requestedStart -notmatch '^[a-z0-9_]+$') {
        throw "Invalid map name: $StartMap"
    }
}

if ($requestedStart) {
    $start = $requestedStart
}
else {
    $randomized = @(Shuffle-MapNames -Values $maps)
    $start = $randomized[0]
}

$targetDir = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# ReGameDLL keeps reading mapcycle.txt sequentially. The CSE proxy replaces only
# its destination, so both files remain a stable pool rather than a fake queue.
Set-Content -LiteralPath $target -Value $maps -Encoding ASCII
Set-Content -LiteralPath $poolTarget -Value $maps -Encoding ASCII
Write-Output $start
