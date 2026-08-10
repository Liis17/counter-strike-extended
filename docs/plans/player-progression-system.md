# План: система прогрессии игрока (статистика → опыт → уровни → скины)

Статус: план утверждён, реализация не начата.
Ветка разработки: `claude/player-progression-system-dteptj`.

## Зачем

В проекте нет учёта достижений игрока: сыгранные раунды, killfeed и табло живут только до конца
матча. Нужно считать победы/поражения и устранения, начислять за них опыт, копить его **локально
на машине игрока** (прогресс едет за игроком, а не привязан к серверу), выдавать уровни и открывать
по уровням скины оружия. Скины должны видеть **все** игроки, а не только владелец. Первая итерация —
перекрасы существующих моделей, чтобы проверить всю цепочку целиком.

Согласованные с владельцем проекта решения:

| Вопрос | Решение |
|--------|---------|
| Детект ботов | Сервер шлёт клиенту флаг (ReGameDLL знает `FL_FAKECLIENT` точно) |
| Профиль | Отдельный файл на каждый SteamID64, фолбэк — общий локальный |
| Опыт | За килл, хедшот, победу/поражение в раунде и в матче; боты дают 30% |
| Объём скинов | 2 ствола × 2 перекраса (AK-47, AWP — красный и золотой) |
| Формат конфигов | KV-текст как `scripts/HudLayout.txt`, парсинг `COM_ParseFile` |

## Разведка: что уже проверено в коде

Эти факты установлены чтением исходников — на них можно опираться без повторной проверки.

**Клиент (`src/cs16-client`)**

| Что | Где |
|-----|-----|
| Единственная точка подмены **своего** viewmodel: `gEngfuncs.CL_LoadModel(szViewModel, &m_pPlayer->pev->viewmodel)` | `cl_dll/cs_wpn/cs_weapons.cpp:434`, `CBasePlayerWeapon::DefaultDeploy` |
| Реализации оружия компилируются в клиент из `dlls/wpn_shared/*.cpp` через `file(GLOB CS_WPNSH_SRC ...)` | `cl_dll/CMakeLists.txt:9`; пример вызова — `dlls/wpn_shared/wpn_ak47.cpp:77` |
| Новые `.cpp` подхватываются автоматически (`file(GLOB "*.cpp")`, `"hud/*.cpp"`) | `cl_dll/CMakeLists.txt:6,10` |
| `MsgFunc_DeathMsg` читает: killer (byte), victim (byte), headshot (byte), оружие (string) | `cl_dll/death.cpp`, ~строка 171 |
| `MsgFunc_ScoreInfo` заполняет `g_PlayerExtraInfo[]` (frags/deaths/teamnumber) | `cl_dll/hud/scoreboard.cpp:563` |
| `MsgFunc_TeamScore` заполняет `g_TeamInfo[].frags` = выигранные раунды | `cl_dll/hud/scoreboard.cpp:691` |
| Свой слот `m_iPlayerNum`; конец матча `gHUD.m_iIntermission` | `cl_dll/hud.h:428`, `cl_dll/hud.h:1156` |
| Образец разбора KV-конфига: `COM_LoadFile` → цикл `COM_ParseFile` → `COM_FreeFile` | `cl_dll/hud_layout.cpp:72-191` |
| Запись файла: API движка умеет только читать, писать через `fopen`; путь — `sprintf(path,"%s/%s", gEngfuncs.pfnGetGameDirectory(), name)` | образец `game_shared/voice_banmgr.cpp:88` |
| Консольная команда: `gEngfuncs.pfnAddCommand("name", Fn)` | `cl_dll/hud_spectator.cpp:246` |
| Userinfo-cvar: `CVAR_CREATE("name","val", FCVAR_ARCHIVE\|FCVAR_USERINFO)` | `cl_dll/hud.cpp:317` |
| Хук user message по строковому имени: `HOOK_MESSAGE_FUNC(name, func)` | `cl_dll/cl_util.h:33` |
| Образец HUD-элемента (`m_szLayoutId` до `AddHudElem`, `GetLayoutPos`, `GetLayoutScale`) | `cl_dll/hud/timer.cpp:41-139` |
| `hud_player_info_t` содержит `uint64 m_nSteamID` (заполняется патчем движка из `cse_sid`) | `engine/cdll_int.h:77-91` |

**Сервер**

| Что | Где |
|-----|-----|
| `gamedll "dlls\mp.dll"`, и этот `mp.dll` собирается из ReGameDLL_CS | `src/cse/cstrike/gameinfo.txt`; `src/cs16-client/CMakeLists.txt:70` (`BUILD_SERVER`) |
| Единственная точка подмены **третьеличной** модели: `pev->viewmodel = ALLOC_STRING(szViewModel); pev->weaponmodel = ALLOC_STRING(szWeaponModel);` | ReGameDLL `regamedll/dlls/weapons.cpp`, `CBasePlayerWeapon::DefaultDeploy` |
| Чтение userinfo: `GET_KEY_VALUE(infobuffer, "name")` — тем же способом читается любой свой ключ | ReGameDLL `regamedll/dlls/client.cpp`, `ClientUserInfoChanged` |
| `p_`-модели **не** precache'ятся в файле оружия (только `v_` и `w_`) — место precache искать отдельно | ReGameDLL `regamedll/dlls/wpn_shared/wpn_ak47.cpp` |
| Userinfo-ключи движок ретранслирует всем клиентам, вырезая только префикс `_` | `SV_FullClientUpdate`, `engine/server/sv_client.c` |

⚠️ Заметка `Obsidian/counter-strike-extendedVault/Client/HUD-TeamBar.md` (~строка 220) утверждает, что
серверный `mp.dll` проприетарный и правки невозможны без перехода на ReGameDLL_CS. **Это устарело** —
ReGameDLL уже собирается. Заметку надо поправить.

## Архитектура

Разделение продиктовано тем, кто чем владеет в движке:

| Слой | Отвечает за | Почему |
|------|-------------|--------|
| Клиент (`cl_dll`) | Профиль, XP, уровни, разблокировки, свой viewmodel | Прогресс локальный и должен работать на любом сервере; предсказание владеет своим viewmodel |
| Сервер (ReGameDLL `mp.dll`) | Флаг «бот», подмена p_-модели для всех | Только сервер знает `FL_FAKECLIENT` и рассылает третьеличную модель всем клиентам |

Обмен — два уже существующих в движке канала:
- клиент → сервер: userinfo-ключ `cse_skins` (тот же механизм, что `cse_sid` в TeamBar);
- сервер → клиент: новое user message `CseInfo` с битовой маской слотов-ботов.

## Предусловие: свой форк ReGameDLL_CS

`src/cs16-client/.gitmodules` указывает на `https://github.com/Velaron/ReGameDLL_CS` — чужой
репозиторий, править напрямую нельзя. Нужен форк `Liis17/ReGameDLL_CS` и перевод submodule на него;
это ровно тот же приём, что уже применён к `mainui_cpp` (см. `Obsidian/counter-strike-extendedVault/CSE/menu.md`).
Ветка с правками — от текущего закреплённого коммита, чтобы можно было ребейзить с апстрима.

**Проверка:** `build-cse.cmd` собирается, поведение не изменилось, `runtime/cstrike/dlls/mp.dll` обновлён.

## Этап 1 — профиль, статистика, опыт, уровни

Новые файлы в `src/cs16-client/cl_dll/`:

- `cse_profile.h` / `cse_profile.cpp` — структура профиля, `CSE_LoadProfile()` / `CSE_SaveProfile()`,
  `CSE_AwardXP()`, `CSE_LevelForXP()`, команды `cse_stats`, `cse_profile_reload`.
- `cse_progression.cpp` — разбор `scripts/CseProgression.txt`.

Разбор — по образцу `CHud::LoadLayout()`, записи с **фиксированным** числом токенов (как блок
`HudDecorations`), без трюка с опциональным пятым токеном.

Имя файла профиля — `cse_profile_<steamid64>.txt`, при `m_nSteamID == 0` — `cse_profile_local.txt`.

Источники событий (всё уже приходит на клиент, новых сообщений от сервера не нужно):

| Событие | Хук | Условие |
|---------|-----|---------|
| Килл / хедшот | `MsgFunc_DeathMsg`, `cl_dll/death.cpp` | `killer == m_iPlayerNum && killer != victim`; 3-й байт = хедшот |
| Своя смерть | там же | `victim == m_iPlayerNum` |
| Победа/поражение в раунде | `MsgFunc_TeamScore`, `cl_dll/hud/scoreboard.cpp:691` | инкремент `g_TeamInfo[i].frags` сверяется с `g_PlayerExtraInfo[m_iPlayerNum].teamnumber` |
| Итог матча | `gHUD.m_iIntermission` | сравнить финальные счета команд |

Попутно — **хирургический фикс off-by-one** в `MsgFunc_TeamScore`: цикл `for(i = 0; i < m_iNumTeams; i++)`,
а страж после него `if(i > m_iNumTeams)` промах не ловит (нужно `>=`). Без фикса запись уходит в
чужой слот, а на счёт завязана вся логика раундов.

Формат `src/cse/cstrike/scripts/CseProgression.txt`:

```
"CseXP"
{
    "kill"           "100"
    "headshot"       "50"
    "death"          "0"
    "bot_multiplier" "0.3"
    "round_win"      "150"
    "round_loss"     "50"
    "match_win"      "500"
    "match_loss"     "150"
}

"CseLevels"
{
    "2" "1000"
    "3" "2500"
    "4" "4500"
    "5" "7000"
}

"CseSkins"
{
    "ak47" "red"  "3" "models/cse/v_ak47_red.mdl"  "models/cse/p_ak47_red.mdl"
    "ak47" "gold" "5" "models/cse/v_ak47_gold.mdl" "models/cse/p_ak47_gold.mdl"
    "awp"  "red"  "4" "models/cse/v_awp_red.mdl"   "models/cse/p_awp_red.mdl"
    "awp"  "gold" "5" "models/cse/v_awp_gold.mdl"  "models/cse/p_awp_gold.mdl"
}
```

Профиль `runtime/cstrike/cse_profile_<id>.txt` — тот же KV-стиль. Уровень **не хранится**, всегда
вычисляется из `xp` (один источник правды):

```
"CseProfile"
{
    "xp"           "12345"
    "kills"        "210"
    "headshots"    "44"
    "deaths"       "180"
    "round_wins"   "60"
    "round_losses" "52"
    "match_wins"   "7"
    "match_losses" "4"
    "unlocked"     "ak47:red;ak47:gold"
    "equipped"     "ak47:gold"
}
```

Установка конфига — `tools/install_progression.ps1` по образцу `tools/install_hud_layout.ps1`
(идемпотентное копирование), вызов добавить в `build-cse.cmd`.

Сохранение — не на каждое событие: по концу раунда, на `m_iIntermission` и на выходе, чтобы не
писать файл в бою.

**Проверка:** `server.cmd` + `start-cse.cmd`, сыграть 3 раунда → `cse_stats` печатает килы/смерти/
раунды, цифры совпадают с табло по `Tab`; после выхода файл профиля содержит те же значения;
повторный вход их подхватывает. **Коммит.**

## Этап 2 — флаг «бот» с сервера

Боты вытесняемые, слот может сменить владельца, поэтому флаг читается **в момент килла**, а не
кешируется при подключении.

- Сервер: регистрация сообщения `CseInfo` рядом с прочими `REG_USER_MSG`; широковещательная отправка
  битовой маски слотов-ботов при подключении/отключении клиента и на старте раунда.
- Клиент: `HOOK_MESSAGE_FUNC("CseInfo", ...)`, маска кладётся в `cse_profile.cpp`; `CSE_AwardXP()`
  для килла умножает на `bot_multiplier`, если бит жертвы взведён.

На чужих серверах сообщение не придёт — маска нулевая, все считаются людьми (осознанная деградация).

**Проверка:** килл бота даёт 30 XP, килл живого игрока со второго клиента — 100 XP; после вытеснения
бота живым игроком тот же слот сразу даёт полный опыт. **Коммит.**

## Этап 3 — генератор перекрасов

`.mdl` GoldSrc хранит текстуры 8-битными индексами с 256-цветной палитрой:
`mstudiotexture_t { char name[64]; int flags; int width, height, index; }`, по `index` лежат
`width*height` байт индексов и следом 768 байт RGB-палитры. **Перекрас = преобразование только
палитры**, геометрия и анимации не трогаются — самый дешёвый и безопасный способ.

- `tools/mdl_recolor.py` — Python (интерпретатор уже обязателен, `src/cs16-client/CMakeLists.txt:10`).
  Вход: исходный `.mdl`, сдвиг тона/тонировка, выход. Обрабатывает случай `numtextures == 0`, когда
  текстуры лежат в отдельном `<name>T.mdl`.
- `src/cse/cstrike/scripts/CseSkinRecipes.txt` — рецепты: исходная модель, преобразование, имя выхода.
- `tools/install_skins.ps1` — запускает генератор, кладёт результат в `runtime/cstrike/models/cse/`.

⚠️ Сгенерированные модели — производные от лицензионных ассетов Valve, поэтому **в git не
коммитятся** (та же причина, по которой `runtime/` в `.gitignore`). В репозиторий едут только скрипт
и рецепты; модели создаются на машине владельца лицензии.

**Проверка:** после `install_skins.ps1` в `runtime/cstrike/models/cse/` лежат 8 файлов (v_ и p_ для
4 комбинаций), открываются просмотрщиком моделей и отличаются цветом. **Коммит.**

## Этап 4 — скины: свой вид и вид для всех

Клиент:
- `cse_skins.cpp` — таблица из `CseProgression.txt`, состояние «разблокировано/надето», команды
  `cse_skin <weapon> <skin>` и `cse_skin_list`. Разблокировка проверяется по уровню; надеть
  неразблокированный скин нельзя.
- `cl_dll/cs_wpn/cs_weapons.cpp:434` — `szViewModel` пропускается через подменялку перед
  `gEngfuncs.CL_LoadModel()`.
- Публикация выбора: cvar `cse_skins` с `FCVAR_USERINFO`, значение — компактное `ak47:gold;awp:red`.
  `MAX_INFO_STRING` = 256, при 2 стволах запас огромный.

Сервер (ReGameDLL):
- `regamedll/dlls/client.cpp`, `ClientUserInfoChanged` — `GET_KEY_VALUE(infobuffer, "cse_skins")`,
  разбор в состояние игрока.
- `regamedll/dlls/weapons.cpp`, `CBasePlayerWeapon::DefaultDeploy` — подмена `szWeaponModel` перед
  `ALLOC_STRING`. Это же покрывает случай выключенного предсказания: функция присваивает и
  `viewmodel`, и `weaponmodel`.
- **Precache.** В GoldSrc отсутствие precache для `pev->weaponmodel` фатально. Стоковые `p_`-модели
  precache'ятся не в файле оружия — найти место (`grep -rn "p_ak47" regamedll/`) и добавить туда же
  все модели скинов; если места нет — precache в `Precache()` каждого затронутого оружия. Лимит
  движка на модели (512) не под угрозой: +8 файлов.
- Защита: файла скина нет → откат на стоковую модель, без краша.

**Проверка:** два клиента на одном сервере. У игрока с надетым скином он виден от первого лица; на
**втором** клиенте оружие в руках первого — того же цвета. Скин выше уровня не надевается. Удалить
файл модели → игра не падает, оружие стоковое. **Коммит.**

## Этап 5 — HUD-элемент прогресса

`cl_dll/hud/xpbar.cpp` — `CHudXPBar` по образцу `cl_dll/hud/timer.cpp`: `Init()` ставит
`strlcpy(m_szLayoutId, "XPBar", ...)` **до** `gHUD.AddHudElem(this)`, `Draw()` использует
`GetLayoutPos()` и `GetLayoutScale()`. Объявление в `cl_dll/hud.h`, вызов `Init()` в `CHud::Init()`.
Рисует уровень, полосу до следующего уровня и всплывающее «+XP» после события.

Регистрация в редакторе — `tools/hud-editor/editor.js`: id в `ELEMENT_IDS`, записи в
`ELEMENT_PREVIEWS` и `DEFAULT_ELEMENTS` (три реестра, как для TeamBar). Строка в
`src/cse/cstrike/scripts/HudLayout.txt`.

**Проверка:** `start-hud-editor.cmd` → подвинуть элемент → export → `install_hud_layout.ps1` → в игре
`hud_layout_reload 1`, позиция совпадает с превью. **Коммит.**

## Сводка по файлам

**Создать**
- `src/cs16-client/cl_dll/cse_profile.{h,cpp}`, `cse_progression.cpp`, `cse_skins.{h,cpp}`
- `src/cs16-client/cl_dll/hud/xpbar.cpp`
- `src/cse/cstrike/scripts/CseProgression.txt`, `CseSkinRecipes.txt`
- `tools/mdl_recolor.py`, `tools/install_progression.ps1`, `tools/install_skins.ps1`

**Изменить**
- Клиент: `cl_dll/cs_wpn/cs_weapons.cpp`, `cl_dll/death.cpp`, `cl_dll/hud/scoreboard.cpp`
  (+ фикс off-by-one), `cl_dll/hud.h`, `cl_dll/hud.cpp`
- Сервер (форк ReGameDLL): `regamedll/dlls/client.cpp`, `regamedll/dlls/weapons.cpp`, точка precache
- Обвязка: `src/cs16-client/.gitmodules`, `build-cse.cmd`, `tools/hud-editor/editor.js`,
  `src/cse/cstrike/scripts/HudLayout.txt`

**Obsidian** — новая заметка `CSE/progression.md` (архитектура, форматы файлов, точки кода), ссылка
в `Index.md`; обновить `Client/HUD-layout.md` (элемент `XPBar`), `Tooling/hud-editor.md`,
`Tooling/Tools.md` (новые скрипты и генератор), `Архитектура.md` (серверный `mp.dll` = ReGameDLL,
третий форк-submodule) и исправить устаревшее утверждение в `Client/HUD-TeamBar.md`.

## Проверка целиком

1. `build-cse.cmd` → `tools/install_skins.ps1` (генерация моделей).
2. `server.cmd de_dust2` + `start-cse.cmd`, второй клиент с другой машины/аккаунта.
3. Сыграть матч: `cse_stats` сверить с табло; выйти и зайти — прогресс на месте.
4. Набрать уровень (или временно занизить пороги в `CseProgression.txt` + `cse_profile_reload`),
   `cse_skin ak47 gold` → скин виден себе и **второму клиенту**.
5. Килл бота против килла живого — 30% против 100% опыта; вытеснение бота живым игроком не ломает учёт.
6. Негативные: удалить файл модели скина, удалить `CseProgression.txt`, зайти на чужой сервер — игра
   работает, прогресс копится, скины откатываются на стоковые.

## Риски

| Риск | Смягчение |
|------|-----------|
| ReGameDLL — чужой репозиторий | Предусловие: свой форк + перевод submodule (как `mainui_cpp`) |
| Точка precache стоковых `p_` моделей не найдена заранее | Поиск на этапе реализации; фолбэк — precache в `Precache()` каждого оружия |
| Локальный файл профиля правится блокнотом | Принято: прогрессия личная, не рейтинговая. Античит вне задачи |
| Чужой сервер | Опыт копится, скины видит только владелец, боты считаются людьми |
| Off-by-one в `TeamScore` | Хирургический фикс в этапе 1 до того, как на счёт завязана логика |
| Лицензионные модели отсутствуют в репозитории | Генератор работает на машине владельца лицензии, результат в gitignored `runtime/` |
