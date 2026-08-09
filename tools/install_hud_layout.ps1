<#
.SYNOPSIS
  Копирует кастомный HudLayout.txt из src/cse/ в runtime/.

.DESCRIPTION
  Идемпотентный скрипт: повторный запуск безопасно перезаписывает целевой файл.
  Источник: src/cse/cstrike/scripts/HudLayout.txt -> runtime/cstrike/scripts/HudLayout.txt

.PARAMETER DryRun
  Только показать, что будет скопировано, без записи.

.PARAMETER Root
  Корень репозитория (по умолчанию — родитель папки tools/).
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

$src = Join-Path $Root 'src\cse\cstrike\scripts\HudLayout.txt'
$dst = Join-Path $Root 'runtime\cstrike\scripts\HudLayout.txt'

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
Write-Output 'OK: cstrike/scripts/HudLayout.txt'
