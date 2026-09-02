# server.cmd — Dedicated Server Launcher

Parent: [[Index]] · Domain: [[Tooling/Tools]]

## Назначение
Запускает выделенный сервер Counter-Strike на движке Xash3D FWGS с ботами YaPB.
Корневой `server.cmd` репозитория, рабочий каталог — `runtime/`.

```
server.cmd [map]   (без аргумента стартовая карта выбирается случайно)
```

Параметры сервера/ботов редактируются в шапке скрипта (`SERVER_*`, `BOT_*`). Перед запуском
`server.cmd` устанавливает `src/cse/cstrike/server.cfg` и исходный `mapcycle.txt`, затем
`tools/prepare_server_maps.ps1` выбирает стартовую карту и создаёт runtime-пул. Явный
`server.cmd de_dust2` меняет только стартовую карту; переходы после неё выбираются прокси случайно.

`server.cfg` задаёт `mp_winlimit 6`, `mp_windifference 1`, `mp_maxrounds 0` и `mp_timelimit 0`: карта завершается после
шести побед одной команды. ReGameDLL выбирает следующий элемент своего последовательного `mapcycle`,
но `cse_mapcycle.dll` заменяет этот destination на случайную валидную карту из `cse_map_pool.txt`.
Прокси исключает текущую карту и не повторяет уже выбранные карты, пока пул не исчерпан.
Пул хранится в `src/cse/cstrike/mapcycle.txt` и основан на текущем dedicated mapcycle; тренировочные
`tr_*` и `cse_test_actions` туда не входят.

Текущую карту можно пропустить из консоли dedicated-сервера командой `/skip`. Она временно включает короткий
лимит времени, поэтому переход выполняется тем же `ChangeLevel` ReGameDLL и попадает в прокси с выбором
новой случайной карты. При загрузке следующей карты `cse_map_change.cfg` восстанавливает матч до шести побед.

`cse_mapcycle.dll` — собственная DLL-прокси из `src/cse/server/`: она форвардит entry points в соседний
`yapb.dll` и подменяет только `pfnChangeLevel`. Сборка и копирование выполняются шагом `build-cse.cmd`.

## Важный нюанс: путь к серверной DLL

`-dll` принимает путь **относительно gamedir** (`cstrike/`), а не bare-имя файла.

```cmd
rem ПРАВИЛЬНО — прокси ищется как cstrike/dlls/cse_mapcycle.dll
set "SERVER_DLL=dlls\cse_mapcycle.dll"

rem НЕПРАВИЛЬНО — движок ищет cstrike/cse_mapcycle.dll, не находит,
rem               сервер поднимается без игровой логики (боты/клиенты не работают)
set "SERVER_DLL=cse_mapcycle.dll"
```

Причина — в `COM_GetCommonLibraryPath()` (`engine/common/lib_common.c`): bare значение из
`-dll` копируется как есть и скармливается `FS_FindLibrary()`, которая ищет его в корнях
searchpath, а не в `dlls/`. Префикс `@` на сборке `XASH_X86 && XASH_WIN32` бесполезен для
подмены серверной DLL — `COM_GenerateServerLibraryPath()` на этой платформе игнорирует
`alt_dllname` и всегда возвращает `GI->game_dll` (из `liblist.gam`).

## Симптомы незагрузившейся серверной DLL
- `Error: can't initialize yapb.dll: Failed to find library yapb.dll` в `runtime/engine.log`
- `Warning: Unknown command "yb_*"` — cvar'ы ботов не зарегистрированы
- Сервер не появляется в поиске LAN
- Клиент зависает на экране загрузки → таймаут → возврат в меню
  (без server DLL движок не может обработать подключение)

## Зависимости
- [[Engine/xash3d-fwgs]] — `runtime/xash3d.exe`
- `runtime/cstrike/dlls/cse_mapcycle.dll` — серверная CSE-прокси (из `src/cse/server`)
- `runtime/cstrike/dlls/yapb.dll` — YaPB, который прокси загружает как внутреннюю DLL
- `runtime/cstrike/liblist.gam` — `gamedll "dlls\mp.dll"` (fallback, когда `-dll` не указан)
