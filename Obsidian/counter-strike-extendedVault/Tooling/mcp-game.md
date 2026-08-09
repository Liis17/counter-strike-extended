# mcp-game

Parent: [[Tools]] · [[Index]]

## Назначение
Локальный MCP-сервер для opencode, автоматизирующий dev-цикл: сборку движка и клиента, развёртывание в `runtime/`,
запуск/остановку игры и чтение логов. Один процесс на TypeScript с набором tools, общается по stdio.

Регистрация: `opencode.json` → `mcp.game`. Запуск: `npm start --prefix tools/mcp-game` (tsx исполняет TypeScript напрямую,
без отдельного build-шага). Зависимости: `@modelcontextprotocol/sdk` 1.x, `zod`, `tsx`, `typescript`.

## Структура
- `tools/mcp-game/package.json` — deps, `start` и `typecheck` scripts
- `tools/mcp-game/tsconfig.json` — TS-конфиг для редактора/typecheck (noEmit, исполняет tsx)
- `tools/mcp-game/src/lib.ts` — хелперы: резолв `PROJECT_ROOT`, `run()` (spawn с перехватом stdout/stderr),
  `wafInvocation`, `listXashProcesses`, `killPid`, `copyTree`, `tailFile`, `textResult`/`truncate`
- `tools/mcp-game/src/index.ts` — точка входа: `McpServer` + регистрация 8 tools + `StdioServerTransport`

## Tools
| Tool | Что делает |
|------|-----------|
| `build_engine` | `waf build` (+`clean`/`rebuild`) в `src/xash3d-fwgs`, затем `waf install --destdir=build/engine`. **Configure не запускает** — ручной one-time шаг с `--sdl2`. |
| `build_client` | `cmake --build build --config <cfg>` + `cmake --install build --prefix=build/cs16-client`. Пресет по умолчанию `win32-release-x86`; configure пропускается при наличии `build/CMakeCache.txt`. |
| `deploy_runtime` | Копирование `build/engine/*` → `runtime/`, `build/cs16-client/cstrike/*` → `runtime/cstrike/`. Параметры: `target` (engine/client/all), `include_pdb`, `dry_run`. Фильтрует `*.lib` всегда, `*.pdb` по флагу. |
| `run_game` | Запускает `runtime/xash3d.exe` (detached, non-blocking), возвращает pid. Параметры: `game`, `map`, `windowed`, `width/height`, `dev`, `extra_args`, `log_file`. |
| `stop_game` | `taskkill /F /PID <pid>` или все экземпляры `xash3d.exe`, если pid не задан. |
| `game_status` | Список pid всех `xash3d.exe` + tracked-from-this-session. |
| `tail_log` | Хвост `runtime/engine.log` (или иного файла в `runtime/`) прямо в чат. |
| `project_paths` | Диагностика: все пути, которые сервер резолвит из корня репозитория. |

## Ключевые методы/функции
| Метод | Назначение |
|-------|-----------|
| `findProjectRoot()` (lib.ts) | Поднимается вверх от `__dirname`, пока не найдёт `.git` + `AGENTS.md` — резолвит `PROJECT_ROOT` независимо от cwd запускающего |
| `run(cmd, args, opts)` (lib.ts) | `child_process.spawn` с перехватом stdout/stderr (ВАЖНО для stdio-протокола MCP), опциональным `onLine`-колбэком и таймаутом |
| `wafInvocation(args, cwd)` (lib.ts) | На Windows → `cmd /c waf.bat ...` (bat-ник сам находит Python в registry), на *nix → `./waf` |
| `copyTree(src, dst, filter)` (lib.ts) | Рекурсивное копирование с фильтром (для `deploy_runtime`) |

## Layout путей
```
PROJECT_ROOT/
├─ src/xash3d-fwgs/      ENGINE_SRC   — waf здесь
├─ src/cs16-client/      CLIENT_SRC   — cmake здесь
├─ build/engine/         ENGINE_INSTALL — waf install --destdir
├─ build/cs16-client/    CLIENT_INSTALL — cmake install --prefix
│   └─ cstrike/{cl_dlls,dlls,extras.pk3}
└─ runtime/              RUNTIME_DIR — финальная папка запуска xash3d.exe
    └─ cstrike/, valve/
```

## Зависимости
- Использует: [[Engine/xash3d-fwgs]] (build_engine, deploy engine), [[Client/cs16-client]] (build_client, deploy client)
- Требует в окружении: `cmake`, `python` (через registry/py launcher — находит `waf.bat`),
  MSVC для пресетов `win32-*-x86`. Для пресетов нужен `Ninja`; без него первый configure делать вручную:
  `cd src/cs16-client && cmake -A Win32 -S . -B build` (далее `build_client` переиспользует кэш).

## Предостережения
- Сервер перехватывает stdout всех дочерних процессов — иначе нарушил бы JSON-RPC поверх stdio.
  Диагностика пишется в stderr (`process.stderr.write`). Для inspect лога используй `tail_log`.
- `run_game` не отслеживает завершение процесса (detached + `unref`); PID только для `stop_game`.
  При рестарте MCP-сервера tracked-pid теряются, но `stop_game` без pid всё равно найдёт все `xash3d.exe` через `tasklist`.
