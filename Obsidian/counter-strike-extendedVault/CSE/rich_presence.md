# rich_presence — Steam-хелпер (Rich Presence + аватары)

Parent: [[Index]]
Связанные: [[CSE/cse-structure]], [[Локализация]], [[Архитектура]], [[Engine/xash3d-fwgs]], [[Client/HUD-TeamBar]]

## Назначение

Внешний C++ wrapper `cse_steamrp.exe`, который запускается **вместо**
`xash3d.exe`: инициализирует Steam API и выставляет Steam Rich Presence
(статус «в игре» в профиле Steam у друзей), затем поднимает `xash3d.exe`
как дочерний процесс и форвардит ему все аргументы.

Вторая роль — **Steam-сторона игрового клиента**: клиентская dll не может
линковать `steam_api`, поэтому хелпер отдаёт ей SteamID64 локального игрока и
выкачивает аватары для [[Client/HUD-TeamBar]] (см. «Сервис аватаров» ниже).

Хранится в `src/cse/rich_presence/` ([[CSE/cse-structure]]).

## Почему вне движка

Движок `xash3d-fwgs` принципиально **не линкует** `steam_api.dll` — GPL-конфликт
(см. `src/xash3d-fwgs/engine/client/cl_steam.c:30-35`,
`Documentation/extensions/steam-broker.md`). Существующая Steam-интеграция в
движке — только auth-tickets через отдельный broker-процесс, и там нет команд
для Rich Presence. Поэтому RP нельзя сделать внутри `xash3d.exe` без правки
субмодуля движка (что запрещено правилом `AGENTS.md`). Внешний helper —
отдельный процесс и подчиняется правилу «собственный код только в `src/cse/`».

## Как работает

1. `LoadLibraryA("steam_api.dll")` — dll **не** в репо (proprietary), берётся из
   установленной Steam HL/CS и кладётся в `runtime/` вручную.
2. `GetProcAddress` достаёт **flat-API** функции (`SteamAPI_Init`,
   `SteamAPI_ISteamFriends_SetRichPresence`, `SteamAPI_SteamFriends_v017` и т.д.).
   **Headers из Steamworks SDK не нужны** — нужные `typedef`'ы объявлены прямо в
   `src/main.cpp`. Это снимает лицензионную проблему (нет proprietary headers).
3. `SteamAPI_Init()` читает `steam_appid.txt` (содержимое: `10` = CS 1.6).
4. `ISteamFriends::SetRichPresence("steam_display", "#HL_RP_MainMenu")` —
   статическое «в главном меню». Токен разрешается Steam-клиентом через
   `<appid>_loc_<lang>.vdf` (см. [[Локализация]]).
5. `CreateProcessA("xash3d.exe", ...)` — дочерний процесс, argv форвардится.
6. Цикл `WaitForSingleObject(child, 200ms)` + `SteamAPI_RunCallbacks()`.
7. На выходе дочернего процесса — `ClearRichPresence` + `SteamAPI_Shutdown`.

Все ошибки инициализации RP **не фатальны**: если `steam_api.dll` нет или Steam
не запущен — helper всё равно запускает игру, пишет диагностику в stderr.

## Сервис аватаров

Клиентская dll не имеет доступа к Steam, поэтому хелпер работает её Steam-стороной.
Обмен — через файлы в `runtime/<gamedir>/cache/` (пути относительно рабочего каталога
`runtime/`, куда переходят все лаунчеры):

| Файл | Кто пишет | Что |
|------|-----------|-----|
| `cache/cse_steam_self.txt` | хелпер | SteamID64 локального игрока; клиент публикует его как userinfo-ключ `cse_sid` |
| `cache/avatars/wanted.txt` | клиент | по одному SteamID64 на строку — кого показывает лента |
| `cache/avatars/<id64>.tga` | хелпер | 32-битный несжатый TGA, `attributes = 0x28` (top-down + альфа) |

Цикл (раз в секунду, внутри того же pump-loop, что и Rich Presence):
`RequestUserInformation(id, false)` → `GetMediumFriendAvatar(id)` (0, пока Steam не
скачал) → `GetImageSize` + `GetImageRGBA` → RGBA конвертируется в BGRA и пишется в TGA.
Уже существующие файлы пропускаются, незавершённые id повторяются на следующем тике.

Формат TGA подобран под загрузчик движка `engine/common/imagelib/img_tga.c`: type 2,
32 bpp, бит 0x20 в attributes → загрузка без переворота строк. **JPG движок не читает**
(поддерживаются tga/png/bmp/dds/ktx2), поэтому прямая закачка с CDN Steam не подходит.

Аксессоры интерфейсов версионированы (`SteamAPI_SteamUtils_v010` и т.п.) и версия плывёт
вместе с SDK, поэтому `resolve_interface()` перебирает суффиксы `_v005`…`_v040` и берёт
первый разрешившийся. Отсутствие любого экспорта не фатально — лента просто остаётся на
плейсхолдерах.

## Экспорты steam_api.dll, которые использует helper

(подтверждены dumpbin'ом для dll из `Half-Life\steam_api.dll`, file version 06.91.21.57)

- `SteamAPI_Init`
- `SteamAPI_Shutdown`
- `SteamAPI_RunCallbacks`
- `SteamAPI_SteamFriends_v017`
- `SteamAPI_ISteamFriends_SetRichPresence(self, key, value)`
- `SteamAPI_ISteamFriends_ClearRichPresence(self)`

Для аватаров (разрешаются перебором версий, см. выше):

- `SteamAPI_SteamUser_v0NN` / `SteamAPI_ISteamUser_GetSteamID(self)`
- `SteamAPI_SteamUtils_v0NN` / `SteamAPI_ISteamUtils_GetImageSize`, `..._GetImageRGBA`
- `SteamAPI_ISteamFriends_RequestUserInformation`, `..._GetMediumFriendAvatar`

## Сборка

```powershell
cd src\cse\rich_presence
cmake -B build -A Win32          # обязательно x86 — dll и xash3d 32-битные
cmake --build build --config Release
```

Артефакт: `build/Release/cse_steamrp.exe` (~26 KB).

## Развёртывание

```powershell
tools\install_richpresence.ps1   # steam_appid.txt + cse_steamrp.exe → runtime/
# один раз:
Copy-Item 'C:\Program Files (x86)\Steam\steamapps\common\Half-Life\steam_api.dll' `
          'runtime\steam_api.dll'
```

`steam_api.dll` — proprietary, в репо не кладётся.

## Запуск

```powershell
cd runtime
.\cse_steamrp.exe -game cstrike
```

Аргументы после `cse_steamrp.exe` форвардятся в `xash3d.exe` без изменений.

## Проверка работы

При запуске helper пишет в stderr:
```
Setting breakpad minidump AppID = 10
SteamInternal_SetMinidumpSteamID:  Caching Steam ID:  7656... [API loaded no]
[steamrp] Rich Presence active (steam_display=#HL_RP_MainMenu).
```
После этого в профиле Steam у друзей отображается статус «в игре» (Counter-Strike,
если аккаунт владеет appid 10).

## Ограничения

- **Владение игрой.** Для отображения именно как Counter-Strike (appid 10)
  аккаунт Steam должен владеть CS 1.6. Без этого — generic статус либо ничего.
- **Имя карты НЕ отображается для CS.** Valve не сделала RP-токены для CS 1.6
  (appid 10) — оригинальная CS в Steam тоже показывает только «в игре», без
  карты/режима (для сравнения, Half-Life appid 70 токены имеет —
  `valve/resource/70_loc_english.vdf`). Helper всё равно вызывает
  `SetRichPresence("map_name", ...)`, но Steam игнорирует его для CS. Если
  хочется видеть карту — переключить `runtime/steam_appid.txt` на `70`: тогда
  токены HL разрешатся и будет «Half-Life: <карта>» (но имя игры сменится).
- **Конфликт с настоящей CS.** Два процесса с одним appid могут конфликтовать —
  закрывать одно перед запуском другого.

## Состояния presence, которые helper выставляет

(Steam для CS 1.6 покажет только базовый «в игре», но токены всё равно
проставляются — на случай переключения на HL appid 70 или если Valve добавит
поддержку CS-токенов.)

- старт / главное меню: `steam_display = "#CS_RP_MainMenu"` (или `#HL_RP_MainMenu`
  если `steam_appid.txt` = 70).
- после загрузки карты (детектится по строке `Spawn Server: <map>` в самом
  свежем `*.log` под `runtime/`): `steam_display = "#CS_RP_PlayingKnown"`,
  `map_name = "<имя карты>"`.

## Файлы

| Файл | Роль |
|------|------|
| `src/main.cpp` | вся логика helper'а (LoadLibrary + flat-API + CreateProcess + цикл) |
| `CMakeLists.txt` | сборка x86 / MSVC, без зависимостей |
| `steam_appid.txt` | AppID 10 (CS 1.6) — копируется в `runtime/` |
| `README.md` | инструкции для пользователя |
