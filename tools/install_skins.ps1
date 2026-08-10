<#
.SYNOPSIS
  Генерирует производные модели скинов из лицензированных исходных моделей runtime/.

.DESCRIPTION
  Идемпотентный скрипт: повторный запуск безопасно перезаписывает выходные модели.
  Рецепты: src/cse/cstrike/scripts/CseSkinRecipes.txt
  Выход: runtime/cstrike/models/cse/

.PARAMETER DryRun
  Только показать рецепты, без записи моделей.

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

$generator = Join-Path $Root 'tools\mdl_recolor.py'
$recipes = Join-Path $Root 'src\cse\cstrike\scripts\CseSkinRecipes.txt'
$gameRoot = Join-Path $Root 'runtime\cstrike'

foreach ($path in @($generator, $recipes, $gameRoot)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Path not found: $path"
  }
}

$python = Get-Command py.exe -ErrorAction SilentlyContinue
$pythonArgs = @(
  $generator,
  '--recipes', $recipes,
  '--root', $gameRoot
)
if ($DryRun) {
  $pythonArgs += '--dry-run'
}

if ($null -ne $python) {
  & $python.Source -3 @pythonArgs
}
else {
  $python = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($null -eq $python) {
    throw 'Python 3 not found: install Python or add py.exe/python.exe to PATH.'
  }
  & $python.Source @pythonArgs
}

if ($LASTEXITCODE -ne 0) {
  throw "Model generator failed with exit code $LASTEXITCODE"
}

if ($DryRun) {
  Write-Output 'DRY: install_skins complete'
}
else {
  Write-Output 'OK: cstrike/models/cse/*.mdl'
}
