# server.cmd — Dedicated Server Launcher

Parent: [[Index]] · Domain: [[Tooling/Tools]]

## Назначение
Запускает выделенный сервер Counter-Strike на движке Xash3D FWGS с ботами YaPB.
Корневой `server.cmd` репозитория, рабочий каталог — `runtime/`.

```
server.cmd [map]   (по умолчанию de_dust2)
```

Параметры сервера/ботов редактируются в шапке скрипта (`SERVER_*`, `BOT_*`).

## Важный нюанс: путь к серверной DLL

`-dll` принимает путь **относительно gamedir** (`cstrike/`), а не bare-имя файла.

```cmd
rem ПРАВИЛЬНО — файл ищется как cstrike/dlls/yapb.dll
set "SERVER_DLL=dlls\yapb.dll"

rem НЕПРАВИЛЬНО — движок ищет cstrike/yapb.dll, не находит,
rem               сервер поднимается без игровой логики (боты/клиенты не работают)
set "SERVER_DLL=yapb.dll"
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
- `runtime/cstrike/dlls/yapb.dll` — серверная DLL с ботами (из `src/cs16-client/3rdparty/yapb`)
- `runtime/cstrike/liblist.gam` — `gamedll "dlls\mp.dll"` (fallback, когда `-dll` не указан)
