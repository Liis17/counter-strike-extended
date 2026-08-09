<#
.SYNOPSIS
  Копирует gameinfo.txt из src/cse/<gamedir>/ в runtime/<gamedir>/.

.DESCRIPTION
  Идемпотентный скрипт: повторный запуск безопасно перезаписывает целевые файлы.
  Источник: src/cse/<gamedir>/gameinfo.txt -> runtime/<gamedir>/gameinfo.txt

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

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

$src = Join-Path $Root 'src\cse'
$dst = Join-Path $Root 'runtime'

if (-not (Test-Path -LiteralPath $src)) {
  Write-Error "Источник не найден: $src"
  exit 1
}
if (-not (Test-Path -LiteralPath $dst)) {
  Write-Error "Целевой runtime не найден: $dst"
  exit 1
}

$copied = 0

Get-ChildItem -Path $src -Recurse -Filter 'gameinfo.txt' | ForEach-Object {
  $rel = $_.FullName.Substring($src.Length + 1)
  $target = Join-Path $dst $rel
  $targetDir = Split-Path $target -Parent

  if ($DryRun) {
    Write-Output "DRY: $($_.FullName) -> $target"
    return
  }

  if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  Write-Output "OK: $rel"
  $copied++
}

Write-Output ""
Write-Output "Copied: $copied file(s)"
if ($DryRun) { Write-Output "(dry-run — файлы не записывались)" }
