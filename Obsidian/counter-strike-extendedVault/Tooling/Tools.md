# Tools

Parent: [[Index]]

## Назначение
Вспомогательные скрипты для разработки/отладки, не часть движка или клиента.

## Файлы
- `tools/screenshot_window.ps1` — делает скриншот окна процесса по имени (по умолчанию `xash3d`), сохраняет в `runtime/window_capture.png`
- `tools/install_localization.ps1` — копирует файлы локализации из `src/cse/localization/` в `runtime/` (идемпотентно, есть `-DryRun`). См. [[Localization/Локализация]]
- `tools/install_hud_layout.ps1` — копирует `src/cse/cstrike/scripts/HudLayout.txt` в `runtime/cstrike/scripts/` (идемпотентно, есть `-DryRun`)
- `tools/install_yapb_map_configs.ps1` — по loose `.bsp` и картам из `.pk3`/`.zip` создаёт отсутствующие per-map конфиги YaPB в `src/cse/` и копирует их в runtime
- `tools/mcp-game/` — MCP-сервер `game` для opencode (build/deploy/run игры без ручных shell-команд). Подробнее: [[Tooling/mcp-game]]
- `server.cmd` — запуск dedicated-сервера CS с ботами YaPB. Важный нюанс: `-dll` требует путь относительно gamedir (`dlls\yapb.dll`, не bare-имя). Подробнее: [[Tooling/server-cmd]]
- `tools/hud-editor/` — визуальный веб-конструктор `HudLayout.txt` (`index.html` + `editor.css` + `editor.js`), без сборки/npm. Запуск — `start-hud-editor.cmd`. Подробнее: [[Tooling/hud-editor]], формат: [[Client/HUD-layout]]

## Ключевые методы/функции
| Метод | Описание |
|-------|----------|
| `screenshot_window.ps1 -ProcessName <name> -OutFile <path>` | Находит окно процесса, выводит на передний план, снимает скриншот через `GetWindowRect`/`CopyFromScreen`, сохраняет PNG |
| `install_localization.ps1 [-DryRun] [-Root <path>]` | Копирует `src/cse/localization/**` в `runtime/`, создавая нужные поддиректории |
| `install_hud_layout.ps1 [-DryRun] [-Root <path>]` | Копирует проектный HUD-layout в `runtime/cstrike/scripts/HudLayout.txt` |
| `install_yapb_map_configs.ps1 [-DryRun] [-Root <path>]` | Находит loose `.bsp` и карты в `.pk3`/`.zip`, создаёт отсутствующие `yb_difficulty 0` в `src/cse/yapb/conf/maps/` и копирует все `.cfg` в YaPB runtime |
| `hud-editor` — «Открыть.../Сохранить» | Читает/пишет `HudLayout.txt` напрямую через File System Access API; парсер/сериализатор — зеркало `CHud::LoadLayout()`/формата из `hud_layout.cpp`. Функции редактора описаны в [[Tooling/hud-editor]] |

## Зависимости
- Использует: [[Engine/xash3d-fwgs]] (снимает окно запущенного `xash3d.exe`)
