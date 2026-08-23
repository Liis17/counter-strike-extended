# HUD TeamBar — лента команд со счётом и аватарами

Parent: [[Index]] | Domain: [[Client/cs16-client]] | Связано: [[Client/HUD-layout]], [[Tooling/hud-editor]], [[CSE/rich_presence]]

**Статус: все пять этапов реализованы.** Заметка описывает дизайн, порядок работ и что именно
проверено.

| Точка | Что |
|-------|-----|
| `src/cs16-client/cl_dll/hud/teambar.cpp` | `CHudTeamBar`, потребитель общего avatar pipeline |
| `src/cs16-client/cl_dll/cse_player_avatars.{cpp,h}` | общий кэш Steam до `MAX_PLAYERS`, wanted.txt раз в 0,5 с, bot/fallback avatar для TeamBar и Scoreboard |
| `src/cs16-client/cl_dll/cse_bot_avatars.{cpp,h}` | аватары ботов: разбор списка, загрузка текстур, `CSE_BotAvatar()` |
| `src/xash3d-fwgs/engine/server/sv_client.c` | `SV_FakeConnect()` пишет боту случайный `cse_av` в userinfo |
| `src/cse/cstrike/gfx/cse/avatars/`, `scripts/CseBotAvatars.txt` | картинки ботов и их список |
| `src/cs16-client/cl_dll/hud.h`, `hud.cpp` | класс, член `CHud::m_TeamBar`, вызов `Init()` |
| `src/xash3d-fwgs/engine/client/dll_int/cl_game.c` | `pfnGetPlayerInfo` заполняет `m_nSteamID` из userinfo-ключа `cse_sid` |
| `src/cse/rich_presence/src/main.cpp` | Steam-сторона: SteamID64 + выкачка аватаров в TGA ([[CSE/rich_presence]]) |
| `src/cse/cstrike/scripts/HudLayout.txt` | запись `"TeamBar" "0" "40" "top_center" "1"` |
| `tools/hud-editor/editor.js` | id в реестрах + ветка `align: "center"` в `getElementPreview()` для TeamBar/Scoreboard |

## Методы

| Метод | Назначение |
|-------|-----------|
| `TeamBar_DrawDeadMark()` | Процедурно рисует светлый диагональный крест поверх затемнённого аватара устранённого игрока. |

**Проверено:**

- лента рисуется в бою: слоты T слева, счёт, слоты CT справа; вторая строка при шести и более
  игроках в команде; мёртвые сильнее затемнены и отмечены светлым диагональным крестом поверх
  аватара; счёт совпадает с табло;
- превью в редакторе совпадает с позицией в игре;
- хелпер по `wanted.txt` кладёт корректный TGA (`type 2, 64×64, 32 bpp, attributes 0x28` —
  ровно то, что читает `img_tga.c`);
- публикация своего id доехала: после чистого выхода в `runtime/cstrike/config.cfg` появляется
  `setinfo "cse_sid" "765611…"`, то есть общий `CSE_PublishSelf()` прочитал файл хелпера уже
  в игре (`Think()` работает только при подключении) и движок сохранил ключ в userinfo;
- клиент действительно перезаписывает `wanted.txt` в игре (в спектаторе — пустым, потому что
  в ленту попадают только игроки команд T/CT).

### Общий avatar pipeline

После появления [[Client/HUD-Scoreboard]] загрузка вынесена из `teambar.cpp` в
`cse_player_avatars.cpp`. TeamBar и Scoreboard используют один массив текстур и один writer
`cache/avatars/wanted.txt`; TeamBar больше не создаёт конкурирующий список SteamID. Обновление
списка вызывается из `CHudTeamBar::Think()` раз в 0,5 секунды и включает всех подключённых
Steam-игроков, а не только видимые слоты ленты. При отсутствии Steam-картинки порядок fallback:
bot avatar → первая буква имени.

## Аватары ботов

У бота нет SteamID, поэтому слот раньше падал в буквенный плейсхолдер. Теперь картинку назначает
сервер: `SV_FakeConnect()` выбирает для фейк-клиента случайный свободный `cse_av` в диапазоне
`0..255`, удерживая уже выданные номера за активными fake-клиентами. Если весь диапазон занят,
новый бот не создаётся, вместо выдачи повторного номера. Движок рассылает userinfo штатным
`SV_FullClientUpdate()` (вырезаются только ключи с префиксом `_`), клиент берёт
`номер % количество записей` из `scripts/CseBotAvatars.txt` и грузит файл
`gRenderAPI.GL_LoadTexture( путь, NULL, 0, ... )` — тем же способом, что `hud/sniperscope.cpp:57`
и `hud/spectator_gui.cpp:101` грузят свои шипнутые TGA. Картинки по сети не идут.
Клиентский массив рассчитан на 256 записей (`CSE_MAX_BOT_AVATARS`); при меньшем количестве
валидных строк используются только реально загруженные аватары. `tools/install_bot_avatars.ps1`
генерирует список автоматически по PNG/TGA-файлам из `gfx/cse/avatars/`.

Загрузка живёт в `CHudTeamBar::VidInit()`, а не в `Init()`: движок сбрасывает пользовательские
текстуры при рестарте видео и смене карты, и сохранённые с прошлой карты texnum протухли бы.

Одинаковые серверные номера у одновременно активных ботов не выдаются. При `cv_rotate_bots` YaPB
пересоздаёт ботов — они освобождают старые номера и законно получают новые. Так как клиент
применяет остаток от количества загруженных файлов, при списке меньше 256 разные серверные
номера теоретически могут ссылаться на одну картинку; текущая серверная гарантия относится именно
к значениям `cse_av`.

**Почему движок, а не YaPB.** У YaPB своя машинерия аватаров (`getRandomAvatar()`, `cv_show_avatars`,
ключ `*sid` — `src/manager.cpp:1166`), но `BotConfig::loadAvatarsConfig()` (`src/config.cpp:591`)
безусловно выходит на `GameFlags::Xash3D`, и обхода у этого guard'а нет. А `3rdparty/yapb` —
submodule на upstream `yapb/yapb`, так что путь через него означал бы форк чужого репозитория.

**Не проверено вживую:** финальная картинка «реальный аватар внутри слота» и рамка слота поверх
текстуры; для ботов — что назначенный сервером `cse_av` доезжает до клиента и превращается в
картинку. Обе проверки требуют входа в команду. Требуется зайти в команду, а ввод с клавиатуры в игру из среды агента не проходит
(SDL raw input). Ручная проверка: запустить `start-cse.cmd` при запущенном Steam, подключиться,
выбрать команду — свой аватар должен появиться в слоте за ~5–10 с (секунда на выкачку хелпером
плюс пятисекундный retry загрузки текстуры), с сохранением цветной рамки команды по краю слота.

Ретрансляция ключа сервером проверена только по коду: `SV_FullClientUpdate()`
(`engine/server/sv_client.c`) шлёт всем клиентам полный userinfo, вырезая лишь ключи с
префиксом `_`.

## Цель

Новый HUD-элемент во время матча: одна горизонтальная лента —
`[аватары T] [счёт T:CT] [аватары CT]`. Счёт — выигранные раунды через двоеточие (`1:3`).
Аватары — из Steam, с фолбэком-плейсхолдером. Элемент должен позиционироваться через
`scripts/HudLayout.txt` (см. [[Client/HUD-layout]]) и редактироваться в `tools/hud-editor`.

## Ключевой вывод разведки

**Правки движка для отрисовки картинок НЕ нужны.** `cs16-client` уже получает
`render_api_t` (`gRenderAPI`, `cl_dll/cdll_int.cpp:422`) и уже им пользуется:

| API | Сигнатура | Где уже применяется |
|-----|-----------|---------------------|
| `GL_LoadTexture` | `(name, buf, size, flags) -> texnum` | `cl_dll/hud.cpp:563` (`*white`); buf=NULL → грузит из FS gamedir; buf≠NULL → имя с `#` и расширением (`console.c:2282`: `"#gfx/conback.lmp"`) |
| `GL_CreateTexture` | `(name, w, h, rgba_buffer, flags)` | из сырого RGBA — ровно то, что отдаёт Steam `GetImageRGBA` |
| `GL_FreeTexture` | `(texnum)` | кеш идёт **по имени**, обновлённый аватар требует Free или нового имени |
| `GL_Bind` / `GL_SelectTexture` | `(tmu, texnum)` | `cl_dll/ammo.cpp:1590` (кастомный прицел) |

Форматы `imagelib` движка: tga / png / bmp / dds / ktx2. **JPG не поддерживается.**

Отрисовка квада — по существующему паттерну `DrawUtils::SPR_DrawAdditiveScaled()`
(`pTriAPI->RenderMode` + `Begin/TexCoord2f/Vertex3f/End`), только с `GL_Bind` вместо
`SpriteTexture`. **Не** использовать `pfnSPR_DrawGeneric` — грабли описаны в
[[Client/HUD-layout]] («блендинг при масштабировании спрайтов»).

Правка движка нужна ровно одна и крошечная — см. Этап 4.

## Откуда берутся данные

| Данные | Источник | Примечание |
|--------|----------|-----------|
| Счёт команд | `g_TeamInfo[]` (`cl_dll/hud/scoreboard.cpp`), заполняется `MsgFunc_TeamScore` | `name` = `"TERRORIST"` / `"CT"`, `frags` = выигранные раунды |
| Состав команд | `g_PlayerExtraInfo[i].teamnumber` (`TEAM_TERRORIST` / `TEAM_CT`) | индексы 1..`MAX_PLAYERS` (=64 в `hud.h:57`), сервер проекта — 12 слотов |
| Ники, «это я» | `g_PlayerInfoList[i].name`, `.thisplayer` | массив **не** обновляется сам — см. врезку ниже |
| Мёртв / жив | `g_PlayerExtraInfo[i].dead` | для усиленного затемнения аватара и светлого креста поверх него |
| SteamID64 | `hud_player_info_t.m_nSteamID` | поле **есть** в структуре, но движок его **не заполняет** — см. Этап 4 |
| Аватар бота | userinfo-ключ `cse_av`, читается `gEngfuncs.PlayerInfo_ValueForKey( i, "cse_av" )` | ставит `SV_FakeConnect()` (`sv_client.c:524`) всем фейк-клиентам: `COM_RandomLong( 0, 255 )`. По сети едет только число, картинка берётся по `номер % длина списка` |

⚠️ **Признак бота — наличие `cse_av`, а не ключ `*bot`.** YaPB публикует `*bot` только при
`show_latency 1` (`3rdparty/yapb/src/manager.cpp:1163`), так что существующий
`CSE_PlayerIsBot()` (`cl_dll/cse_profile.cpp:251`), от которого зависит `bot_multiplier` в XP,
на дефолтных настройках сервера возвращает false для всех ботов. Здесь эта зависимость не
используется; сам `CSE_PlayerIsBot()` не трогали.

⚠️ **`g_PlayerInfoList` обновляется не каждый кадр.** Заполняет его только
`CHudScoreboard::GetAllPlayersInfo()` (`scoreboard.cpp`), а вызывается он из
`DrawScoreboard()` (`:192` — то есть лишь пока держат `Tab`), из `MsgFunc_TeamInfo` (`:633`),
из `DeathMsg` (`death.cpp:198`) и из спектаторского кода. Для TeamBar этого мало: ленту видно
всегда. Метод публичный (`hud.h:442`) → в `CHudTeamBar::Think()` вызывать
`gHUD.m_Scoreboard.GetAllPlayersInfo()` с троттлингом (напр. раз в 0.5–1 с), не каждый кадр.
`g_PlayerExtraInfo[].dead` / `.teamnumber` — message-driven (`ScoreInfo`, `TeamInfo`, `DeathMsg`),
их обновлять не нужно.

`MsgFunc_TeamScore` обновляет `g_TeamInfo[]` напрямую; renderer читает тот же раундовый счёт,
поэтому отдельные score-поля и второй `HOOK_MESSAGE` не нужны.

## Геометрия и модель позиционирования

`GetLayoutPos()` при переопределении возвращает «сырую» точку якоря — центрирование живёт
только в *дефолтной* ветке каждого элемента (см. `Timer`). Поэтому:

- **Рекомендация: фиксированное число слотов на команду** (константа, напр. 5). Тогда ширина
  ленты постоянна, точка layout = **левый верхний угол ленты**, и превью в редакторе честно
  совпадает с игрой без правок его геометрической модели.
- Альтернатива (дороже): переменная ширина + новый case `align: "center"` в
  `getElementPreview()` (`tools/hud-editor/editor.js:158`) + вычитание половины ширины в
  `Draw()`. Риск рассинхрона превью и игры — тот же класс багов, что чинили коммиты
  «Fix multi-config client deployment for HUD anchors» и «Keep Timer's editor default at center».

Ширина = `2 * slots * (avatarW + gap) + scoreBlockW`, всё умножается на `GetLayoutScale()`.

## Этапы

### Этап 0 — разведка боем (spike, без кода в продакшене)

1. Временный `Con_Printf` дампа `g_TeamInfo[1..m_iNumTeams].name/frags/teamnumber` раз в секунду →
   **проверка:** счёт совпадает с табло `Tab` на протяжении нескольких раундов.
2. На клиенте `setinfo cse_sid 12345`, на втором клиенте — временный `Con_Printf` в
   `CL_UpdateUserinfo` (`engine/client/parse/cl_parse.c:1352`) →
   **проверка:** ключ доехал. Проверить попутно: запас `MAX_INFO_STRING` (256) с учётом штатных
   ключей CS, троттлинг `SV_ShouldUpdateUserinfo`, не вычищает ли `mp.dll` неизвестные ключи в
   `ClientUserInfoChanged`.

Результат Этапа 0 определяет, нужен ли фикс счёта и жизнеспособна ли схема из Этапов 3–5.

### Этап 1 — элемент `CHudTeamBar` с плейсхолдерами (видимая фича)

| Файл | Правка |
|------|--------|
| `src/cs16-client/cl_dll/hud/teambar.cpp` | новый: `Init` (`m_szLayoutId = "TeamBar"` до `AddHudElem`), `VidInit`, `Draw` |
| `src/cs16-client/cl_dll/hud.h` | объявление класса + член `CHudTeamBar m_TeamBar;` в `CHud` |
| `src/cs16-client/cl_dll/hud.cpp` | `m_TeamBar.Init();` в списке `CHud::Init()` (~строка 400) |
| CMake | правок не нужно: `cl_dll/CMakeLists.txt:10` — `file(GLOB CS_HUD_SRC "hud/*.cpp")`; но конфигурацию cmake надо перегенерировать |

Содержимое `Draw()`: гварды как у `Timer` (`HIDEHUD_ALL`, `m_iIntermission`; про `OBS_IN_EYE`
решить отдельно — ленту в спектаторе, скорее всего, показывать надо), сбор двух списков игроков,
плейсхолдер-аватар (`FillRGBABlend` цветом команды + иконка/буква ника), счёт цифрами
`DrawUtils::DrawHudNumber2` и двоеточие точками `FillRGBA` — ровно как в `hud/timer.cpp:120`.

**Проверка:** запуск `server.cmd` + `start-cse.cmd`, лента видна, счёт меняется по раундам,
живые/мёртвые отличаются, при 9 ботах не выходит за экран.

**Коммит** в конце этапа (правило CLAUDE.md).

### Этап 2 — редактор и конфиг

| Файл | Правка |
|------|--------|
| `tools/hud-editor/editor.js:3` | `"TeamBar"` в `ELEMENT_IDS` |
| `tools/hud-editor/editor.js:34` | запись в `ELEMENT_PREVIEWS`: `width`/`height` по формуле выше, `scalable: true`, `sample` |
| `tools/hud-editor/editor.js:47` | запись в `DEFAULT_ELEMENTS` (напр. `{ x: 0, y: 20, anchor: "top_center", scale: 1 }`) |
| `src/cse/cstrike/scripts/HudLayout.txt` | строка `"TeamBar" "x" "y" "anchor" "scale"` |
| `tools/install_hud_layout.ps1` | правок не требует — тупое копирование, whitelist id отсутствует |

Превью-семпл в редакторе рисуется как текст (`sample`), для ленты уместен псевдографический
`"▪▪▪▪▪ 1:3 ▪▪▪▪▪"` либо отдельная ветка отрисовки квадратов.

**Проверка:** `start-hud-editor.cmd` → подвинуть элемент → export → `install_hud_layout.ps1` →
в игре `hud_layout_reload 1` → позиция в игре совпадает с превью на всех девяти якорях.

**Коммит.** Обновить [[Client/HUD-layout]] (таблица поддерживаемых элементов) и [[Tooling/hud-editor]].

### Этап 3 — SteamID64 локального игрока

Расширить существующий хелпер `cse_steamrp.exe` ([[CSE/rich_presence]]) — он уже динамически
грузит `steam_api.dll` и живёт отдельным процессом (принцип «Steam только вне движка»):

1. После `SteamAPI_Init` — `SteamAPI_ISteamUser_GetSteamID` → записать id64 в
   `runtime/cstrike/cache/cse_steam_self.txt`.
2. Клиент при коннекте читает файл (`gEngfuncs.COM_LoadFile`) и вызывает
   `pfnClientCmd("setinfo cse_sid <id64>")`.

**Проверка:** на втором клиенте в userinfo первого виден ключ `cse_sid` (дамп из Этапа 0).

### Этап 4 — единственная правка движка (2 строки)

`src/xash3d-fwgs/engine/client/dll_int/cl_game.c`, `pfnGetPlayerInfo` (~строка 2860):

```c
pinfo->m_nSteamID = strtoull( Info_ValueForKey( player->userinfo, "cse_sid" ), NULL, 10 );
```

`Q_atoi64` в движке **нет** (проверено), поэтому `strtoull` из stdlib. Плюс: ранний `return`
в `pfnGetPlayerInfo` (пустой слот) заполняет только `name` и `thisplayer` — `m_nSteamID` там
надо явно обнулить, иначе у пустых слотов останется мусор от предыдущего вызова и проверка
«у ботов 0» будет плавающей.

Поле `m_nSteamID` уже есть в `hud_player_info_t` **обеих** копий структуры
(`xash3d-fwgs/engine/cdll_int.h:90` и `cs16-client/engine/cdll_int.h:90`), раскладка полей
сверена — **ABI не меняется**, расширять `cl_enginefunc_t` не нужно.

Клиенты получают полный userinfo всех игроков штатно: `SV_FullClientUpdate`
(`engine/server/sv_client.c:1178`) вырезает только ключи с префиксом `_`.

**Проверка:** клиент печатает id64 всех игроков-людей; у ботов 0.

### Этап 5 — сами аватары

1. Клиент пишет список нужных id64 в `<gamedir>/cache/avatars/wanted.txt`. ⚠️ В `cl_enginefunc_t`
   есть только чтение (`COM_LoadFile` / `COM_FreeFile`), записи нет → путь собирать через
   `gEngfuncs.pfnGetGameDirectory()` (`cdll_int.h:217`) и писать обычным `fopen`. Чтение обратно
   штатное: `GL_LoadTexture` с путём относительно gamedir идёт через FS движка.
2. Хелпер поллит файл; для каждого id: `RequestUserInformation(id, false)` → колбэк
   `PersonaStateChange` → `GetMediumFriendAvatar` (64×64) → `GetImageSize` + `GetImageRGBA` →
   пишет **несжатый 32-битный TGA** `cache/avatars/<id64>.tga` (~20 строк, без зависимостей;
   учесть BGRA-порядок и ориентацию строк). PNG-энкодер не нужен, JPG движок не прочитает.
3. Клиент раз в 5 с пробует загрузить файл. Важно: аватары появляются **после** старта движка,
   когда его пути поиска уже построены, поэтому файл читается обычным `fopen`/`fread`, а байты
   отдаются в `gRenderAPI.GL_LoadTexture("#cse_avatar_<id64>.tga", buf, size, TF_NOMIPMAP|TF_CLAMP)` —
   форма с префиксом `#` означает «декодировать буфер», расширение выбирает кодек (тот же приём,
   что у движка в `console.c` для conback). Результат кешируется как `id64 -> texnum`.
4. Фолбэк-плейсхолдер остаётся для ботов и игроков без Steam.

**Проверка:** свой аватар виден; аватар второго живого игрока виден; у ботов плейсхолдер;
выключенный Steam ничего не ломает.

## Отклонённые альтернативы

| Вариант | Почему нет |
|---------|-----------|
| Тянуть аватар напрямую по HTTPS из движка (`net_http` + mbedTLS в форке уже есть) | Steam CDN отдаёт **JPG**, в `imagelib` JPG-декодера нет → всё равно нужен конвертер → проще хелпером |
| Кастомное user message с сервера | Текущий `mp.dll` собирается из ReGameDLL_CS и регистрирует сообщения в `LinkUserMessages`; новый контракт потребует изменения серверной DLL и клиентского `HOOK_MESSAGE`. YaPB действительно проксирует регистрацию, но сам по себе не доказывает произвольный plugin path — см. [[CSE/map-actions]] |
| Линковать `steam_api` прямо в `cl_dll` | Ломает принцип «Steam — только во внешнем хелпере» из [[CSE/rich_presence]] (GPL-конфликт + разрядность) |
| Расширять `cl_enginefunc_t` новыми PIC_*-функциями | Не нужно: `gRenderAPI` уже даёт загрузку/отрисовку текстур, а `m_nSteamID` уже есть в структуре |
| Генерировать `.spr` на лету из RGBA | `SPR_Load` требует валидный IDSP (`Mod_LoadSpriteModel`), лишний дисковый ввод-вывод, лимит `MAX_CLIENT_SPRITES` |

## Ограничения по факту

Боевой конфиг проекта — `SERVER_MAXPLAYERS=12`, `BOT_QUOTA=9` (`server.cmd`). У ботов Steam-личности
нет, поэтому вся цепочка Этапов 3–5 даёт **один реальный аватар** (свой) плюс аватары живых
игроков, если они тоже играют этой сборкой и с запущенным Steam. Этапы 1–2 — самодостаточная
видимая фича; Этапы 3–5 можно отложить или отменить без ущерба для неё.

## Открытые вопросы

1. Слотов на команду: фиксированно 5 (рекомендация) или динамика по числу игроков?
2. Базовый размер аватара: 64 px; мёртвые получают усиленное затемнение и светлый диагональный крест.
3. Показывать ленту всегда, или скрывать в спектаторе / при `HIDEHUD_*`?
4. Счёт = выигранные раунды (`TeamScore`) — подтвердить, что это именно то, что нужно.
5. Порядок игроков в ленте: по номеру слота, по фрагам, свой игрок первым?
6. Плейсхолдер для ботов: иконка команды или первая буква ника?
