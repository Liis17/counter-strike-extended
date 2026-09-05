<#
.SYNOPSIS
  Компилирует собственные карты CSE внешним J.A.C.K./ZHLT-тулчейном.

.DESCRIPTION
  Карты из src/cse/maps/build-list.txt проходят последовательный pipeline
  hlcsg -> hlbsp -> hlvis -> hlrad во временном build/cse-maps/. В runtime
  ничего не устанавливается: это делает отдельный install_cse_maps.ps1.

  Отсутствующий toolchain считается штатным пропуском для локальной среды.
  Ошибка уже запущенного компилятора останавливает сборку и не оставляет
  пригодный к установке manifest.

.PARAMETER DryRun
  Показывает источники, цели и команды без запуска компиляторов.

.PARAMETER Root
  Корень репозитория (по умолчанию — родитель папки tools/).

.PARAMETER ToolchainRoot
  Папка с hlcsg.exe, hlbsp.exe, hlvis.exe и hlrad.exe. Если параметр не
  задан, используется CSE_MAP_TOOLCHAIN_ROOT, затем путь J.A.C.K. по умолчанию.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [string]$Root,
  [string]$ToolchainRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}
else {
  $Root = (Resolve-Path -LiteralPath $Root).Path
}

if ([string]::IsNullOrWhiteSpace($ToolchainRoot)) {
  $ToolchainRoot = $env:CSE_MAP_TOOLCHAIN_ROOT
}
if ([string]::IsNullOrWhiteSpace($ToolchainRoot)) {
  $ToolchainRoot = 'C:\Program Files\J.A.C.K.\halflife'
}

$mapRoot = Join-Path $Root 'src\cse\maps'
$buildRoot = Join-Path $Root 'build\cse-maps'
$workRoot = Join-Path $buildRoot 'work'
$outputRoot = Join-Path $buildRoot 'output'
$manifestPath = Join-Path $buildRoot 'manifest.json'
$buildListPath = Join-Path $mapRoot 'build-list.txt'
$runtimeCstrike = Join-Path $Root 'runtime\cstrike'

if (-not (Test-Path -LiteralPath $buildListPath -PathType Leaf)) {
  throw "Список сборки карт не найден: $buildListPath"
}

$mapNames = @(
  foreach ($line in Get-Content -LiteralPath $buildListPath) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or
        $trimmed.StartsWith('#') -or
        $trimmed.StartsWith('//')) {
      continue
    }

    $mapName = ($trimmed -split '\s+', 2)[0].ToLowerInvariant()
    if ($mapName -notmatch '^[a-z0-9_]+$') {
      throw "Недопустимое имя карты в build-list.txt: $mapName"
    }

    $sourceMap = Join-Path $mapRoot "$mapName.map"
    if (-not (Test-Path -LiteralPath $sourceMap -PathType Leaf)) {
      throw "Исходник карты не найден: $sourceMap"
    }

    $mapName
  }
)

if ($mapNames.Count -eq 0) {
  throw "Список сборки карт пуст: $buildListPath"
}

$compilerNames = @('hlcsg', 'hlbsp', 'hlvis', 'hlrad')
$compilerPaths = @{}
$missingCompilers = @()
foreach ($compilerName in $compilerNames) {
  $compilerPath = Join-Path $ToolchainRoot "$compilerName.exe"
  $compilerPaths[$compilerName] = $compilerPath
  if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    $missingCompilers += $compilerPath
  }
}

Write-Output "Map source root: $mapRoot"
Write-Output "Toolchain root: $ToolchainRoot"
Write-Output "Build root: $buildRoot"
Write-Output "Install target: $(Join-Path $runtimeCstrike 'maps')"

foreach ($mapName in $mapNames) {
  $sourceMap = Join-Path $mapRoot "$mapName.map"
  $buildOutput = Join-Path $outputRoot "$mapName.bsp"
  Write-Output "MAP: $mapName"
  Write-Output "  source: $sourceMap"
  Write-Output "  output: $buildOutput"
  Write-Output "  target: $(Join-Path $runtimeCstrike "maps\$mapName.bsp")"
  Write-Output "  pipeline: hlcsg -> hlbsp -> hlvis -> hlrad"
}

function Write-EmptyManifest {
  param([Parameter(Mandatory = $true)] [string[]]$Skipped)

  if ($DryRun) {
    return
  }

  if (-not (Test-Path -LiteralPath $buildRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
  }

  $manifest = [ordered]@{
    version = 1
    built = @()
    skipped = @($Skipped)
  }
  $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

if ($missingCompilers.Count -gt 0) {
  Write-Host "WARNING: J.A.C.K./ZHLT compiler is missing; CSE maps will be skipped." -ForegroundColor Red
  foreach ($missingCompiler in $missingCompilers) {
    Write-Host "  missing: $missingCompiler" -ForegroundColor Red
  }
  Write-EmptyManifest -Skipped $mapNames
  if ($DryRun) {
    Write-Output '(dry-run — компиляторы не запускались)'
  }
  else {
    Write-Output "Skipped: $($mapNames.Count) map(s)"
  }
  return
}

$requiredWads = @(
  (Join-Path $Root 'runtime\valve\halflife.wad'),
  (Join-Path $runtimeCstrike 'cstrike.wad')
)
foreach ($wad in $requiredWads) {
  if (-not (Test-Path -LiteralPath $wad -PathType Leaf)) {
    throw "Штатный WAD для компиляции не найден: $wad"
  }
}

if ($DryRun) {
  foreach ($mapName in $mapNames) {
    Write-Output "DRY-RUN: $mapName — WADs: halflife.wad, cstrike.wad"
    foreach ($compilerName in $compilerNames) {
      Write-Output "  & $($compilerPaths[$compilerName]) -console 0 -chart -threads 4 $mapName -low -wadautodetect"
    }
  }
  Write-Output '(dry-run — файлы и BSP не записывались)'
  return
}

New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
Write-EmptyManifest -Skipped @($mapNames)

$builtMaps = New-Object System.Collections.Generic.List[object]
foreach ($mapName in $mapNames) {
  $sourceMap = Join-Path $mapRoot "$mapName.map"
  $mapWork = Join-Path $workRoot $mapName
  $mapOutput = Join-Path $outputRoot "$mapName.bsp"

  New-Item -ItemType Directory -Path $mapWork -Force | Out-Null
  Copy-Item -LiteralPath $sourceMap -Destination (Join-Path $mapWork "$mapName.map") -Force
  foreach ($wad in $requiredWads) {
    Copy-Item -LiteralPath $wad -Destination (Join-Path $mapWork (Split-Path -Leaf $wad)) -Force
  }

  foreach ($compilerName in $compilerNames) {
    $logPath = Join-Path $mapWork "$compilerName.log"
    $arguments = @('-console', '0', '-chart', '-threads', '4', $mapName, '-low', '-wadautodetect')
    Write-Output "BUILD: $mapName / $compilerName"

    Push-Location $mapWork
    try {
      & $compilerPaths[$compilerName] @arguments *> $logPath
      $exitCode = $LASTEXITCODE
    }
    finally {
      Pop-Location
    }

    if ($exitCode -ne 0) {
      $tail = @(Get-Content -LiteralPath $logPath -Tail 40 -ErrorAction SilentlyContinue)
      if ($tail.Count -gt 0) {
        Write-Output ($tail -join [Environment]::NewLine)
      }
      throw "$compilerName завершился с кодом $exitCode для карты $mapName"
    }
  }

  $compiledBsp = Join-Path $mapWork "$mapName.bsp"
  if (-not (Test-Path -LiteralPath $compiledBsp -PathType Leaf)) {
    throw "Компилятор не создал BSP: $compiledBsp"
  }

  Copy-Item -LiteralPath $compiledBsp -Destination $mapOutput -Force
  $builtMaps.Add([ordered]@{
      name = $mapName
      bsp = "output/$mapName.bsp"
    })
}

$finalManifest = [ordered]@{
  version = 1
  built = @($builtMaps)
  skipped = @()
}
$finalManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Output "Built: $($builtMaps.Count) map(s)"
