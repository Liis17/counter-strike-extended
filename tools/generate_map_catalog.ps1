<#
.SYNOPSIS
  Генерирует каталог происхождения карт для меню создания сервера.

.DESCRIPTION
  Читает versioned-шаблон из src/cse, добавляет в него имена BSP из
  src/3rdpartymaps/maps/ и записывает результат в runtime/cstrike/scripts/.
  Список карт, добавленных игроком вручную, в каталог не попадает: меню
  вычисляет его как остаток от maps.lst.

.PARAMETER DryRun
  Только показать результат и статистику, без записи в runtime/.

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

$templatePath = Join-Path $Root 'src\cse\cstrike\scripts\CseMapCatalog.json'
$thirdPartyMapsPath = Join-Path $Root 'src\3rdpartymaps\maps'
$runtimeCstrikePath = Join-Path $Root 'runtime\cstrike'
$targetPath = Join-Path $runtimeCstrikePath 'scripts\CseMapCatalog.json'

if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
  throw "Map catalog template not found: $templatePath"
}
if (-not (Test-Path -LiteralPath $thirdPartyMapsPath -PathType Container)) {
  throw "Third-party maps directory not found: $thirdPartyMapsPath"
}
if (-not $DryRun -and -not (Test-Path -LiteralPath $runtimeCstrikePath -PathType Container)) {
  throw "Target cstrike directory not found: $runtimeCstrikePath"
}

function Normalize-MapName {
  param(
    [Parameter(Mandatory = $true)] [string]$Value,
    [Parameter(Mandatory = $true)] [string]$Field
  )

  $name = $Value.Trim().ToLowerInvariant()
  if ($name.EndsWith('.bsp', [StringComparison]::OrdinalIgnoreCase)) {
    $name = $name.Substring(0, $name.Length - 4)
  }

  if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/]') {
    throw "Invalid map name in field ${Field}: '$Value'"
  }

  return $name
}

function Normalize-MapNames {
  param(
    [AllowNull()] [object]$Value,
    [Parameter(Mandatory = $true)] [string]$Field
  )

  $names = foreach ($item in @($Value)) {
    if ($null -eq $item) {
      throw "Field $Field contains an empty map name"
    }

    Normalize-MapName -Value ([string]$item) -Field $Field
  }

  return @($names | Sort-Object -Unique)
}

try {
  $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
}
catch {
  throw "Unable to read JSON template $templatePath`: $($_.Exception.Message)"
}

foreach ($field in @('version', 'official', 'cse', 'third_party')) {
  if ($null -eq $template.PSObject.Properties[$field]) {
    throw "Template field '$field' is missing: $templatePath"
  }
}

if ([int]$template.version -ne 1) {
  throw "Unsupported map catalog version: $($template.version)"
}

$official = @(Normalize-MapNames -Value $template.official -Field 'official')
$cse = @(Normalize-MapNames -Value $template.cse -Field 'cse')

$thirdParty = @(
  Get-ChildItem -LiteralPath $thirdPartyMapsPath -Filter '*.bsp' -File |
    ForEach-Object { Normalize-MapName -Value $_.BaseName -Field 'third_party' } |
    Sort-Object -Unique
)

$catalog = [ordered]@{
  version = 1
  official = $official
  cse = $cse
  third_party = $thirdParty
}
$json = $catalog | ConvertTo-Json -Depth 3

Write-Host "Map catalog: official=$($official.Count), cse=$($cse.Count), third_party=$($thirdParty.Count)"
if ($DryRun) {
  Write-Host "DryRun: file was not written ($targetPath)"
  return
}

$targetDirectory = Split-Path -Parent $targetPath
if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($targetPath, $json + [Environment]::NewLine, $utf8)
Write-Host "Map catalog written: $targetPath"
