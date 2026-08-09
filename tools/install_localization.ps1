<#
.SYNOPSIS
  Копирует файлы локализации из src/cse/localization/ в runtime/.

.DESCRIPTION
  Идемпотентный скрипт: повторный запуск безопасно перезаписывает целевые файлы.
  Источник: src/cse/localization/<gamedir>/resource/* -> runtime/<gamedir>/resource/*
  Не затрагивает *_english.txt файлы (они лежат рядом и принадлежат Steam-ассетам).

.PARAMETER DryRun
  Только показать, что будет скопировано, без записи.

.PARAMETER Root
  Корень репозитория (по умолчанию — родитель папки tools/).
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$src = Join-Path $Root 'src\cse\localization'
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
$skipped = 0

Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
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
