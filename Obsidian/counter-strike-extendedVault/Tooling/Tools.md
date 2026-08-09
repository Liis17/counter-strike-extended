# Tools

Parent: [[Index]]

## Назначение
Вспомогательные скрипты для разработки/отладки, не часть движка или клиента.

## Файлы
- `tools/screenshot_window.ps1` — делает скриншот окна процесса по имени (по умолчанию `xash3d`), сохраняет в `runtime/window_capture.png`
- `tools/install_localization.ps1` — копирует файлы локализации из `src/cse/localization/` в `runtime/` (идемпотентно, есть `-DryRun`). См. [[Localization/Локализация]]
- `tools/mcp-game/` — MCP-сервер `game` для opencode (build/deploy/run игры без ручных shell-команд). Подробнее: [[Tooling/mcp-game]]
- `tools/hud-editor/index.html` — визуальный веб-конструктор `HudLayout.txt` (см. [[Client/HUD-layout]]). Один самодостаточный HTML-файл, без сборки/npm. Открывать через `http://` (не `file://` — браузеры блокируют File System Access API на этой схеме), например `npx http-server tools/hud-editor` или любой статический сервер. Работает только в Chrome/Edge (нужен `window.showOpenFilePicker`/`showSaveFilePicker`).

## Ключевые методы/функции
| Метод | Описание |
|-------|----------|
| `screenshot_window.ps1 -ProcessName <name> -OutFile <path>` | Находит окно процесса, выводит на передний план, снимает скриншот через `GetWindowRect`/`CopyFromScreen`, сохраняет PNG |
| `install_localization.ps1 [-DryRun] [-Root <path>]` | Копирует `src/cse/localization/**` в `runtime/`, создавая нужные поддиректории |
| `hud-editor/index.html` — «Открыть.../Сохранить» | Читает/пишет `HudLayout.txt` напрямую через File System Access API. Холст с выбором разрешения экрана, 9 обязательных HUD-элементов (drag + anchor + scale) и добавляемые декорации `Line`/`Shade`/`Panel` (drag + resize + цвет + alpha + radius). Парсер/сериализатор в JS — зеркало `CHud::LoadLayout()`/формата из `hud_layout.cpp` |

## Зависимости
- Использует: [[Engine/xash3d-fwgs]] (снимает окно запущенного `xash3d.exe`)
