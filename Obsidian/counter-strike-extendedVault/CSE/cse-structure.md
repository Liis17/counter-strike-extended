# cse — Counter-Strike Extended (собственный код проекта)

Parent: [[Index]]
Связанные: [[Локализация]], [[Архитектура]], [[Tooling/Tools]]

## Назначение

`src/cse/` — **единственное место в репозитории**, где хранится собственный код,
ассеты, переводы и конфиги проекта counter-strike-extended. Submodule'и
(`src/xash3d-fwgs/`, `src/cs16-client/`) — сторонний upstream-код, их НЕ правим;
папка `runtime/` gitignored и содержит только собранные артефакты и
лицензированные Steam-ассеты.

## Правило проекта

> **Любые новые моды, переводы, ассеты, конфиги или кастомный код проекта —
> добавлять ТОЛЬКО в `src/cse/`.** Не в submodule, не прямо в `runtime/`,
> не в корень репозитория.

Это правило зафиксировано в `src/cse/README.md` и в `AGENTS.md`.

## Структура

```
src/cse/
├── README.md                       # правило «всё своё здесь»
├── localization/                   # переводы (см. [[Локализация]])
│   ├── valve/resource/             # → runtime/valve/resource/
│   └── cstrike/resource/           # → runtime/cstrike/resource/
├── rich_presence/                  # Steam Rich Presence helper (см. [[rich_presence]])
│   ├── src/main.cpp                # cse_steamrp.exe — LoadLibrary steam_api.dll + SetRichPresence
│   ├── CMakeLists.txt              # сборка x86 (MSVC)
│   ├── steam_appid.txt             # AppID 10 (CS 1.6)
│   └── README.md                   # детали сборки/запуска/ограничений
└── menu/                           # патчи главного меню (см. [[CSE/menu]])
    └── main-menu-simplify.patch    # → src/cs16-client/3rdparty/mainui_cpp/menus/Main.cpp
```

При добавлении нового домена (например, кастомных карт, конфигов, скриптов) —
создать подпапку здесь и зарегистрировать её в install-скрипте.

## Развёртывание в runtime/

Копирование `src/cse/` → `runtime/` выполняется идемпотентными install-скриптами
из `tools/`:

| Скрипт | Что копирует |
|--------|--------------|
| `tools/install_localization.ps1` | `src/cse/localization/**` → `runtime/<gamedir>/...` |
| `tools/install_richpresence.ps1` | `src/cse/rich_presence/steam_appid.txt` + собранный `cse_steamrp.exe` → `runtime/` |
| `tools/apply_menu_patch.ps1` | `src/cse/menu/*.patch` → дерево `src/cs16-client/3rdparty/mainui_cpp` (не копирование, а `git apply` перед сборкой) |

Скрипты принимают `-DryRun` для предварительного просмотра и `-Root` для
переопределения корня репозитория.

## История

- Создан при инициализации русской локализации: переведены GameUI движка,
  Half-Life строки, CS 1.6 (оружие/режимы/scoreboard), mainui, токены Steam RP.
- Добавлен домен `rich_presence/` — внешний C++ wrapper `cse_steamrp.exe`,
  выставляющий Steam Rich Presence через динамическую загрузку `steam_api.dll`
  (без правки субмодуля движка и без proprietary headers).
- Добавлен домен `menu/` — патч упрощённого главного меню. Первый случай, когда
  изменение по природе своей нельзя вынести из submodule (C++ внутри mainui_cpp),
  поэтому в `src/cse/` лежит `.patch`, а не исходник.
