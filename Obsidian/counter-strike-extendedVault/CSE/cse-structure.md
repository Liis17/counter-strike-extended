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

Исключение для системы прогрессии: C++-хуки, которые должны попасть внутрь
`client.dll`, находятся в проектном форке `src/cs16-client` по утверждённому
плану; конфиг `CseProgression.txt` и install-скрипт остаются в `src/cse/` и
`tools/`.

## Структура

```
src/cse/
├── README.md                       # правило «всё своё здесь»
├── localization/                   # переводы (см. [[Локализация]])
│   ├── valve/resource/             # → runtime/valve/resource/
│   └── cstrike/resource/           # → runtime/cstrike/resource/
├── cstrike/
│   ├── gameinfo.txt                # → runtime/cstrike/gameinfo.txt (render_picbutton_text, см. [[CSE/menu]])
│   ├── scripts/HudLayout.txt       # → runtime/cstrike/scripts/HudLayout.txt (кастомный HUD, см. [[Client/HUD-layout]])
│   └── scripts/CseProgression.txt  # → runtime/cstrike/scripts/CseProgression.txt (XP/уровни, см. [[CSE/progression]])
├── yapb/
│   └── conf/maps/                  # → runtime/cstrike/addons/yapb/conf/maps/
│       └── <map>.cfg               # per-map YaPB config, default yb_difficulty 0
└── rich_presence/                  # Steam Rich Presence helper (см. [[rich_presence]])
    ├── src/main.cpp                # cse_steamrp.exe — LoadLibrary steam_api.dll + SetRichPresence
    ├── CMakeLists.txt              # сборка x86 (MSVC)
    ├── steam_appid.txt             # AppID 10 (CS 1.6)
    └── README.md                   # детали сборки/запуска/ограничений
```

При добавлении нового домена (например, кастомных карт, конфигов, скриптов) —
создать подпапку здесь и зарегистрировать её в install-скрипте.

## Развёртывание в runtime/

Копирование `src/cse/` → `runtime/` выполняется идемпотентными install-скриптами
из `tools/`:

| Скрипт | Что копирует |
|--------|--------------|
| `tools/install_localization.ps1` | `src/cse/localization/**` → `runtime/<gamedir>/...` |
| `tools/install_gameinfo.ps1` | `src/cse/<gamedir>/gameinfo.txt` → `runtime/<gamedir>/gameinfo.txt` |
| `tools/install_hud_layout.ps1` | `src/cse/cstrike/scripts/HudLayout.txt` → `runtime/cstrike/scripts/HudLayout.txt` |
| `tools/install_progression.ps1` | `src/cse/cstrike/scripts/CseProgression.txt` → `runtime/cstrike/scripts/CseProgression.txt` |
| `tools/install_yapb_map_configs.ps1` | loose `runtime/cstrike/maps/*.bsp` и карты из `.pk3`/`.zip` → создаёт отсутствующие `src/cse/yapb/conf/maps/*.cfg` и копирует их в `runtime/cstrike/addons/yapb/conf/maps/` |
| `tools/install_richpresence.ps1` | `src/cse/rich_presence/steam_appid.txt` + собранный `cse_steamrp.exe` → `runtime/` |

Скрипты принимают `-DryRun` для предварительного просмотра и `-Root` для
переопределения корня репозитория.

## История

- Создан при инициализации русской локализации: переведены GameUI движка,
  Half-Life строки, CS 1.6 (оружие/режимы/scoreboard), mainui, токены Steam RP.
- Добавлен домен `rich_presence/` — внешний C++ wrapper `cse_steamrp.exe`,
  выставляющий Steam Rich Presence через динамическую загрузку `steam_api.dll`
  (без правки субмодуля движка и без proprietary headers).
- Упрощение главного меню (см. [[CSE/menu]]) — исключение из правила: C++ внутри
  mainui_cpp нельзя вынести в `src/cse/`, поэтому правка живёт в форке
  `Liis17/mainui_cpp` (ветка `cs16-client`), как и правки самого клиента.
- Добавлен `cstrike/gameinfo.txt` с `render_picbutton_text 1` — форсирует текстовый
  рендер кнопок главного меню (вместо BMP-атласа `btns_main.bmp` из `extras.pk3`),
  без чего локализация кнопок не работает (см. [[CSE/menu]]).
