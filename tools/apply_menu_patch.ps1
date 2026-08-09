<#
.SYNOPSIS
  Применяет патчи меню из src/cse/menu/ к submodule src/cs16-client/3rdparty/mainui_cpp.

.DESCRIPTION
  Идемпотентный скрипт. Патчи — обычные `git diff` по дереву mainui_cpp.
  Если патч уже применён (проверка через `git apply --reverse --check`), шаг пропускается.
  Запускать перед сборкой клиента (build-cse.cmd), т.к. menu.dll собирается из этого submodule.

.PARAMETER DryRun
  Только проверить применимость (`git apply --check`), без записи.

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

$patchDir  = Join-Path $Root 'src\cse\menu'
$targetDir = Join-Path $Root 'src\cs16-client\3rdparty\mainui_cpp'

if (-not (Test-Path -LiteralPath $patchDir)) {
  Write-Error "Папка патчей не найдена: $patchDir"
  exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $targetDir 'menus'))) {
  Write-Error "Submodule mainui_cpp не найден: $targetDir (git submodule update --init --recursive)"
  exit 1
}

$patches = Get-ChildItem -LiteralPath $patchDir -Filter '*.patch' | Sort-Object Name
if (-not $patches) {
  Write-Output "Патчей нет в $patchDir"
  exit 0
}

# git пишет диагностику в stderr — при ErrorActionPreference=Stop это рвёт скрипт,
# поэтому глушим вывод и смотрим только код возврата
function Invoke-GitApply {
  param([string[]]$GitArgs)
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & git -C $targetDir apply @GitArgs 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  return $code
}

foreach ($p in $patches) {
  if ((Invoke-GitApply @('--reverse', '--check', $p.FullName)) -eq 0) {
    Write-Output "SKIP: $($p.Name) — уже применён"
    continue
  }

  if ((Invoke-GitApply @('--check', $p.FullName)) -ne 0) {
    Write-Error "Патч не применяется: $($p.Name) — дерево mainui_cpp изменилось, обнови патч"
    exit 1
  }

  if ($DryRun) {
    Write-Output "DRY: $($p.Name) — применится чисто"
  } else {
    if ((Invoke-GitApply @($p.FullName)) -ne 0) { Write-Error "git apply упал на $($p.Name)"; exit 1 }
    Write-Output "OK: $($p.Name)"
  }
}

Write-Output ''
if ($DryRun) { Write-Output '(dry-run — файлы не изменялись)' }
