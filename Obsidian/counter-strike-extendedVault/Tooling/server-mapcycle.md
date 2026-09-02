# server-mapcycle — случайная серверная ротация карт

Parent: [[Index]] · [[Tooling/server-cmd]] · [[Tooling/Tools]]

## Назначение

`src/cse/server/mapcycle_proxy.cpp` — собственная Windows x86 DLL-прокси для dedicated-сервера.
Она оставляет YaPB и ReGameDLL сторонними submodule-компонентами, но меняет destination карты
перед самым вызовом движка `pfnChangeLevel`.

## Поток запуска

1. `server.cmd` устанавливает конфиги и вызывает `tools/prepare_server_maps.ps1`.
2. Скрипт выбирает стартовую карту (если она не передана явно) и пишет пул в
   `runtime/cstrike/mapcycle.txt` и `runtime/cstrike/cse_map_pool.txt`.
3. Xash3D загружает `dlls/cse_mapcycle.dll`; прокси загружает рядом `yapb.dll` и форвардит его
   GoldSrc entry points.
4. ReGameDLL по `mp_winlimit` или `/skip` вызывает обычный `ChangeLevel`; прокси выбирает новую
   валидную карту из пула, исключая текущую и уже выбранные в текущем запуске.
5. После исчерпания пула мешок заполняется заново, поэтому следующий переход снова случайный.

## Инварианты

- `src/cs16-client/` не изменяется для этой функции.
- Прямой запуск с `-dll dlls/yapb.dll` сохраняет старое последовательное поведение и не включает
  случайную ротацию; для неё нужен `cse_mapcycle.dll` или `server.cmd`.
- При отсутствии или неполноте `cse_map_pool.txt` прокси использует `mapcycle.txt` как запасной
  случайный пул; только если оба файла не дают минимум две карты, сохраняется исходное назначение ReGameDLL.
- Прокси читает только сгенерированный `runtime/cstrike/cse_map_pool.txt`; source of truth —
  `src/cse/cstrike/mapcycle.txt`.

## Сборка

`build-cse.cmd` отдельным CMake-проектом собирает `src/cse/server/` и копирует
`cse_mapcycle.dll` в `runtime/cstrike/dlls/` рядом с `yapb.dll`.

## Основные функции

| Функция | Роль |
|---------|------|
| `GiveFnptrsToDll` | Сохраняет таблицу функций движка, подменяет `pfnChangeLevel` и передаёт таблицу YaPB |
| `CSE_ChangeLevel` | Выбирает destination карты и вызывает исходный callback движка |
| `LoadMapPool` | Читает сгенерированный `cse_map_pool.txt` и нормализует имена карт |
| `NextRandomMap` | Выдаёт валидную карту без повторов до исчерпания текущего мешка |
