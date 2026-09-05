# cse — Counter-Strike Extended (собственный код проекта)

Parent: [[Index]]
Связанные: [[Локализация]], [[Архитектура]], [[CSE/map-atmosphere]], [[Tooling/Tools]], [[Tooling/server-mapcycle]]

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

Исключение для клиентской логики, которая должна попасть внутрь `client.dll`:
она находится в проектном форке `src/cs16-client`; конфиги, install-скрипты и
прочие проектные ресурсы остаются в `src/cse/` и `tools/`. Сюда входят система
прогрессии и немедленное переключение оружия по цифровым слотам и колесу
(см. [[Client/cs16-client]]).

Исключение расширено для аватаров ботов: назначает их **сервер**, а серверный код —
это движок. Правка живёт в форке `src/xash3d-fwgs` (`SV_FakeConnect()`), потому что
YaPB — submodule на upstream `yapb/yapb`, и путь через него потребовал бы отдельного
форка чужого репозитория. Картинки, список и install-скрипт — по-прежнему в `src/cse/`
и `tools/` (см. [[Client/HUD-TeamBar]]).

Готовые сторонние карты и их комплектные ресурсы — отдельное исключение из
правила выше: они хранятся в `src/3rdpartymaps/`, потому что повторяют структуру
игровой папки `cstrike` (например, `maps/`, `models/`, `sound/` и `sprites/`).
Это не собственные моды проекта; в `runtime/cstrike/` они устанавливаются
скриптом `tools/install_3rdpartymaps.ps1`.

## Структура

```
src/cse/
├── README.md                       # правило «всё своё здесь»
├── localization/                   # переводы (см. [[Локализация]])
│   ├── valve/resource/             # → runtime/valve/resource/
│   └── cstrike/resource/           # → runtime/cstrike/resource/
├── cstrike/
│   ├── gameinfo.txt                # → runtime/cstrike/gameinfo.txt (render_picbutton_text, см. [[CSE/menu]])
│   ├── server.cfg                  # → runtime/cstrike/server.cfg (dedicated-настройки)
│   ├── cse_map_change.cfg          # → runtime/cstrike/cse_map_change.cfg (/skip + восстановление правил)
│   ├── mapcycle.txt                # исходный пул карт для случайной ротации
│   ├── gfx/cse/avatars/*.{png,tga}     # → runtime/cstrike/gfx/cse/avatars/ (аватары ботов, см. [[Client/HUD-TeamBar]])
│   ├── scripts/HudLayout.txt           # → runtime/cstrike/scripts/HudLayout.txt (кастомный HUD, см. [[Client/HUD-layout]])
│   ├── scripts/CseProgression.txt      # → runtime/cstrike/scripts/CseProgression.txt (XP/уровни, см. [[CSE/progression]])
│   ├── scripts/CseCosmetics.txt        # → runtime/cstrike/scripts/CseCosmetics.txt (каталог оружия/вариантов)
│   ├── scripts/CseBotAvatars.txt       # → runtime/cstrike/scripts/CseBotAvatars.txt (список аватаров ботов)
│   ├── scripts/CseMapCatalog.json       # versioned-шаблон происхождения карт (third_party генерируется)
│   ├── sound/                          # → runtime/cstrike/sound/ (проектные звуковые замены; loop cue проверяет install-скрипт)
│   └── scripts/CseSkinRecipes.txt      # рецепты производных моделей из runtime-ассетов
├── maps/                                # исходники карт, компилируемые внешним Hammer/J.A.C.K.
│   ├── build-list.txt                   # явный список автоматической сборки
│   ├── cse_test_actions.map
│   ├── cse_lobby.map                    # техдвор без objectives/ботов
│   ├── ent/<map>.ent                    # полные snapshots для stock-map dressing
│   ├── res/<map>.res                    # resource manifests; .ent обязан быть перечислен
│   ├── de_dust2.map                     # декомпилированный исходник, см. [[CSE/de_dust2]]
│   └── de_dust2_generated.wad           # встроенные текстуры исходного BSP; не собирается автоматически
├── yapb/
│   └── conf/maps/                  # → runtime/cstrike/addons/yapb/conf/maps/
│       └── <map>.cfg               # per-map YaPB config, default yb_difficulty 0
├── server/                          # серверная CSE-логика случайной ротации
│   ├── CMakeLists.txt               # сборка x86 DLL-прокси
│   └── mapcycle_proxy.cpp           # обёртка YaPB + pfnChangeLevel hook
└── rich_presence/                  # Steam Rich Presence helper (см. [[rich_presence]])
    ├── src/main.cpp                # cse_steamrp.exe — LoadLibrary steam_api.dll + SetRichPresence
    ├── CMakeLists.txt              # сборка x86 (MSVC)
    ├── steam_appid.txt             # AppID 10 (CS 1.6)
    └── README.md                   # детали сборки/запуска/ограничений
```

При добавлении нового домена (например, кастомных карт, конфигов, скриптов) —
создать подпапку здесь и зарегистрировать её в install-скрипте.

Для зацикленных звуков `ambient_generic` WAV-файл должен содержать RIFF `cue`
chunk с точкой цикла; без него движок может удалить звук, если игрок был вне
радиуса слышимости в момент загрузки карты.

## Развёртывание в runtime/

Копирование `src/cse/` → `runtime/` выполняется идемпотентными install-скриптами
из `tools/`:

| Скрипт | Что копирует |
|--------|--------------|
| `tools/install_3rdpartymaps.ps1` | `src/3rdpartymaps/**` → `runtime/cstrike/**`, сохраняя структуру стороннего набора и перезаписывая одноимённые файлы |
| `tools/build_cse_maps.ps1` | `src/cse/maps/build-list.txt` → временный `build/cse-maps/` через `hlcsg → hlbsp → hlvis → hlrad`; J.A.C.K./ZHLT задаётся параметром или `CSE_MAP_TOOLCHAIN_ROOT` |
| `tools/install_cse_maps.ps1` | завершённые BSP → `runtime/cstrike/maps/`; snapshots `.ent` проверяются на сохранение base entities, лимиты и resources, затем `.ent/.res` копируются в runtime |
| `tools/install_cse_assets.ps1` | `src/cse/cstrike/**` → `runtime/cstrike/**`, с перезаписью одноимённых базовых файлов |
| `tools/generate_map_catalog.ps1` | шаблон каталога + `src/3rdpartymaps/maps/*.bsp` → `runtime/cstrike/scripts/CseMapCatalog.json` |
| `tools/install_localization.ps1` | `src/cse/localization/**` → `runtime/<gamedir>/...` |
| `tools/install_gameinfo.ps1` | `src/cse/<gamedir>/gameinfo.txt` → `runtime/<gamedir>/gameinfo.txt` |
| `tools/install_server_config.ps1` | серверные `server.cfg`, `cse_map_change.cfg` и исходный `mapcycle.txt` → `runtime/cstrike/` |
| `tools/install_hud_layout.ps1` | `src/cse/cstrike/scripts/HudLayout.txt` → `runtime/cstrike/scripts/HudLayout.txt` |
| `tools/install_progression.ps1` | `src/cse/cstrike/scripts/CseProgression.txt` → `runtime/cstrike/scripts/CseProgression.txt` |
| `tools/validate_cosmetics.py` | проверяет единый каталог `CseCosmetics.txt`, ID и 63 варианта |
| `tools/install_cosmetics.ps1` | `src/cse/cstrike/scripts/CseCosmetics.txt` → `runtime/cstrike/scripts/CseCosmetics.txt` |
| `tools/generate_cosmetics.py` | декомпилирует stock-модели, применяет палитру/detail mesh и собирает 208 моделей |
| `tools/install_cosmetic_models.ps1` | запускает генератор полного каталога через `mdldec` и внешний `studiomdl` |
| `tools/install_bot_avatars.ps1` | генерирует список из PNG/TGA в `src/cse/cstrike/gfx/cse/avatars/`, затем копирует картинки и `CseBotAvatars.txt` в `runtime/` |
| `tools/install_skins.ps1` | читает `CseSkinRecipes.txt`, запускает `tools/mdl_recolor.py` и создаёт производные `.mdl` в `runtime/cstrike/models/cse/` |
| `tools/install_yapb_map_configs.ps1` | loose `runtime/cstrike/maps/*.bsp` и карты из `.pk3`/`.zip` → создаёт отсутствующие `src/cse/yapb/conf/maps/*.cfg` и копирует их в `runtime/cstrike/addons/yapb/conf/maps/` |
| `tools/install_richpresence.ps1` | `src/cse/rich_presence/steam_appid.txt` + собранный `cse_steamrp.exe` → `runtime/` |
| `build-cse.cmd` | собирает `src/cse/server/`, компилирует/устанавливает карты CSE и разворачивает `cse_mapcycle.dll` рядом с `runtime/cstrike/dlls/yapb.dll` |

При запуске `server.cmd` скрипт `tools/prepare_server_maps.ps1` выбирает стартовую карту и записывает
стабильный пул в runtime `mapcycle.txt` и `cse_map_pool.txt`. Затем `cse_mapcycle.dll` загружается
как прокси перед YaPB и перехватывает `pfnChangeLevel`: `/skip` и завершение матча выбирают новую
валидную карту случайно, без повторов до исчерпания пула. `tr_*` и `cse_test_actions` — не часть
боевого пула.

Скрипты принимают `-DryRun` для предварительного просмотра и `-Root` для
переопределения корня репозитория. Если J.A.C.K./ZHLT отсутствует, map build
выводит красное предупреждение и пропускает карты; ошибка запущенного компилятора
останавливает pipeline без установки частичного BSP. Сгенерированные модели и
BSP не отслеживаются git: это производные файлы в `runtime/`.

`cse_lobby` добавлена в `CseMapCatalog.json`, но намеренно не добавлена в
`src/cse/cstrike/mapcycle.txt`. Запуск для ручной проверки: `server.cmd cse_lobby -nobots`. В v1 dressing ограничен `cs_backalley` и `de_torn`; разрешены только
`ambient_generic`, `infodecal`, `env_rain`/`env_snow`, `env_fog`, `env_sprite`,
`env_glow` и несолидный `cycler_wreckage` с лимитами 24/8/4/12/1/1.

## История

- Создан при инициализации русской локализации: переведены GameUI движка,
  Half-Life строки, CS 1.6 (оружие/режимы/scoreboard), mainui, токены Steam RP.
- Добавлен домен `rich_presence/` — внешний C++ wrapper `cse_steamrp.exe`,
  выставляющий Steam Rich Presence через динамическую загрузку `steam_api.dll`
  (без правки субмодуля движка и без proprietary headers).
- Упрощение главного меню (см. [[CSE/menu]]) — исключение из правила: C++ внутри
  mainui_cpp нельзя вынести в `src/cse/`, поэтому правка живёт в форке
  `Liis17/mainui_cpp` (ветка `cs16-client`), как и правки самого клиента.
- Добавлен домен `cstrike/gfx/cse/avatars/` — картинки, которые сервер случайно раздаёт
  ботам через userinfo-ключ `cse_av` (см. [[Client/HUD-TeamBar]]). Первый случай, когда
  собственный код проекта попал в форк движка, а не клиента.
- Добавлен `cstrike/gameinfo.txt` с `render_picbutton_text 1` — форсирует текстовый
  рендер кнопок главного меню (вместо BMP-атласа `btns_main.bmp` из `extras.pk3`),
  без чего локализация кнопок не работает (см. [[CSE/menu]]).
- Добавлен source-only исходник `maps/de_dust2.map`, полученный из
  `runtime/cstrike/maps/de_dust2.bsp` через Half-Life Unified SDK Map Decompiler;
  рядом сохранён WAD со встроенными текстурами (подробности: [[CSE/de_dust2]]).
