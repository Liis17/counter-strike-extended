<#
.SYNOPSIS
  Копирует проектные ассеты Counter-Strike поверх базовых ассетов runtime.

.DESCRIPTION
  Идемпотентный скрипт: файлы из src/cse/cstrike/** копируются в
  runtime/cstrike/** с перезаписью одноимённых оригинальных файлов.
  Перед копированием BSP-карты проверяются на зацикленные ambient_generic;
  для их проектных WAV без RIFF cue-маркера добавляется точка цикла.
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

function Get-EntityKeyValue {
  param(
    [Parameter(Mandatory = $true)] [string]$Body,
    [Parameter(Mandatory = $true)] [string]$Key
  )

  $pattern = '"' + [regex]::Escape($Key) + '"\s+"([^"]*)"'
  $match = [regex]::Match(
    $Body,
    $pattern,
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
  )

  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return $null
}

function Convert-ToSoundRelativePath {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $normalized = $Path.Trim().Replace('\', '/')
  while ($normalized.StartsWith('/')) {
    $normalized = $normalized.Substring(1)
  }

  while ($normalized.StartsWith('./', [StringComparison]::Ordinal)) {
    $normalized = $normalized.Substring(2)
  }

  if ($normalized.StartsWith('sound/', [StringComparison]::OrdinalIgnoreCase)) {
    $normalized = $normalized.Substring(6)
  }

  return $normalized
}

function Get-BspEntityLump {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $stream = [IO.File]::OpenRead($Path)
  $reader = $null

  try {
    # BSP header: version + 15 lumps, each with offset and length.
    if ($stream.Length -lt 124) {
      return $null
    }

    $reader = New-Object IO.BinaryReader($stream)
    $null = $reader.ReadInt32()
    $entityOffset = $reader.ReadInt32()
    $entityLength = $reader.ReadInt32()

    if ($entityOffset -lt 0 -or $entityLength -le 0) {
      return $null
    }

    $entityEnd = [int64]$entityOffset + [int64]$entityLength
    if ($entityEnd -gt $stream.Length) {
      return $null
    }

    $stream.Seek($entityOffset, [IO.SeekOrigin]::Begin) | Out-Null
    $entityBytes = $reader.ReadBytes($entityLength)
    if ($entityBytes.Length -ne $entityLength) {
      return $null
    }

    return [Text.Encoding]::ASCII.GetString($entityBytes)
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

function Get-BspLoopedAmbientSoundPaths {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $entityText = Get-BspEntityLump -Path $Path
  if ([string]::IsNullOrWhiteSpace($entityText)) {
    return
  }

  $entities = [regex]::Matches($entityText, '(?ms)\{(?<body>.*?)\}')
  foreach ($entity in $entities) {
    $body = $entity.Groups['body'].Value
    $classname = Get-EntityKeyValue -Body $body -Key 'classname'
    if ($classname -ine 'ambient_generic') {
      continue
    }

    $spawnFlagsText = Get-EntityKeyValue -Body $body -Key 'spawnflags'
    $spawnFlags = 0
    if (-not [string]::IsNullOrWhiteSpace($spawnFlagsText)) {
      if (-not [int]::TryParse($spawnFlagsText, [ref]$spawnFlags)) {
        continue
      }
    }

    # SF_AMBIENT_SOUND_NOT_LOOPING = 32.
    if (($spawnFlags -band 32) -ne 0) {
      continue
    }

    $message = Get-EntityKeyValue -Body $body -Key 'message'
    if ([string]::IsNullOrWhiteSpace($message) -or $message[0] -in @('!', '#', '*')) {
      continue
    }

    $soundPath = Convert-ToSoundRelativePath -Path $message
    if ([IO.Path]::GetExtension($soundPath) -ieq '.wav') {
      Write-Output $soundPath
    }
  }
}

function Get-WavChunks {
  param([Parameter(Mandatory = $true)] [byte[]]$Bytes)

  if ($Bytes.Length -lt 12 -or
      [Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne 'RIFF' -or
      [Text.Encoding]::ASCII.GetString($Bytes, 8, 4) -ne 'WAVE') {
    throw 'Файл не является RIFF/WAVE'
  }

  $riffSize = [uint64][BitConverter]::ToUInt32($Bytes, 4)
  if ($riffSize + 8 -gt $Bytes.Length) {
    throw 'RIFF/WAVE имеет обрезанный размер'
  }

  $chunks = @()
  $offset = 12
  while ($offset + 8 -le $Bytes.Length) {
    $chunkLength = [uint64][BitConverter]::ToUInt32($Bytes, $offset + 4)
    $chunkEnd = [uint64]$offset + 8 + $chunkLength
    if ($chunkEnd -gt $Bytes.Length) {
      throw "WAV chunk выходит за пределы файла (offset $offset)"
    }

    $chunks += [pscustomobject]@{
      Id = [Text.Encoding]::ASCII.GetString($Bytes, $offset, 4)
      Offset = $offset
      Length = $chunkLength
    }

    $nextOffset = $chunkEnd + ($chunkLength % 2)
    if ($nextOffset -le $offset -or $nextOffset -gt $Bytes.Length) {
      break
    }

    $offset = [int]$nextOffset
  }

  return $chunks
}

function Test-WavLoopCue {
  param([Parameter(Mandatory = $true)] [string]$Path)

  $bytes = [IO.File]::ReadAllBytes($Path)
  $chunks = @(Get-WavChunks -Bytes $bytes)
  $fmtChunk = $chunks | Where-Object { $_.Id -eq 'fmt ' } | Select-Object -First 1
  $dataChunk = $chunks | Where-Object { $_.Id -eq 'data' } | Select-Object -First 1
  if ($null -eq $fmtChunk -or $fmtChunk.Length -lt 16 -or $null -eq $dataChunk) {
    throw "WAV не содержит корректные fmt/data chunks: $Path"
  }

  $blockAlign = [uint16][BitConverter]::ToUInt16($bytes, $fmtChunk.Offset + 20)
  if ($blockAlign -eq 0) {
    throw "WAV содержит нулевой block align: $Path"
  }

  $totalSamples = [uint64]($dataChunk.Length / $blockAlign)
  foreach ($chunk in $chunks) {
    if ($chunk.Id -ne 'cue ') {
      continue
    }

    if ($chunk.Length -lt 28) {
      throw "WAV содержит слишком короткий cue chunk: $Path"
    }

    $cuePoints = [uint64][BitConverter]::ToUInt32($bytes, $chunk.Offset + 8)
    if ($cuePoints -eq 0) {
      throw "WAV содержит пустой cue chunk: $Path"
    }

    if ($cuePoints -gt [math]::Floor(($chunk.Length - 4) / 24)) {
      throw "WAV содержит обрезанные cue-записи: $Path"
    }

    if ([Text.Encoding]::ASCII.GetString($bytes, $chunk.Offset + 20, 4) -ne 'data') {
      throw "WAV cue не ссылается на data chunk: $Path"
    }

    $sampleOffset = [uint64][BitConverter]::ToUInt32($bytes, $chunk.Offset + 32)
    if ($sampleOffset -ge $totalSamples) {
      throw "WAV cue указывает за пределы data: $Path"
    }

    return $true
  }

  return $false
}

function Add-WavLoopCue {
  param([Parameter(Mandatory = $true)] [string]$Path)

  if (Test-WavLoopCue -Path $Path) {
    return $false
  }

  $bytes = [IO.File]::ReadAllBytes($Path)
  $cue = New-Object byte[] 36
  [Array]::Copy([Text.Encoding]::ASCII.GetBytes('cue '), 0, $cue, 0, 4)
  [Array]::Copy([BitConverter]::GetBytes([uint32]28), 0, $cue, 4, 4)
  [Array]::Copy([BitConverter]::GetBytes([uint32]1), 0, $cue, 8, 4)
  [Array]::Copy([BitConverter]::GetBytes([uint32]1), 0, $cue, 12, 4)
  [Array]::Copy([Text.Encoding]::ASCII.GetBytes('data'), 0, $cue, 20, 4)

  $updated = New-Object byte[] ($bytes.Length + $cue.Length)
  [Array]::Copy($bytes, 0, $updated, 0, $bytes.Length)
  [Array]::Copy($cue, 0, $updated, $bytes.Length, $cue.Length)
  [Array]::Copy([BitConverter]::GetBytes([uint32]($updated.Length - 8)), 0, $updated, 4, 4)

  $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
  try {
    [IO.File]::WriteAllBytes($temporary, $updated)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  }
  finally {
    if (Test-Path -LiteralPath $temporary) {
      Remove-Item -LiteralPath $temporary -Force
    }
  }

  return $true
}

$sourceSoundRoot = Join-Path $src 'sound'
$sourceSounds = @{}
if (Test-Path -LiteralPath $sourceSoundRoot -PathType Container) {
  foreach ($soundFile in @(Get-ChildItem -LiteralPath $sourceSoundRoot -Recurse -File)) {
    $relativeSound = $soundFile.FullName.Substring($sourceSoundRoot.Length + 1).Replace('\', '/')
    $sourceSounds[$relativeSound] = $soundFile.FullName
  }
}

$loopedSoundPaths = @{}
$mapRoots = @(
  (Join-Path $Root 'src\cse\maps'),
  (Join-Path $src 'maps'),
  (Join-Path $dst 'maps')
)
foreach ($mapRoot in $mapRoots) {
  if (-not (Test-Path -LiteralPath $mapRoot -PathType Container)) {
    continue
  }

  foreach ($map in @(Get-ChildItem -LiteralPath $mapRoot -Recurse -File -Filter '*.bsp')) {
    foreach ($soundPath in @(Get-BspLoopedAmbientSoundPaths -Path $map.FullName)) {
      $loopedSoundPaths[$soundPath] = $true
    }
  }
}

$loopChecked = 0
$loopFixed = 0
foreach ($soundPath in $loopedSoundPaths.Keys) {
  if (-not $sourceSounds.ContainsKey($soundPath)) {
    continue
  }

  $sourcePath = $sourceSounds[$soundPath]
  $loopChecked++
  if (Test-WavLoopCue -Path $sourcePath) {
    Write-Output "LOOP OK: $soundPath"
    continue
  }

  if ($DryRun) {
    Write-Output "LOOP FIX: $soundPath (dry-run — RIFF cue будет добавлен)"
    continue
  }

  if (Add-WavLoopCue -Path $sourcePath) {
    Write-Output "LOOP FIX: $soundPath (добавлен RIFF cue)"
    $loopFixed++
  }
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
Write-Output "Looped ambient WAVs checked: $loopChecked; fixed: $loopFixed"
if ($DryRun) {
  Write-Output "Would copy: $copied file(s)"
  Write-Output '(dry-run — файлы не записывались)'
}
else {
  Write-Output "Copied: $copied file(s)"
}
