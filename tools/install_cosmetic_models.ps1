<#
.SYNOPSIS
  Генерирует и устанавливает все модели каталога косметики.

.DESCRIPTION
  Декомпилирует stock-модели, применяет палитру/мотив/деталь из
  CseCosmetics.txt и собирает новые GoldSrc .mdl в runtime/cstrike/models/cse/.
  Сам компилятор studiomdl не хранится в репозитории: передайте его путь
  через -StudioMdl или переменную CSE_STUDIOMDL.

.PARAMETER DryRun
  Показать 208 задач без запуска внешних инструментов.

.PARAMETER Mdldec
  Путь к mdldec.exe. По умолчанию ищется в локальной сборке Xash3D.

.PARAMETER StudioMdl
  Путь к официальному/совместимому studiomdl.exe.

.PARAMETER Activities
  Каталог mdldec с activities.txt.

.PARAMETER Root
  Корень репозитория.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [string]$Mdldec,
  [string]$StudioMdl,
  [string]$Activities,
  [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
  $Root = (Resolve-Path -LiteralPath $Root).Path
}

$generator = Join-Path $Root 'tools\generate_cosmetics.py'
$catalog = Join-Path $Root 'src\cse\cstrike\scripts\CseCosmetics.txt'
$gameRoot = Join-Path $Root 'runtime\cstrike'

foreach ($path in @($generator, $catalog, $gameRoot)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Path not found: $path"
  }
}

$python = Get-Command py.exe -ErrorAction SilentlyContinue
if ($null -eq $python) {
  $python = Get-Command python.exe -ErrorAction SilentlyContinue
}
if ($null -eq $python) {
  throw 'Python 3 not found: install Python or add py.exe/python.exe to PATH.'
}
$pythonLauncherArgs = @()
if ($python.Name -eq 'py.exe') {
  $pythonLauncherArgs = @('-3')
}

$pythonArgs = @(
  $generator,
  '--catalog', $catalog,
  '--root', $gameRoot
)

if ($DryRun) {
  $pythonArgs += '--dry-run'
  & $python.Source @pythonLauncherArgs @pythonArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Cosmetic dry-run failed with exit code $LASTEXITCODE"
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Mdldec) -and -not [string]::IsNullOrWhiteSpace($env:CSE_MDLDEC)) {
  $Mdldec = $env:CSE_MDLDEC
}
if ([string]::IsNullOrWhiteSpace($StudioMdl) -and -not [string]::IsNullOrWhiteSpace($env:CSE_STUDIOMDL)) {
  $StudioMdl = $env:CSE_STUDIOMDL
}
if ([string]::IsNullOrWhiteSpace($Mdldec)) {
  $mdldecCandidates = @(
    (Join-Path $Root 'src\xash3d-fwgs\build\utils\mdldec\mdldec.exe'),
    (Join-Path $Root 'build\utils\mdldec\mdldec.exe'),
    (Join-Path $Root 'tools\mdldec.exe')
  )
  $Mdldec = $mdldecCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($StudioMdl)) {
  $studioMdlCandidates = @(
    (Join-Path $Root 'build\studiomdl.exe'),
    (Join-Path $Root 'build\studiomdl-build\studiomdl.exe'),
    (Join-Path $Root 'tools\studiomdl.exe')
  )
  $StudioMdl = $studioMdlCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($Mdldec) -or -not (Test-Path -LiteralPath $Mdldec -PathType Leaf)) {
  throw 'mdldec.exe not found. Build Xash3D with utils enabled or pass -Mdldec <path>.'
}
if ([string]::IsNullOrWhiteSpace($StudioMdl) -or -not (Test-Path -LiteralPath $StudioMdl -PathType Leaf)) {
  throw 'studiomdl.exe not found. Pass -StudioMdl <path> or set CSE_STUDIOMDL.'
}
if ([string]::IsNullOrWhiteSpace($Activities)) {
  $Activities = Join-Path $Root 'src\xash3d-fwgs\utils\mdldec\res'
}
if (-not (Test-Path -LiteralPath $Activities -PathType Container) -and
    -not (Test-Path -LiteralPath $Activities -PathType Leaf)) {
  throw "mdldec activities path not found: $Activities"
}

$pythonArgs += @(
  '--mdldec', (Resolve-Path -LiteralPath $Mdldec).Path,
  '--studiomdl', (Resolve-Path -LiteralPath $StudioMdl).Path,
  '--activities', (Resolve-Path -LiteralPath $Activities).Path
)

& $python.Source @pythonLauncherArgs @pythonArgs
if ($LASTEXITCODE -ne 0) {
  throw "Cosmetic model generator failed with exit code $LASTEXITCODE"
}

Write-Output 'OK: cstrike/models/cse/*.mdl'
