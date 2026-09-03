<#
.SYNOPSIS
  Копирует каталог косметики из src/cse/ в runtime/.

.DESCRIPTION
  Идемпотентно устанавливает CseCosmetics.txt. Производные модели устанавливаются
  отдельным шагом после проверки каталога.

.PARAMETER DryRun
  Только показать целевой путь.

.PARAMETER Root
  Корень репозитория.
#>
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

$src = Join-Path $Root 'src\cse\cstrike\scripts\CseCosmetics.txt'
$dst = Join-Path $Root 'runtime\cstrike\scripts\CseCosmetics.txt'

if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
  throw "Источник не найден: $src"
}

if ($DryRun) {
  Write-Output "DRY: $src -> $dst"
  exit 0
}

$dstDir = Split-Path -Path $dst -Parent
if (-not (Test-Path -LiteralPath $dstDir -PathType Container)) {
  New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
}

Copy-Item -LiteralPath $src -Destination $dst -Force
Write-Output 'OK: cstrike/scripts/CseCosmetics.txt'
