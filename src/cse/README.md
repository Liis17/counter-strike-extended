# cse — Counter-Strike Extended (собственные моды/изменения)

Эта папка — **единственное место** в репозитории, где хранится собственный код,
ассеты и конфиги проекта counter-strike-extended. Submodule'и (`src/xash3d-fwgs/`,
`src/cs16-client/`) — сторонний upstream-код, их НЕ правим.

Содержимое `src/cse/` отслеживается в git. При сборке/развёртывании в `runtime/`
копируются только ресурсы, для которых есть соответствующий install-скрипт; исходники
карт остаются source-only до внешней компиляции в BSP (см. ниже).

## Структура

```
src/cse/
├── README.md                       # этот файл
├── localization/                   # локализация (русские переводы)
│   ├── valve/resource/             # → runtime/valve/resource/
│   │   ├── gameui_russian.txt     # GameUI движка (меню/настройки)
│   │   ├── valve_russian.txt      # базовые Half-Life строки
│   │   ├── mainui_russian.txt     # mainui (главное меню CS16Client)
│   │   └── 70_loc_russian.vdf     # токены Steam Rich Presence (для HL, appid 70)
│   └── cstrike/resource/           # → runtime/cstrike/resource/
│       └── cstrike_russian.txt    # CS 1.6 (оружие, режимы, scoreboard)
├── cstrike/                        # ресурсы игры CS 1.6
│   ├── gameinfo.txt                # → runtime/cstrike/gameinfo.txt
│   └── scripts/                    # → runtime/cstrike/scripts/
│       ├── HudLayout.txt           # кастомный HUD-layout
│       ├── CseProgression.txt      # XP и пороги уровней
│       └── CseSkinRecipes.txt      # рецепты перекрасов моделей
├── maps/                            # исходники собственных карт; BSP — производный артефакт
│   └── cse_test_actions.map         # стенд штатных map actions
├── yapb/                           # конфиги YaPB для отдельных карт
│   └── conf/maps/                  # → runtime/cstrike/addons/yapb/conf/maps/
│       └── <map>.cfg               # настройки YaPB для конкретной карты
└── rich_presence/                  # Steam Rich Presence helper (внешний wrapper)
    ├── src/main.cpp               # cse_steamrp.exe — грузит steam_api.dll, выставляет RP
    ├── CMakeLists.txt             # сборка x86 (MSVC)
    ├── steam_appid.txt            # AppID 10 (CS 1.6)
    └── README.md                  # детали сборки/запуска
```

## Развёртывание в runtime/

Скопировать локализацию в `runtime/`:

```powershell
tools\install_localization.ps1
```

Установить кастомный HUD-layout в `runtime/`:

```powershell
tools\install_hud_layout.ps1
```

Установить конфиг прогрессии:

```powershell
tools\install_progression.ps1
```

Исходники карт находятся в `src/cse/maps/`. Внешний Hammer/J.A.C.K.-тулчейн компилирует их в BSP;
текущий `build-cse.cmd` карты не компилирует и не устанавливает.

Сгенерировать производные модели скинов из лицензированных моделей в `runtime/`:

```powershell
tools\install_skins.ps1
```

Рецепты хранятся в `cstrike/scripts/CseSkinRecipes.txt`; в git попадают только рецепты и генератор,
а созданные `.mdl` остаются в gitignored `runtime/`.

Создать и скопировать конфиги YaPB для всех карт из `runtime/`:

```powershell
tools\install_yapb_map_configs.ps1
```

Собрать и скопировать Steam Rich Presence helper:

```powershell
# один раз — собрать (x86, MSVC)
cd src\cse\rich_presence
cmake -B build -A Win32
cmake --build build --config Release
cd ..\..\..
# разнести в runtime/
tools\install_richpresence.ps1
# один раз — скопировать steam_api.dll из установленной HL/CS (proprietary, в репо не кладётся)
Copy-Item 'C:\Program Files (x86)\Steam\steamapps\common\Half-Life\steam_api.dll' 'runtime\steam_api.dll'
```

Install-скрипты идемпотентны: повторный запуск безопасно перезаписывает целевые
файлы, а уже существующие исходные конфиги карт не перезаписываются.

## Правило

**Любые новые моды, переводы, ассеты или конфиги проекта — добавлять только
сюда, в `src/cse/`.** Не в submodule'и, не прямо в `runtime/` (он gitignored),
не в корень репозитория. Это правило зафиксировано в Obsidian
(`Obsidian/counter-strike-extendedVault/CSE/cse-structure.md`).

Исключение для утверждённого плана прогрессии: C++-интеграция, которая должна
собираться внутрь `client.dll`, живёт в форке `src/cs16-client`; её конфиги,
скрипты установки и прочие проектные ресурсы по-прежнему хранятся здесь.
