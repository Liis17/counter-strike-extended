<#
.SYNOPSIS
  Копирует Steam Rich Presence helper в runtime/.

.DESCRIPTION
  Идемпотентный скрипт. Копирует:
    - src/cse/rich_presence/steam_appid.txt          -> runtime/steam_appid.txt
    - src/cse/rich_presence/build/.../cse_steamrp.exe -> runtime/cse_steamrp.exe
  exe ищется в build/Release/ (VS generator) или build/ (Ninja).
  steam_api.dll НЕ копируется — он proprietary, кладётся вручную (см. README).

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

# $PSScriptRoot недоступен в значениях param() по умолчанию (PS 5.1 + CmdletBinding)
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

$rpDir = Join-Path $Root 'src\cse\rich_presence'
$dst   = Join-Path $Root 'runtime'

if (-not (Test-Path -LiteralPath $rpDir)) {
  Write-Error "Источник не найден: $rpDir"
  exit 1
}
if (-not (Test-Path -LiteralPath $dst)) {
  Write-Error "Целевой runtime не найден: $dst"
  exit 1
}

# 1. steam_appid.txt
$appidSrc = Join-Path $rpDir 'steam_appid.txt'
$appidDst = Join-Path $dst   'steam_appid.txt'
if (-not (Test-Path -LiteralPath $appidSrc)) {
  Write-Error "steam_appid.txt не найден: $appidSrc"
  exit 1
}
if ($DryRun) {
  Write-Output "DRY: $appidSrc -> $appidDst"
} else {
  Copy-Item -LiteralPath $appidSrc -Destination $appidDst -Force
  Write-Output "OK: steam_appid.txt"
}

# 2. cse_steamrp.exe — ищем в типовых расположениях сборки CMake
$exeCandidates = @(
  (Join-Path $rpDir 'build\Release\cse_steamrp.exe'),
  (Join-Path $rpDir 'build\cse_steamrp.exe'),
  (Join-Path $rpDir 'build\RelWithDebInfo\cse_steamrp.exe'),
  (Join-Path $rpDir 'build\Debug\cse_steamrp.exe')
)
$exeSrc = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $exeSrc) {
  Write-Error "cse_steamrp.exe не найден ни в одном из ожидаемых мест. Соберите сначала:`n  cd src\cse\rich_presence && cmake -B build -A Win32 && cmake --build build --config Release"
  exit 1
}
$exeDst = Join-Path $dst 'cse_steamrp.exe'
if ($DryRun) {
  Write-Output "DRY: $exeSrc -> $exeDst"
} else {
  Copy-Item -LiteralPath $exeSrc -Destination $exeDst -Force
  Write-Output "OK: cse_steamrp.exe (from $(Split-Path $exeSrc -Leaf))"
}

Write-Output ''
if ($DryRun) { Write-Output '(dry-run — файлы не записывались)' }
