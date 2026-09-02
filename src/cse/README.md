# cse — Counter-Strike Extended (собственные моды/изменения)

Эта папка — **единственное место** в репозитории, где хранятся собственные
ассеты, переводы и конфиги проекта counter-strike-extended. Submodule'и
(`src/xash3d-fwgs/`, `src/cs16-client/`) в основном содержат upstream-код;
утверждённая клиентская логика, которая должна собираться внутрь `client.dll`,
ведётся в проектном fork `src/cs16-client` и фиксируется gitlink'ом из этого
репозитория.

Содержимое `src/cse/` отслеживается в git. При сборке/развёртывании в `runtime/`
копируются только ресурсы, для которых есть соответствующий install-скрипт; исходники
карт остаются source-only до внешней компиляции в BSP (см. ниже).

Готовые сторонние карты, скачанные из интернета вместе с их ресурсами, не
являются собственными ассетами проекта и хранятся отдельно в
src/3rdpartymaps/. Они устанавливаются в runtime/cstrike/ скриптом
tools/install_3rdpartymaps.ps1.

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
│   ├── server.cfg                  # → runtime/cstrike/server.cfg
│   ├── cse_map_change.cfg          # → runtime/cstrike/cse_map_change.cfg (/skip + восстановление правил)
│   ├── mapcycle.txt                # пул карт для случайной ротации
│   ├── gfx/cse/avatars/            # → runtime/cstrike/gfx/cse/avatars/
│   │   └── *.png / *.tga           # аватары ботов, 64x64
│   └── scripts/                    # → runtime/cstrike/scripts/
│       ├── HudLayout.txt           # кастомный HUD-layout
│       ├── CseProgression.txt      # XP и пороги уровней
│       ├── CseBotAvatars.txt       # список аватаров ботов
│       ├── CseMapCatalog.json       # шаблон явных CSE/official списков карт
│       └── CseSkinRecipes.txt      # рецепты перекрасов моделей
├── maps/                            # исходники карт; BSP — производный артефакт
│   ├── cse_test_actions.map         # стенд штатных map actions
│   ├── de_dust2.map                 # декомпилированный исходник карты de_dust2
│   └── de_dust2_generated.wad       # 15 текстур, встроенных в исходный BSP
├── yapb/                           # конфиги YaPB для отдельных карт
│   └── conf/maps/                  # → runtime/cstrike/addons/yapb/conf/maps/
│       └── <map>.cfg               # настройки YaPB для конкретной карты
├── server/                          # серверный CSE-код
│   ├── CMakeLists.txt               # сборка x86 DLL-прокси
│   └── mapcycle_proxy.cpp           # случайная смена карт поверх YaPB
└── rich_presence/                  # Steam Rich Presence helper (внешний wrapper)
    ├── src/main.cpp               # cse_steamrp.exe — грузит steam_api.dll, выставляет RP
    ├── CMakeLists.txt             # сборка x86 (MSVC)
    ├── steam_appid.txt            # AppID 10 (CS 1.6)
    └── README.md                  # детали сборки/запуска
```

## Развёртывание в runtime/

Установить сторонние карты и их ресурсы:

```powershell
tools\install_3rdpartymaps.ps1
```

Сгенерировать каталог происхождения карт после установки ассетов:

```powershell
tools\generate_map_catalog.ps1
```

Скрипт сохраняет в `runtime/cstrike/scripts/CseMapCatalog.json` явные списки `official` и
`cse` из шаблона и отсортированный список BSP из `src/3rdpartymaps/maps/` в `third_party`.
Карты, которые игрок добавит непосредственно в runtime, в JSON не записываются и
определяются меню как `Скачанные карты`.

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

Установить правила выделенного сервера и исходный пул карт:

```powershell
tools\install_server_config.ps1
```

При запуске `server.cmd` `tools/prepare_server_maps.ps1` выбирает случайную стартовую карту и
сохраняет стабильный пул в `runtime/cstrike/cse_map_pool.txt`; `server.cmd <map>` сохраняет
явный выбор стартовой карты. Тренировочные `tr_*` и тестовая карта `cse_test_actions` в пул не входят.

`cse_mapcycle.dll` загружается как серверная DLL-прокси, передаёт YaPB дальше и подменяет только
назначение `pfnChangeLevel`: при `/skip` и штатном завершении матча выбирается случайная валидная
карта из пула, текущая карта исключается, а уже выбранные карты не повторяются до исчерпания пула.
`cse_map_change.cfg` по-прежнему временно завершает карту и восстанавливает правила матча до шести побед.

Прокси собирается и разворачивается в `runtime/cstrike/dlls/` автоматически шагом `build-cse.cmd`.
Она ожидает рядом оригинальный `yapb.dll`; запуск напрямую с `-dll dlls\yapb.dll` обходит случайную ротацию.

Установить аватары ботов (картинки + список):

```powershell
tools\install_bot_avatars.ps1
```

Скрипт автоматически строит `cstrike/scripts/CseBotAvatars.txt` по PNG/TGA-файлам из
`cstrike/gfx/cse/avatars/`, сортируя их по имени; JPG пропускается. Сервер выдаёт каждому
боту случайный свободный номер аватара среди `0..255`, клиент по нему берёт запись из списка —
картинки по сети не передаются, файлы на сервере и у клиентов обязаны совпадать. Формат — TGA32
или PNG 64×64.
Чтобы добавить аватар, достаточно положить файл в каталог и снова запустить скрипт.

Исходники собственных карт находятся в `src/cse/maps/`. Внешний Hammer/J.A.C.K.-тулчейн
компилирует их в BSP; текущий `build-cse.cmd` собственные исходники карт не компилирует.
Готовые сторонние карты из `src/3rdpartymaps/` устанавливаются отдельным скриптом выше.
`de_dust2.map` — приближённая декомпиляция BSP для ручной модификации; исходный BSP
в `runtime/` не перезаписывается.

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

Клиентская C++-логика, которая должна собираться внутрь `client.dll`, живёт в
форке `src/cs16-client`; её конфиги, скрипты установки и прочие проектные
ресурсы по-прежнему хранятся здесь. В частности, сюда входят прогрессия и
логика немедленного переключения оружия (описана в [[Client/cs16-client]]).
