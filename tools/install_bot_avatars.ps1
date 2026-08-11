<#
.SYNOPSIS
  Копирует аватары ботов и их список из src/cse/ в runtime/.

.DESCRIPTION
  Идемпотентный скрипт: повторный запуск безопасно перезаписывает целевые файлы.
  Источник: src/cse/cstrike/gfx/cse/avatars/*      -> runtime/cstrike/gfx/cse/avatars/*
            src/cse/cstrike/scripts/CseBotAvatars.txt -> runtime/cstrike/scripts/CseBotAvatars.txt

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

$srcImages = Join-Path $Root 'src\cse\cstrike\gfx\cse\avatars'
$srcList   = Join-Path $Root 'src\cse\cstrike\scripts\CseBotAvatars.txt'
$dstImages = Join-Path $Root 'runtime\cstrike\gfx\cse\avatars'
$dstList   = Join-Path $Root 'runtime\cstrike\scripts\CseBotAvatars.txt'

if (-not (Test-Path -LiteralPath $srcImages)) {
  Write-Error "Источник не найден: $srcImages"
  exit 1
}
if (-not (Test-Path -LiteralPath $srcList -PathType Leaf)) {
  Write-Error "Источник не найден: $srcList"
  exit 1
}

$copied = 0

Get-ChildItem -Path $srcImages -File | ForEach-Object {
  $target = Join-Path $dstImages $_.Name

  if ($DryRun) {
    Write-Output "DRY: $($_.FullName) -> $target"
    return
  }

  if (-not (Test-Path -LiteralPath $dstImages)) {
    New-Item -ItemType Directory -Path $dstImages -Force | Out-Null
  }

  Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  Write-Output "OK: cstrike/gfx/cse/avatars/$($_.Name)"
  $copied++
}

if ($DryRun) {
  Write-Output "DRY: $srcList -> $dstList"
}
else {
  $dstListDir = Split-Path $dstList -Parent
  if (-not (Test-Path -LiteralPath $dstListDir)) {
    New-Item -ItemType Directory -Path $dstListDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $srcList -Destination $dstList -Force
  Write-Output 'OK: cstrike/scripts/CseBotAvatars.txt'
  $copied++
}

Write-Output ""
Write-Output "Copied: $copied file(s)"
if ($DryRun) { Write-Output "(dry-run — файлы не записывались)" }
