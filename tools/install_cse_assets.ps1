<#
.SYNOPSIS
  Копирует проектные ассеты Counter-Strike поверх базовых ассетов runtime.

.DESCRIPTION
  Идемпотентный скрипт: файлы из src/cse/cstrike/** копируются в
  runtime/cstrike/** с перезаписью одноимённых оригинальных файлов.
  Файлы, которых нет в src/cse/cstrike/, скрипт не удаляет.

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

$src = Join-Path $Root 'src\cse\cstrike'
$dst = Join-Path $Root 'runtime\cstrike'

if (-not (Test-Path -LiteralPath $src -PathType Container)) {
  throw "Источник не найден: $src"
}
if (-not (Test-Path -LiteralPath $dst -PathType Container)) {
  throw "Целевой cstrike не найден: $dst"
}

$files = @(Get-ChildItem -LiteralPath $src -Recurse -File)
$copied = 0

foreach ($file in $files) {
  $relative = $file.FullName.Substring($src.Length + 1)
  $target = Join-Path $dst $relative
  $targetDir = Split-Path -Path $target -Parent

  if ($DryRun) {
    Write-Output "DRY: $($file.FullName) -> $target"
    $copied++
    continue
  }

  if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  Write-Output "OK: $relative"
  $copied++
}

Write-Output ""
if ($DryRun) {
  Write-Output "Would copy: $copied file(s)"
  Write-Output '(dry-run — файлы не записывались)'
}
else {
  Write-Output "Copied: $copied file(s)"
}
