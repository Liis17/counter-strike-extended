# Tools

Parent: [[Index]]

## Назначение
Вспомогательные скрипты для разработки/отладки, не часть движка или клиента.

## Файлы
- `tools/screenshot_window.ps1` — делает скриншот окна процесса по имени (по умолчанию `xash3d`), сохраняет в `runtime/window_capture.png`
- `tools/install_localization.ps1` — копирует файлы локализации из `src/cse/localization/` в `runtime/` (идемпотентно, есть `-DryRun`). См. [[Localization/Локализация]]
- `tools/mcp-game/` — MCP-сервер `game` для opencode (build/deploy/run игры без ручных shell-команд). Подробнее: [[Tooling/mcp-game]]
- `tools/hud-editor/index.html` — визуальный веб-конструктор `HudLayout.txt` (см. [[Client/HUD-layout]]). Один самодостаточный HTML-файл, без сборки/npm. Открывать через `http://` (не `file://` — браузеры блокируют File System Access API на этой схеме), например `npx http-server tools/hud-editor` или любой статический сервер. Работает только в Chrome/Edge (нужен `window.showOpenFilePicker`/`showSaveFilePicker`). Холст нужно выставлять в фактическое разрешение игры; для текущего runtime есть пресет `2560×1440`.

## Ключевые методы/функции
| Метод | Описание |
|-------|----------|
| `screenshot_window.ps1 -ProcessName <name> -OutFile <path>` | Находит окно процесса, выводит на передний план, снимает скриншот через `GetWindowRect`/`CopyFromScreen`, сохраняет PNG |
| `install_localization.ps1 [-DryRun] [-Root <path>]` | Копирует `src/cse/localization/**` в `runtime/`, создавая нужные поддиректории |
| `hud-editor/index.html` — «Открыть.../Сохранить» | Читает/пишет `HudLayout.txt` напрямую через File System Access API. Холст с выбором фактического разрешения экрана, ориентировочными габаритами 9 HUD-элементов (включая right-aligned origin и поддерживаемый scale) и декорациями `Line`/`Shade`/`Panel` (drag + resize + цвет + alpha + radius). Выбранное разрешение сохраняется в комментарии, парсер/сериализатор — зеркало `CHud::LoadLayout()`/формата из `hud_layout.cpp` |
| `getElementPreview(id, element)` | Вычисляет footprint HUD-блока и его runtime-origin для предпросмотра |
| `beginElementDrag(node, element)` | Перемещает HUD-блок через тот же anchor/inverse-anchor контракт, что и игра |

## Зависимости
- Использует: [[Engine/xash3d-fwgs]] (снимает окно запущенного `xash3d.exe`)
