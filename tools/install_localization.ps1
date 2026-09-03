<#
.SYNOPSIS
  Копирует файлы локализации из src/cse/localization/ в runtime/.

.DESCRIPTION
  Идемпотентный скрипт: повторный запуск безопасно перезаписывает целевые файлы.
  Источник: src/cse/localization/<gamedir>/resource/* -> runtime/<gamedir>/resource/*
  После копирования добавляет CSE scoreboard tokens в существующий UTF-16
  cstrike_english.txt и профильные mainui tokens в mainui_russian.txt,
  не заменяя upstream-словарь.

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

# cstrike_english.txt поставляется клиентом и поэтому не хранится в src/cse.
# Localize() читает именно этот UTF-16 словарь, так что добавляем только наши
# короткие scoreboard-подписи, сохраняя все upstream-токены и делая операцию
# идемпотентной. 10_loc_english.vdf остаётся источником тех же строк для
# систем, которые загружают VDF напрямую.
$english = Join-Path $dst 'cstrike\resource\cstrike_english.txt'
if (Test-Path -LiteralPath $english) {
  if ($DryRun) {
    Write-Output "DRY: patch cstrike/resource/cstrike_english.txt with CSE scoreboard tokens"
  } else {
    $bytes = [IO.File]::ReadAllBytes($english)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
      $encoding = [Text.Encoding]::Unicode
      $content = $encoding.GetString($bytes, 2, $bytes.Length - 2)
      if ($content -notmatch '(?m)^"CSE_SB_K"') {
        $lineBreak = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $marker = '"Cstrike_ACCOUNT"'
        $markerAt = $content.IndexOf($marker)
        if ($markerAt -ge 0) {
          $lineEnd = $content.IndexOf($lineBreak, $markerAt)
          if ($lineEnd -lt 0) { $lineEnd = $content.Length }
          $tokens = ($lineBreak +
            '"CSE_SB_K"                 "K"' + $lineBreak +
            '"CSE_SB_D"                 "D"' + $lineBreak +
            '"CSE_SB_PING"              "PING"' + $lineBreak +
            '"CSE_SB_BOT"               "BOT"' + $lineBreak +
            '"CSE_SB_SPECTATORS"        "Spectators"' + $lineBreak +
            '"CSE_SB_PLAYERS"           "Players"')
          $content = $content.Insert($lineEnd, $tokens)
          [IO.File]::WriteAllText($english, $content, $encoding)
          Write-Output "OK: patched cstrike/resource/cstrike_english.txt"
        } else {
          Write-Warning "cstrike_english.txt has no Cstrike_ACCOUNT marker; scoreboard tokens were not added"
        }
      }
    } else {
      Write-Warning "cstrike_english.txt is not UTF-16 LE; scoreboard tokens were not added"
    }
  }
}

# mainui_russian.txt хранится в UTF-16 и содержит upstream-токены. Добавляем
# подписи экрана прогрессии после копирования, чтобы исходный словарь можно
# было хранить в репозитории без риска для его кодировки. Операция идемпотентна.
$mainuiRussian = Join-Path $dst 'valve\resource\mainui_russian.txt'
if (Test-Path -LiteralPath $mainuiRussian) {
  if ($DryRun) {
    Write-Output "DRY: patch valve/resource/mainui_russian.txt with CSE profile tokens"
  } else {
    $bytes = [IO.File]::ReadAllBytes($mainuiRussian)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
      $encoding = [Text.Encoding]::Unicode
      $content = $encoding.GetString($bytes, 2, $bytes.Length - 2)
      if ($content -notmatch '(?m)^"Daily challenges"') {
        $lineBreak = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $marker = '"Weapon skins"'
        $markerAt = $content.IndexOf($marker)
        if ($markerAt -ge 0) {
          $lineEnd = $content.IndexOf($lineBreak, $markerAt)
          if ($lineEnd -lt 0) { $lineEnd = $content.Length }
          $tokens = ($lineBreak +
            '"Daily challenges"                                                        "Ежедневные задания"' + $lineBreak +
            '"Weekly challenges"                                                       "Еженедельные задания"' + $lineBreak +
            '"Match history"                                                           "История матчей"' + $lineBreak +
            '"Map statistics"                                                          "Статистика карт"' + $lineBreak +
            '"Weapon statistics"                                                       "Статистика оружия"' + $lineBreak +
            '"Headshots"                                                               "Попадания в голову"' + $lineBreak +
            '"Completed"                                                               "Выполнено"' + $lineBreak +
            '"Interrupted"                                                             "Прервано"' + $lineBreak +
            '"Task"                                                                    "Задание"' + $lineBreak +
            '"Progress"                                                                "Прогресс"' + $lineBreak +
            '"Reward"                                                                  "Награда"' + $lineBreak +
            '"Map"                                                                     "Карта"' + $lineBreak +
            '"UTC"                                                                     "UTC"' + $lineBreak +
            '"XP"                                                                      "XP"' + $lineBreak +
            '"Result"                                                                  "Результат"' + $lineBreak +
            '"Rounds"                                                                  "Раунды"' + $lineBreak +
            '"K / D / HS"                                                              "У / С / ВГ"' + $lineBreak +
            '"Deaths"                                                                  "Смерти"' + $lineBreak +
            '"Matches"                                                                 "Матчи"' + $lineBreak +
            '"Go back to the Main Menu."                                               "Вернуться в главное меню."')
          $content = $content.Insert($lineEnd, $tokens)
          [IO.File]::WriteAllText($mainuiRussian, $content, $encoding)
          Write-Output "OK: patched valve/resource/mainui_russian.txt"
        } else {
          Write-Warning "mainui_russian.txt has no Weapon skins marker; profile tokens were not added"
        }
      }
    } else {
      Write-Warning "mainui_russian.txt is not UTF-16 LE; profile tokens were not added"
    }
  }
}

Write-Output ""
Write-Output "Copied: $copied file(s)"
if ($DryRun) { Write-Output "(dry-run — файлы не записывались)" }
