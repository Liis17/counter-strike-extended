# rich_presence — Steam-хелпер для xash3d (Rich Presence + аватары)

Внешний C++-helper `cse_steamrp.exe`, который оборачивает `xash3d.exe`: при
запуске игры инициализирует Steam API и выставляет Steam Rich Presence
(статус «в игре» в профиле Steam у друзей). Запускается **вместо**
`xash3d.exe`, сам поднимает дочерний процесс движка и форвардит ему все
аргументы.

## Зачем отдельный helper

Движок `xash3d-fwgs` принципиально **не линкует** `steam_api.dll` (GPL-конфликт,
см. `src/xash3d-fwgs/engine/client/cl_steam.c`). Поэтому Rich Presence нельзя
сделать внутри процесса `xash3d.exe` без правки субмодуля движка. Helper —
отдельный процесс, который линкует Steam API динамически и подчиняется правилу
«собственный код только в `src/cse/`».

## Как это работает

1. `LoadLibraryA("steam_api.dll")` — dll **не** в репо (proprietary), берётся из
   установленной Steam HL/CS.
2. `GetProcAddress` достаёт flat-API функции (`SteamAPI_Init`,
   `SteamAPI_ISteamFriends_SetRichPresence` и т.д.). **Headers из Steamworks SDK
   не нужны** — объявлены минимальные `typedef`'ы прямо в `src/main.cpp`.
3. `SteamAPI_Init()` читает `steam_appid.txt` (содержимое: `10` = CS 1.6).
4. `ISteamFriends::SetRichPresence("steam_display", "#HL_RP_MainMenu")`.
5. `CreateProcessA("xash3d.exe", ...)` — дочерний процесс с форвардом argv.
6. Цикл `WaitForSingleObject(child, 200ms)` + `SteamAPI_RunCallbacks()` пока
   движок работает.
7. На выходе дочернего процесса — `ClearRichPresence` + `SteamAPI_Shutdown`.

## Сборка

Нужен CMake + MSVC (Visual Studio 2022 BuildTools или новее). Сборка
**обязательно 32-битная** (x86), чтобы совпасть по разрядности с `steam_api.dll`
из HL/CS и с `xash3d.exe`.

```powershell
cd src\cse\rich_presence
cmake -B build -A Win32
cmake --build build --config Release
```

Артефакт: `build\Release\cse_steamrp.exe` (для VS-генератора) либо
`build\cse_steamrp.exe` (для Ninja).

## Развёртывание в runtime/

```powershell
tools\install_richpresence.ps1
```

Копирует `steam_appid.txt` и собранный `cse_steamrp.exe` в `runtime/`.
Идемпотентен.

## steam_api.dll (один раз, вручную)

`steam_api.dll` — proprietary и **не кладётся в репо**. Скопируйте его из
установленной Steam-игры в `runtime/`:

```powershell
Copy-Item 'C:\Program Files (x86)\Steam\steamapps\common\Half-Life\steam_api.dll' `
          'runtime\steam_api.dll'
```

Достаточно 32-битной версии (HL/CS её и поставляют).

## Запуск

```powershell
cd runtime
.\cse_steamrp.exe -game cstrike
```

Все аргументы после `cse_steamrp.exe` форвардятся в `xash3d.exe` без изменений:
`-window`, `-dev 3`, `+map de_dust2` и т.д.

## Сервис аватаров (для HUD TeamBar)

Клиентская dll не может линковать `steam_api`, поэтому хелпер работает её
Steam-стороной. Обмен — файлами в `runtime/<gamedir>/cache/`:

| Файл | Кто пишет | Что |
|------|-----------|-----|
| `cache/cse_steam_self.txt` | хелпер | SteamID64 локального игрока |
| `cache/avatars/wanted.txt` | клиент | по одному SteamID64 на строку |
| `cache/avatars/<id64>.tga` | хелпер | 32-битный несжатый TGA 64×64 |

Раз в секунду: `RequestUserInformation` → `GetMediumFriendAvatar` →
`GetImageSize`/`GetImageRGBA` → TGA (`attributes = 0x28`, BGRA). Уже скачанные
пропускаются, ещё не готовые повторяются на следующем тике. Отсутствие нужных
экспортов в `steam_api.dll` не фатально — лента остаётся на плейсхолдерах.

## Ограничения

- **Владение игрой.** Чтобы Steam показал статус именно как Counter-Strike
  (appid 10), аккаунт должен владеть CS 1.6. Без этого Steam либо не покажет RP,
  либо покажет generic «Играет в cse_steamrp».
- **Имя карты НЕ отображается для CS.** Valve не сделала RP-токены для CS 1.6
  (appid 10) — у оригинальной CS в Steam тоже видно только «в игре», без карты
  и режима (для сравнения, Half-Life appid 70 токены имеет). Helper всё равно
  вызывает `SetRichPresence` с `map_name`, но Steam игнорирует его для CS.
  Если позже захочется отображать карту — переключить `steam_appid.txt` на `70`
  (HL-токены встроены Valve): тогда будет «Half-Life: <карта>», но имя игры
  сменится на Half-Life.
- **Конфликт с настоящей CS.** Если параллельно запущена Steam-версия CS 1.6,
  два процесса с одним appid могут конфликтовать. Закрывайте одно перед запуском
  другого.

## Состояния presence, которые helper выставляет

(Steam для CS 1.6 покажет только базовый «в игре», но токены всё равно
проставляются — на случай переключения на HL appid 70 или если Valve добавит
поддержку CS-токенов.)

- старт / главное меню: `steam_display = "#CS_RP_MainMenu"` (или `#HL_RP_MainMenu`)
- после загрузки карты (детектится по строке `Spawn Server: <map>` в самом
  свежем `*.log` под `runtime/`): `steam_display = "#CS_RP_PlayingKnown"`,
  `map_name = "<имя карты>"`.
