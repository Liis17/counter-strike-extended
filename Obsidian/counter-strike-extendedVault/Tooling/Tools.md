# Tools

Parent: [[Index]]

## Назначение
Вспомогательные скрипты для разработки/отладки, не часть движка или клиента.

## Файлы
- `tools/install_3rdpartymaps.ps1` — копирует содержимое `src/3rdpartymaps/` в `runtime/cstrike/` с сохранением вложенных путей (идемпотентно, есть `-DryRun`)
- `tools/generate_map_catalog.ps1` — строит `runtime/cstrike/scripts/CseMapCatalog.json` из versioned-шаблона и BSP сторонних карт (есть `-DryRun` и `-Root`)
- `tools/screenshot_window.ps1` — делает скриншот окна процесса по имени (по умолчанию `xash3d`), сохраняет в `runtime/window_capture.png`
- `tools/install_cse_assets.ps1` — перед копированием находит в BSP зацикленные `ambient_generic`, добавляет отсутствующий RIFF `cue` в проектные WAV и накладывает `src/cse/cstrike/` на `runtime/cstrike/` с перезаписью одноимённых оригиналов (идемпотентно, есть `-DryRun`)
- `tools/install_localization.ps1` — копирует файлы локализации из `src/cse/localization/` в `runtime/` (идемпотентно, есть `-DryRun`). См. [[Localization/Локализация]]
- `tools/install_hud_layout.ps1` — копирует `src/cse/cstrike/scripts/HudLayout.txt` в `runtime/cstrike/scripts/` (идемпотентно, есть `-DryRun`)
- `tools/install_progression.ps1` — копирует `src/cse/cstrike/scripts/CseProgression.txt` в `runtime/cstrike/scripts/` (идемпотентно, есть `-DryRun`)
- `tools/install_server_config.ps1` — копирует серверные `server.cfg`, `cse_map_change.cfg` и исходный `mapcycle.txt` в `runtime/cstrike/` (идемпотентно, есть `-DryRun`)
- `tools/prepare_server_maps.ps1` — выбирает стартовую карту и записывает стабильный пул в runtime `mapcycle.txt` и `cse_map_pool.txt`
- `tools/mdl_recolor.py` — меняет только RGB-палитры GoldSrc `.mdl`, не затрагивая геометрию и анимации; поддерживает внешний `<name>T.mdl`
- `tools/install_skins.ps1` — читает `src/cse/cstrike/scripts/CseSkinRecipes.txt`, запускает генератор и пишет производные модели в `runtime/cstrike/models/cse/` (есть `-DryRun`)
- `tools/install_yapb_map_configs.ps1` — по loose `.bsp` и картам из `.pk3`/`.zip` создаёт отсутствующие per-map конфиги YaPB в `src/cse/` и копирует их в runtime
- `tools/mcp-game/` — MCP-сервер `game` для opencode (build/deploy/run игры без ручных shell-команд). Подробнее: [[Tooling/mcp-game]]
- `server.cmd` — запуск dedicated-сервера CS с ботами YaPB, случайной ротацией карт и матчем до 6 побед. Важный нюанс: `-dll` требует путь относительно gamedir (`dlls\cse_mapcycle.dll`, не bare-имя). Подробнее: [[Tooling/server-cmd]]
- `tools/hud-editor/` — визуальный веб-конструктор `HudLayout.txt` (`index.html` + `editor.css` + `editor.js`), без сборки/npm. Запуск — `start-hud-editor.cmd`. Подробнее: [[Tooling/hud-editor]], формат: [[Client/HUD-layout]]

## Ключевые методы/функции
| Метод | Описание |
|-------|----------|
| `screenshot_window.ps1 -ProcessName <name> -OutFile <path>` | Находит окно процесса, выводит на передний план, снимает скриншот через `GetWindowRect`/`CopyFromScreen`, сохраняет PNG |
| `install_3rdpartymaps.ps1 [-DryRun] [-Root <path>]` | Копирует все файлы из `src/3rdpartymaps/**` в `runtime/cstrike/**`, сохраняя относительные пути и перезаписывая одноимённые файлы |
| `generate_map_catalog.ps1 [-DryRun] [-Root <path>]` | Читает `src/cse/cstrike/scripts/CseMapCatalog.json`, добавляет отсортированные `src/3rdpartymaps/maps/*.bsp` в `third_party` и пишет каталог в runtime; список скачанных карт вычисляет UI |
| `install_cse_assets.ps1 [-DryRun] [-Root <path>]` | Проверяет looped `ambient_generic` в BSP, добавляет cue-маркер проектным WAV без него и копирует `src/cse/cstrike/**` в `runtime/cstrike/**`, перезаписывая одноимённые базовые ассеты и не удаляя остальные |
| `install_localization.ps1 [-DryRun] [-Root <path>]` | Копирует `src/cse/localization/**` в `runtime/`, создавая нужные поддиректории |
| `install_hud_layout.ps1 [-DryRun] [-Root <path>]` | Копирует проектный HUD-layout в `runtime/cstrike/scripts/HudLayout.txt` |
| `install_progression.ps1 [-DryRun] [-Root <path>]` | Копирует конфиг XP/уровней в `runtime/cstrike/scripts/CseProgression.txt` |
| `install_server_config.ps1 [-DryRun] [-Root <path>]` | Копирует серверные правила, map-change hook и исходный пул карт в `runtime/cstrike/` |
| `prepare_server_maps.ps1 [-Root <path>] [-StartMap <map>]` | Выбирает стартовую карту, валидирует её в пуле и записывает runtime-пул |
| `mdl_recolor.py <source> <output> [--hue-shift <degrees>] [--tint R G B]` | Копирует `.mdl`, преобразуя только его 256-цветные палитры |
| `install_skins.ps1 [-DryRun] [-Root <path>]` | Генерирует модели по `CseSkinRecipes.txt`; требует локальные исходные `.mdl` в `runtime/cstrike/models/` |
| `install_yapb_map_configs.ps1 [-DryRun] [-Root <path>]` | Находит loose `.bsp` и карты в `.pk3`/`.zip`, создаёт отсутствующие `yb_difficulty 0` в `src/cse/yapb/conf/maps/` и копирует все `.cfg` в YaPB runtime |
| `hud-editor` — «Открыть.../Сохранить» | Читает/пишет `HudLayout.txt` напрямую через File System Access API; парсер/сериализатор — зеркало `CHud::LoadLayout()`/формата из `hud_layout.cpp`. Функции редактора описаны в [[Tooling/hud-editor]] |

## Зависимости
- Использует: [[Engine/xash3d-fwgs]] (снимает окно запущенного `xash3d.exe`)
- Для случайной серверной ротации `build-cse.cmd` собирает `src/cse/server/mapcycle_proxy.cpp` в x86 `cse_mapcycle.dll`; прокси загружает соседний `yapb.dll`
- Для генератора моделей нужен Python 3; исходные модели берутся из лицензированного `runtime/` и не попадают в git
