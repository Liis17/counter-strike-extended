# Tools

Parent: [[Index]]

## Назначение
Вспомогательные скрипты для разработки/отладки, не часть движка или клиента.

## Файлы
- `tools/screenshot_window.ps1` — делает скриншот окна процесса по имени (по умолчанию `xash3d`), сохраняет в `runtime/window_capture.png`
- `tools/install_localization.ps1` — копирует файлы локализации из `src/cse/localization/` в `runtime/` (идемпотентно, есть `-DryRun`). См. [[Localization/Локализация]]
- `tools/apply_menu_patch.ps1` — накладывает патчи из `src/cse/menu/` на submodule `src/cs16-client/3rdparty/mainui_cpp` (идемпотентно, есть `-DryRun`). См. [[CSE/menu]]
- `tools/mcp-game/` — MCP-сервер `game` для opencode (build/deploy/run игры без ручных shell-команд). Подробнее: [[Tooling/mcp-game]]

## Ключевые методы/функции
| Метод | Описание |
|-------|----------|
| `screenshot_window.ps1 -ProcessName <name> -OutFile <path>` | Находит окно процесса, выводит на передний план, снимает скриншот через `GetWindowRect`/`CopyFromScreen`, сохраняет PNG |
| `install_localization.ps1 [-DryRun] [-Root <path>]` | Копирует `src/cse/localization/**` в `runtime/`, создавая нужные поддиректории |
| `apply_menu_patch.ps1 [-DryRun] [-Root <path>]` | `git apply` каждого `src/cse/menu/*.patch` к mainui_cpp; уже применённые пропускает через `git apply --reverse --check` |

## Зависимости
- Использует: [[Engine/xash3d-fwgs]] (снимает окно запущенного `xash3d.exe`)
