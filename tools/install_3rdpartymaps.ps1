<#
.SYNOPSIS
  Копирует сторонние карты и их ресурсы в runtime/cstrike/.

.DESCRIPTION
  Идемпотентный скрипт: все файлы из src/3rdpartymaps/** копируются в
  runtime/cstrike/** с сохранением относительных путей и перезаписью
  одноимённых файлов. Файлы, которых нет в src/3rdpartymaps/, скрипт не
  удаляет.

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

$sourceDir = Join-Path $Root 'src\3rdpartymaps'
$targetDir = Join-Path $Root 'runtime\cstrike'

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
  throw "Источник не найден: $sourceDir"
}
if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
  throw "Целевой cstrike не найден: $targetDir"
}

$files = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File)
$copied = 0

foreach ($file in $files) {
  $relative = $file.FullName.Substring($sourceDir.Length + 1)
  $target = Join-Path $targetDir $relative

  if ($DryRun) {
    Write-Output "DRY-RUN: $relative -> $target"
    $copied++
    continue
  }

  $targetParent = Split-Path -Path $target -Parent
  if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
  }

  Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  Write-Output "OK: $relative"
  $copied++
}

if ($DryRun) {
  Write-Output "Would copy: $copied file(s)"
  Write-Output '(dry-run — файлы не записывались)'
}
else {
  Write-Output "Copied: $copied file(s)"
}
