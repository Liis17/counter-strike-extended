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

$sourceDir = Join-Path $Root 'src\cse\cstrike'
$targetDir = Join-Path $Root 'runtime\cstrike'
$fileNames = @('server.cfg', 'cse_map_change.cfg', 'mapcycle.txt')

if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    throw "Game directory not found: $targetDir"
}

foreach ($fileName in $fileNames) {
    $source = Join-Path $sourceDir $fileName
    $target = Join-Path $targetDir $fileName

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Source file not found: $source"
    }

    if ($DryRun) {
        Write-Output "DRY-RUN: $source -> $target"
        continue
    }

    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Output "OK: $fileName"
}

if ($DryRun) {
    Write-Output '(dry-run — файлы не записывались)'
}
