<#
.SYNOPSIS
  Устанавливает скомпилированные карты CSE и проверенные .ent/.res.

.DESCRIPTION
  BSP берутся только из build/cse-maps/output/, чей manifest создаёт
  build_cse_maps.ps1. Полные snapshots entity-lump для существующих карт
  сравниваются с BSP: исходные блоки должны идти без изменений, новые блоки
  могут быть только разрешённых классов и укладываться в лимиты v1.

.PARAMETER DryRun
  Проверяет и показывает целевые файлы без копирования и изменения времени.

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

$sourceMapRoot = Join-Path $Root 'src\cse\maps'
$sourceEntRoot = Join-Path $sourceMapRoot 'ent'
$sourceResRoot = Join-Path $sourceMapRoot 'res'
$runtimeCstrike = Join-Path $Root 'runtime\cstrike'
$runtimeMaps = Join-Path $runtimeCstrike 'maps'
$buildRoot = Join-Path $Root 'build\cse-maps'
$buildOutput = Join-Path $buildRoot 'output'
$manifestPath = Join-Path $buildRoot 'manifest.json'

if (-not (Test-Path -LiteralPath $runtimeCstrike -PathType Container)) {
  throw "Целевой cstrike не найден: $runtimeCstrike"
}
if (-not (Test-Path -LiteralPath $runtimeMaps -PathType Container)) {
  if ($DryRun) {
    Write-Output "DRY-RUN: каталог карт будет создан: $runtimeMaps"
  }
  else {
    New-Item -ItemType Directory -Path $runtimeMaps -Force | Out-Null
  }
}

function Get-EntityValue {
  param(
    [Parameter(Mandatory = $true)] [string]$Block,
    [Parameter(Mandatory = $true)] [string]$Key
  )

  $pattern = '(?m)^"' + [regex]::Escape($Key) + '"\s+"([^"]*)"'
  $match = [regex]::Match(
    $Block,
    $pattern,
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
  )
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return $null
}

function Get-TopLevelEntityBlocks {
  param([Parameter(Mandatory = $true)] [string]$Text)

  $blocks = New-Object System.Collections.Generic.List[string]
  $depth = 0
  $start = -1
  $inQuote = $false
  $escaped = $false

  for ($i = 0; $i -lt $Text.Length; $i++) {
    $character = $Text[$i]
    if ($inQuote) {
      if ($escaped) {
        $escaped = $false
      }
      elseif ($character -eq '\') {
        $escaped = $true
      }
      elseif ($character -eq '"') {
        $inQuote = $false
      }
      continue
    }

    if ($character -eq '"') {
      $inQuote = $true
      continue
    }
    if ($character -eq '{') {
      if ($depth -eq 0) {
        $start = $i
      }
      $depth++
      continue
    }
    if ($character -eq '}') {
      $depth--
      if ($depth -lt 0) {
        throw 'Entity snapshot содержит лишнюю закрывающую скобку.'
      }
      if ($depth -eq 0) {
        $blocks.Add($Text.Substring($start, $i - $start + 1))
        $start = -1
      }
    }
  }

  if ($inQuote -or $depth -ne 0) {
    throw 'Entity snapshot имеет незакрытую строку или блок.'
  }

  return @($blocks)
}

function Normalize-EntityBlock {
  param([Parameter(Mandatory = $true)] [string]$Block)

  return $Block.Trim().Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-BspEntityLump {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $stream = [IO.File]::OpenRead($Path)
  $reader = $null
  try {
    if ($stream.Length -lt 124) {
      throw "BSP слишком короткий: $Path"
    }

    $reader = New-Object IO.BinaryReader($stream)
    $null = $reader.ReadInt32()
    $entityOffset = $reader.ReadInt32()
    $entityLength = $reader.ReadInt32()
    if ($entityOffset -lt 0 -or $entityLength -le 0) {
      throw "В BSP отсутствует entity lump: $Path"
    }

    $entityEnd = [int64]$entityOffset + [int64]$entityLength
    if ($entityEnd -gt $stream.Length) {
      throw "Entity lump выходит за пределы BSP: $Path"
    }

    $stream.Seek($entityOffset, [IO.SeekOrigin]::Begin) | Out-Null
    $bytes = $reader.ReadBytes($entityLength)
    if ($bytes.Length -ne $entityLength) {
      throw "Не удалось прочитать entity lump: $Path"
    }

    return [Text.Encoding]::ASCII.GetString($bytes)
  }
  finally {
    if ($null -ne $reader) {
      $reader.Dispose()
    }
    else {
      $stream.Dispose()
    }
  }
}

function Convert-ToRuntimeRelativePath {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $normalized = $Path.Trim().Replace('\', '/')
  while ($normalized.StartsWith('/')) {
    $normalized = $normalized.Substring(1)
  }
  while ($normalized.StartsWith('./', [StringComparison]::Ordinal)) {
    $normalized = $normalized.Substring(2)
  }
  return $normalized
}

function Test-ResourceFile {
  param(
    [Parameter(Mandatory = $true)] [string]$RelativePath,
    [Parameter(Mandatory = $true)] [string]$Context
  )

  $normalized = Convert-ToRuntimeRelativePath -Path $RelativePath
  if ([string]::IsNullOrWhiteSpace($normalized) -or
      $normalized.Contains('..') -or
      $normalized.Contains(':')) {
      throw "Недопустимый resource path в ${Context}: $RelativePath"
  }

  $fullPath = Join-Path $runtimeCstrike ($normalized.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Resource не найден в runtime/cstrike ($Context): $normalized"
  }
}

function Test-EntitySnapshot {
  param(
    [Parameter(Mandatory = $true)] [string]$MapName,
    [Parameter(Mandatory = $true)] [string]$EntityPath,
    [Parameter(Mandatory = $true)] [string]$BspPath
  )

  $baseText = Get-BspEntityLump -Path $BspPath
  $snapshotText = [IO.File]::ReadAllText($EntityPath, [Text.Encoding]::ASCII)
  $baseBlocks = @(Get-TopLevelEntityBlocks -Text $baseText)
  $snapshotBlocks = @(Get-TopLevelEntityBlocks -Text $snapshotText)

  if ($snapshotBlocks.Count -lt $baseBlocks.Count) {
    throw "$MapName.ent теряет entity-блоки BSP: $($snapshotBlocks.Count) < $($baseBlocks.Count)"
  }

  for ($i = 0; $i -lt $baseBlocks.Count; $i++) {
    if ((Normalize-EntityBlock -Block $snapshotBlocks[$i]) -cne
        (Normalize-EntityBlock -Block $baseBlocks[$i])) {
      throw "$MapName.ent изменяет исходный entity-блок BSP с индексом $i"
    }
  }

  $addedBlocks = @()
  if ($snapshotBlocks.Count -gt $baseBlocks.Count) {
    $addedBlocks = @($snapshotBlocks[$baseBlocks.Count..($snapshotBlocks.Count - 1)])
  }

  $allowedClasses = @(
    'ambient_generic', 'infodecal', 'env_rain', 'env_snow', 'env_fog',
    'env_sprite', 'env_glow', 'cycler_wreckage'
  )
  $props = 0
  $ambients = 0
  $decals = 0
  $weather = 0
  $fog = 0

  foreach ($block in $addedBlocks) {
    $classname = Get-EntityValue -Block $block -Key 'classname'
    if ([string]::IsNullOrWhiteSpace($classname)) {
      throw "$MapName.ent содержит добавленный блок без classname"
    }

    if ($classname -like 'light*' -or
        $classname -ieq 'cycler' -or
        $classname -ieq 'cycler_sprite') {
      throw "$MapName.ent содержит запрещённый класс: $classname"
    }

    if ($classname -like 'func_*' -and $block -match '(?ms)\r?\n\s*\{\s*\(') {
      throw "$MapName.ent содержит запрещённый brush func_*: $classname"
    }
    if ($allowedClasses -notcontains $classname.ToLowerInvariant()) {
      throw "$MapName.ent содержит недопустимый добавленный класс: $classname"
    }

    switch ($classname.ToLowerInvariant()) {
      'ambient_generic' {
        $ambients++
        $message = Get-EntityValue -Block $block -Key 'message'
        if ([string]::IsNullOrWhiteSpace($message)) {
          throw "$MapName.ent: ambient_generic без message"
        }
        if ($message[0] -notin @('!', '#', '*')) {
          $soundPath = Convert-ToRuntimeRelativePath -Path $message
          if (-not $soundPath.StartsWith('sound/', [StringComparison]::OrdinalIgnoreCase)) {
            $soundPath = "sound/$soundPath"
          }
          Test-ResourceFile -RelativePath $soundPath -Context "$MapName.ent ambient_generic"
        }
      }
      'infodecal' {
        $decals++
      }
      'env_rain' { $weather++ }
      'env_snow' { $weather++ }
      'env_fog' { $fog++ }
      'cycler_wreckage' {
        $props++
        $model = Get-EntityValue -Block $block -Key 'model'
        if ([string]::IsNullOrWhiteSpace($model)) {
          throw "$MapName.ent: cycler_wreckage без model"
        }
        Test-ResourceFile -RelativePath $model -Context "$MapName.ent cycler_wreckage"
      }
      'env_sprite' {
        $model = Get-EntityValue -Block $block -Key 'model'
        if ([string]::IsNullOrWhiteSpace($model)) {
          throw "$MapName.ent: env_sprite без model"
        }
        Test-ResourceFile -RelativePath $model -Context "$MapName.ent env_sprite"
      }
      'env_glow' {
        $model = Get-EntityValue -Block $block -Key 'model'
        if ([string]::IsNullOrWhiteSpace($model)) {
          throw "$MapName.ent: env_glow без model"
        }
        Test-ResourceFile -RelativePath $model -Context "$MapName.ent env_glow"
      }
    }
  }

  if ($addedBlocks.Count -gt 24 -or $props -gt 8 -or $ambients -gt 4 -or
      $decals -gt 12 -or $weather -gt 1 -or $fog -gt 1) {
    throw "$MapName.ent превышает лимиты v1: new=$($addedBlocks.Count), props=$props, ambient=$ambients, decals=$decals, weather=$weather, fog=$fog"
  }

  return [pscustomobject]@{
    Map = $MapName
    BaseEntities = $baseBlocks.Count
    NewEntities = $addedBlocks.Count
    Props = $props
    Ambients = $ambients
    Decals = $decals
    Weather = $weather
    Fog = $fog
  }
}

function Test-ResourceManifest {
  param(
    [Parameter(Mandatory = $true)] [string]$MapName,
    [Parameter(Mandatory = $true)] [string]$ResourcePath,
    [switch]$RequireEntitySnapshot,
    [switch]$CheckFiles
  )

  $lines = @(Get-Content -LiteralPath $ResourcePath)
  $normalizedLines = @(
    foreach ($line in $lines) {
      $trimmed = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed) -or
          $trimmed.StartsWith('//') -or
          $trimmed.StartsWith('#')) {
        continue
      }
      if ($trimmed.Contains('..') -or $trimmed.Contains(':') -or $trimmed.Contains('\')) {
        throw "$MapName.res содержит небезопасный путь: $trimmed"
      }
      $trimmed
    }
  )

  if ($CheckFiles) {
    foreach ($resource in $normalizedLines) {
      Test-ResourceFile -RelativePath $resource -Context "$MapName.res"
    }
  }

  if ($RequireEntitySnapshot) {
    $required = "maps/$MapName.ent"
    if ($normalizedLines -notcontains $required) {
      throw "$MapName.res обязан содержать $required"
    }
  }
}

$installedBsp = 0
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  foreach ($entry in @($manifest.built)) {
    $mapName = [string]$entry.name
    if ($mapName -notmatch '^[a-z0-9_]+$') {
      throw "manifest содержит недопустимое имя карты: $mapName"
    }

    $sourceBsp = Join-Path $buildOutput "$mapName.bsp"
    if (-not (Test-Path -LiteralPath $sourceBsp -PathType Leaf)) {
      throw "BSP из manifest не найден: $sourceBsp"
    }

    $targetBsp = Join-Path $runtimeMaps "$mapName.bsp"
    if ($DryRun) {
      Write-Output "DRY-RUN: $sourceBsp -> $targetBsp"
    }
    else {
      $temporary = "$targetBsp.$([Guid]::NewGuid().ToString('N')).tmp"
      try {
        Copy-Item -LiteralPath $sourceBsp -Destination $temporary -Force
        Move-Item -LiteralPath $temporary -Destination $targetBsp -Force
      }
      finally {
        if (Test-Path -LiteralPath $temporary) {
          Remove-Item -LiteralPath $temporary -Force
        }
      }
      Write-Output "OK: maps/$mapName.bsp"
    }
    $installedBsp++
  }
}
else {
  Write-Host 'WARNING: build/cse-maps/manifest.json не найден; собранные CSE BSP пропущены.' -ForegroundColor Red
}

$snapshotCount = 0
if (Test-Path -LiteralPath $sourceEntRoot -PathType Container) {
  foreach ($entityFile in @(Get-ChildItem -LiteralPath $sourceEntRoot -File -Filter '*.ent')) {
    $mapName = $entityFile.BaseName.ToLowerInvariant()
    if ($mapName -notmatch '^[a-z0-9_]+$') {
      throw "Недопустимое имя карты в .ent: $mapName"
    }

    $bspPath = Join-Path $runtimeMaps "$mapName.bsp"
    if (-not (Test-Path -LiteralPath $bspPath -PathType Leaf)) {
      throw "BSP для проверки $mapName.ent не найден: $bspPath"
    }

    $resPath = Join-Path $sourceResRoot "$mapName.res"
    if (-not (Test-Path -LiteralPath $resPath -PathType Leaf)) {
      throw "Для $mapName.ent отсутствует .res: $resPath"
    }

    $stats = Test-EntitySnapshot -MapName $mapName -EntityPath $entityFile.FullName -BspPath $bspPath
    Test-ResourceManifest -MapName $mapName -ResourcePath $resPath -RequireEntitySnapshot
    Write-Output "ENT: $mapName — base=$($stats.BaseEntities), new=$($stats.NewEntities), props=$($stats.Props), ambient=$($stats.Ambients), decals=$($stats.Decals), weather=$($stats.Weather), fog=$($stats.Fog)"

    $targetEnt = Join-Path $runtimeMaps "$mapName.ent"
    $targetRes = Join-Path $runtimeMaps "$mapName.res"
    $bspTime = (Get-Item -LiteralPath $bspPath).LastWriteTimeUtc
    if ($DryRun) {
      Write-Output "DRY-RUN: $($entityFile.FullName) -> $targetEnt (mtime > $bspTime)"
      Write-Output "DRY-RUN: $resPath -> $targetRes"
    }
    else {
      Copy-Item -LiteralPath $entityFile.FullName -Destination $targetEnt -Force
      Copy-Item -LiteralPath $resPath -Destination $targetRes -Force
      [IO.File]::SetLastWriteTimeUtc($targetEnt, $bspTime.AddSeconds(2))
      $installedTime = (Get-Item -LiteralPath $targetEnt).LastWriteTimeUtc
      if ($installedTime -le $bspTime) {
        throw "Не удалось сделать $targetEnt новее BSP"
      }
      Write-Output "OK: maps/$mapName.ent + maps/$mapName.res (mtime > BSP)"
    }
    $snapshotCount++
  }
}

if (Test-Path -LiteralPath $sourceResRoot -PathType Container) {
  foreach ($resourceFile in @(Get-ChildItem -LiteralPath $sourceResRoot -File -Filter '*.res')) {
    $resourceMapName = $resourceFile.BaseName.ToLowerInvariant()
    if ($DryRun) {
      Test-ResourceManifest -MapName $resourceMapName -ResourcePath $resourceFile.FullName
    }
    else {
      Test-ResourceManifest -MapName $resourceMapName -ResourcePath $resourceFile.FullName -CheckFiles
    }
    $targetRes = Join-Path $runtimeMaps $resourceFile.Name
    if ($DryRun) {
      Write-Output "DRY-RUN: $($resourceFile.FullName) -> $targetRes"
    }
    elseif (-not (Test-Path -LiteralPath $targetRes -PathType Leaf)) {
      Copy-Item -LiteralPath $resourceFile.FullName -Destination $targetRes -Force
      Write-Output "OK: maps/$($resourceFile.Name)"
    }
  }
}

if ($DryRun) {
  Write-Output "Would install BSP: $installedBsp; entity snapshots: $snapshotCount"
  Write-Output '(dry-run — файлы не записывались)'
}
else {
  Write-Output "Installed BSP: $installedBsp; entity snapshots: $snapshotCount"
}
