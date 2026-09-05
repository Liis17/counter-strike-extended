# Исследование: свои действия на картах

Статический результат первой итерации плана `docs/plans/custom-map-actions.md`.
Исходник стендовой карты скомпилирован J.A.C.K./ZHLT и локально установлен как производный BSP;
игровой стенд ещё не запускался. Строки «не проверено» ниже не являются отрицательным результатом.

## 1. Вопрос и краткий ответ

Да, карту с действием для всех игроков можно сделать без нового C++ в пределах штатных
сущностей ReGameDLL: `func_button` или `trigger_multiple` передают активацию по цепочке
`target`/`targetname`, а цель может открыть дверь, показать текст, проиграть звук, выдать
оружие, изменить HP или очки.

Главная деталь — сохранять правильный `pActivator`: кнопка и обычный триггер его запоминают,
`multi_manager` передаёт его дальше, а `trigger_relay` заменяет активатора собой.

Действие видно другим игрокам тремя разными способами: репликацией состояния сущности,
игровым user message или `SVC_TEMPENTITY`. Нельзя считать все эти случаи рассылкой
`MSG_ALL`.

Новое серверное поведение — новый classname, сложное условие или долговременное состояние —
требует кода сервера либо реально подтверждённого серверного расширения. В текущей сборке
серверная DLL — ReGameDLL, но отдельный плагинный путь этим исследованием не доказан.

Новый HUD-виджет требует двух сторон: сервер регистрирует и отправляет контракт сообщения,
клиент регистрирует `HOOK_MESSAGE` и рисует состояние. Для простого текста сначала следует
использовать существующие `game_text`, `TextMsg`, `HudText` или `HudTextPro`.

## 2. Зафиксированные решения и версия источников

Исследование выполнено 2026-08-10 в рабочей копии на ветке `main`. Зафиксированы SHA,
чтобы ссылки `file:line` ниже относились к конкретному содержимому, а не к памяти о HLSDK.

| Обозначение | Путь | SHA |
|---|---|---|
| `REGAME` | `src/cs16-client/3rdparty/ReGameDLL_CS` | `7be9d59dca1ee11d270e4631d7e3be0c67a1a82b` |
| `XASH` | `src/xash3d-fwgs` | `51df172aedee136f0c777b08aba059a314989fa2` |
| `CLIENT` (исследовательский snapshot) | `src/cs16-client` | `bd52fb6bb5ae5efec4423fccf96f4a54fe59e32e` |
| `YAPB` | `src/cs16-client/3rdparty/yapb` | `4967a220ba3a58c461ee1cef8b6fb37c6fd93b5e` |
| Parent | текущий корневой commit до этой итерации | `2d7d4e56b8e18640b8953c36c256d2139e916bde` |

В `src/cse/cstrike/gameinfo.txt:1-18` задано `gamedll "dlls\\mp.dll"`; обычный
`server.cmd` запускает CSE proxy поверх YaPB, задаёт 12 слотов и квоту 9 ботов.
Исключение — явный `server.cmd cse_lobby -nobots`, который использует штатный
`mp.dll` без YaPB для карты без waypoint-графа.
`src/cs16-client/CMakeLists.txt:56-64` подключает YaPB и ReGameDLL при `BUILD_SERVER`.
На Windows CMake ReGameDLL собирает Xash-совместимую библиотеку с postfix `mp`, а список
серверных исходников задан явно (`REGAME/regamedll/CMakeLists.txt:203-255,376-386,447-455`).

После исследовательского commit parent `src/cs16-client` был параллельно передвинут до
`96da2ba64d7e2749abb33ccf55dab8d1dc26e686` отдельной задачей progression. Ссылки на client
`file:line` в этом документе относятся к зафиксированному snapshot `bd52...`; перед будущей
реализацией их нужно повторно сверить с новым submodule SHA.

## 3. Что подтверждено в коде

### A. Штатная активация и сущности

| Факт | Подтверждение |
|---|---|
| `func_button` существует и может работать через Use или touch | `REGAME/regamedll/dlls/buttons.cpp:438-514,584-603,629-729` |
| `trigger_multiple` и `trigger_once` передают игрока в `ActivateMultiTrigger` | `REGAME/regamedll/dlls/triggers.cpp:963-1016,1026-1097` |
| `multi_manager` принимает произвольные цели с задержками | `REGAME/regamedll/dlls/triggers.cpp:179-204,289-363`; массив ограничен `MAX_MM_TARGETS = 16` в `REGAME/regamedll/dlls/triggers.h:94,150-151` |
| `trigger_relay` вызывает цели с собой как активатором | `REGAME/regamedll/dlls/triggers.cpp:127-167` |
| `target` ищет `targetname` и вызывает `Use(pActivator, pCaller, useType, value)` | `REGAME/regamedll/dlls/subs.cpp:111-168`; API `Use` — `REGAME/regamedll/dlls/cbase.h:113,160` |
| master-фильтр применяется до действия | `REGAME/regamedll/dlls/maprules.cpp:30-38`; поиск master — `REGAME/regamedll/dlls/util.cpp:995-1011` |
| штатные игровые цели включают текст, очки, HP, счётчик, экипировку, команду | `game_score` — `REGAME/regamedll/dlls/maprules.cpp:53-90`; `game_text` — `109-224`; `game_player_hurt` — `456-477`; `game_counter`/`game_counter_set` — `479-538`; `game_player_equip` — `540-607`; `game_player_team` — `609-642` |
| серверные операции игрока включают item, HP, armor, frags и money | объявления `TakeHealth`, `AddPoints`, `AddAccount`, `GiveNamedItem`/`GiveNamedItemEx` — `REGAME/regamedll/dlls/player.h:352-356,482,544-545`; реализации — `player.cpp:644-646,3544-3588,4569-4604,6528-6558,7044-7056` |
| список действительно связан с FGD | `REGAME/regamedll/extra/Toolkit/GameDefinitionFile/regamedll-cs.fgd:909-975,1387-1438,1702-1792,2188-2280` и соответствующие `LINK_ENTITY_TO_CLASS` в `REGAME/regamedll/dlls/maprules.cpp:53-609`, `buttons.cpp:438`, `triggers.cpp:127-1840` |

#### Инвентарь `LINK_ENTITY_TO_CLASS` и сверка FGD

Чтобы не ограничивать исследование предполагаемыми `game_*`, выполнена проверка по всем
`REGAME/regamedll/dlls/**/*.cpp` на SHA `7be9d59...`: 207 уникальных первых аргументов
`LINK_ENTITY_TO_CLASS`. FGD содержит 130 объявлений `PointClass`/`SolidClass`/`BaseClass`/
`NPCClass`. Это не обещание полного one-to-one совпадения: FGD включает базовые/tooling
описания, а GameDLL содержит оружие, алиасы и технические экспорты.

Полный сырой inventory (включая такие технические аргументы, как `beam`, `DelayedUse` и
`mapClassName`) сохранён здесь для воспроизводимой сверки:

<details>
<summary>207 аргументов LINK_ENTITY_TO_CLASS</summary>

`ambient_generic`, `ammo_338magnum`, `ammo_357sig`, `ammo_45acp`, `ammo_50ae`, `ammo_556nato`,
`ammo_556natobox`, `ammo_57mm`, `ammo_762nato`, `ammo_9mm`, `ammo_buckshot`, `armoury_entity`,
`beam`, `bodyque`, `bot`, `button_target`, `cycler`, `cycler_prdroid`, `cycler_sprite`,
`cycler_weapon`, `cycler_wreckage`, `DelayedUse`, `env_beam`, `env_beverage`, `env_blood`,
`env_bombglow`, `env_bubbles`, `env_debris`, `env_explosion`, `env_fade`, `env_fog`,
`env_funnel`, `env_global`, `env_glow`, `env_laser`, `env_lightning`, `env_message`, `env_rain`,
`env_render`, `env_shake`, `env_shooter`, `env_snow`, `env_sound`, `env_spark`, `env_sprite`,
`fireanddie`, `func_bomb_target`, `func_breakable`, `func_button`, `func_buyzone`,
`func_conveyor`, `func_door`, `func_door_rotating`, `func_escapezone`, `func_friction`,
`func_grencatch`, `func_guntarget`, `func_healthcharger`, `func_hostage_rescue`,
`func_illusionary`, `func_ladder`, `func_monsterclip`, `func_mortar_field`, `func_pendulum`,
`func_plat`, `func_platrot`, `func_pushable`, `func_rain`, `func_recharge`, `func_rot_button`,
`func_rotating`, `func_snow`, `func_tank`, `func_tankcontrols`, `func_tanklaser`,
`func_tankmortar`, `func_tankrocket`, `func_trackautochange`, `func_trackchange`,
`func_tracktrain`, `func_train`, `func_traincontrols`, `func_vehicle`, `func_vehiclecontrols`,
`func_vip_safetyzone`, `func_wall`, `func_wall_toggle`, `func_water`, `func_weaponcheck`,
`game_counter`, `game_counter_set`, `game_end`, `game_player_equip`, `game_player_hurt`,
`game_player_team`, `game_score`, `game_team_master`, `game_team_set`, `game_text`,
`game_zone_player`, `gib`, `gibshooter`, `grenade`, `hostage_entity`, `info_bomb_target`,
`info_hostage_rescue`, `info_intermission`, `info_landmark`, `info_map_parameters`,
`info_null`, `info_player_deathmatch`, `info_player_start`, `info_spawn_point`, `info_target`,
`info_teleport_destination`, `info_vip_start`, `infodecal`, `item_airbox`, `item_airtank`,
`item_antidote`, `item_assaultsuit`, `item_battery`, `item_healthkit`, `item_kevlar`,
`item_longjump`, `item_security`, `item_sodacan`, `item_suit`, `item_thighpack`, `light`,
`light_environment`, `light_spot`, `mapClassName`, `momentary_door`, `momentary_rot_button`,
`monster_hevsuit_dead`, `monster_mortar`, `monster_scientist`, `multi_manager`, `multisource`,
`path_corner`, `path_track`, `player`, `player_loadsaved`, `player_weaponstrip`,
`point_clientcommand`, `point_servercommand`, `soundent`, `spark_shower`, `speaker`,
`target_cdaudio`, `test_effect`, `trigger`, `trigger_auto`, `trigger_autosave`, `trigger_camera`,
`trigger_cdaudio`, `trigger_changelevel`, `trigger_changetarget`, `trigger_counter`,
`trigger_endsection`, `trigger_gravity`, `trigger_hurt`, `trigger_monsterjump`,
`trigger_multiple`, `trigger_once`, `trigger_push`, `trigger_random`, `trigger_random_time`,
`trigger_random_unique`, `trigger_relay`, `trigger_setorigin`, `trigger_teleport`,
`trigger_transition`, `weapon_ak47`, `weapon_aug`, `weapon_awp`, `weapon_c4`, `weapon_deagle`,
`weapon_elite`, `weapon_famas`, `weapon_fiveseven`, `weapon_flashbang`, `weapon_g3sg1`,
`weapon_galil`, `weapon_glock18`, `weapon_hegrenade`, `weapon_knife`, `weapon_m249`,
`weapon_m3`, `weapon_m4a1`, `weapon_mac10`, `weapon_mp5navy`, `weapon_p228`, `weapon_p90`,
`weapon_scout`, `weapon_sg550`, `weapon_sg552`, `weapon_shield`, `weapon_smokegrenade`,
`weapon_tmp`, `weapon_ump45`, `weapon_usp`, `weapon_xm1014`, `weaponbox`, `world_items`,
`worldspawn`.

</details>

Автоматическая set-сверка дала следующие расхождения, которые не следует молча считать
ошибкой: FGD-only — `env_lighting`, `env_smoker`, `info_compile_parameters`, `info_lights_rad`,
`info_texlights`, `item_nvgs`; raw C++-only включает weapon/ammo exports, технические
алиасы и классы без FGD-описания. Для action-рецептов выше каждый classname дополнительно
сверен вручную по коду и FGD-строкам; FGD остаётся редакторской подсказкой, не источником
server spawn behavior.

### B. Граница расширения

| Факт | Подтверждение |
|---|---|
| неизвестный classname сначала ищется как экспорт GameDLL, затем может попасть в Xash-расширение или `custom`; при отсутствии spawn-функции логируется ошибка и edict освобождается | `XASH/engine/server/sv_game.c:1056-1130` |
| загрузка entity lump вызывает `pfnSpawn`, а возврат `-1` освобождает сущность | `XASH/engine/server/sv_game.c:5056-5097` |
| внешний `maps/<map>.ent` заменяет entity lump только если новее BSP | `XASH/engine/common/mod_bmodel.c:2298-2340` |
| `entpatch <mapname>` — встроенный способ записать entity patch | `XASH/engine/server/sv_cmds.c:596-620,1034-1046`; запись patch — `XASH/engine/server/sv_game.c:786-812,839-871` |
| YaPB проксирует `pfnRegUserMsg` и предоставляет `SV_CreateEntity`, разрешающий символ в GameDLL | `YAPB/src/linkage.cpp:770-783,1121-1140` |
| YaPB содержит Metamod `Meta_Query`/`Meta_Attach`, но текущий launcher не доказывает загрузку произвольного plugin path | интерфейс YaPB — `YAPB/src/linkage.cpp:958-1019`; standalone/Metamod ветки — `YAPB/src/engine.cpp:1036-1076`; текущий запуск — `server.cmd:7,65-74`; результат: runtime loader не проверен |

### C. User message и клиентский HUD

| Факт | Подтверждение |
|---|---|
| сервер регистрирует сообщения в `LinkUserMessages()` до игровой работы | `REGAME/regamedll/dlls/client.cpp:143-180,227-231,3866`; объявление — `REGAME/regamedll/dlls/client.h:122,214-296` |
| в текущем сервере уже есть `HudText`, `HudTextPro`, `TextMsg`, `ScreenShake`, `ScreenFade` | `REGAME/regamedll/dlls/client.cpp:156-159,179-180`; размеры задаются там же |
| клиентский hook — макрос `HOOK_MESSAGE`, а обработчики распределены по модулям | `CLIENT/cl_dll/cl_util.h:33-37`; `message.cpp:44-54,594-682`; `text_message.cpp:32-39,182-...`; HUD hooks — `hud.cpp:294-315` |
| существующий HUD уже инициализируется в `CHud::Init`, а HUD-исходники подключаются glob-ом | `CLIENT/cl_dll/hud.cpp:409,434-436`; `CLIENT/cl_dll/CMakeLists.txt:6-10` |
| существующий путь HUD и три реестра редактора уже описаны отдельно | `docs/plans/player-progression-system.md:34-49,373-383`; образец timer — `CLIENT/cl_dll/hud/timer.cpp:41-139`; editor — `tools/hud-editor/editor.js:3,35-65` |
| новый серверный `.cpp` нельзя рассчитывать подхватить glob-ом ReGameDLL | `REGAME/regamedll/CMakeLists.txt:203-255` — явный `GAMEDLL_SRCS` |

### D. Сеть, лимиты и доставка

| Факт | Подтверждение |
|---|---|
| текущий предел одного user message — 2048 байт; число user messages — 197 | `XASH/engine/common/common.h:136`; `XASH/engine/common/protocol.h:109-125`; сервер проверяет размер/слоты в `XASH/engine/server/sv_game.c:2633-2686,3460-3490`, клиент — `XASH/engine/client/parse/cl_parse.c:2224-2269` |
| доступны `MSG_INIT`, `MSG_ALL`, `MSG_BROADCAST`, `MSG_PAS[_R]`, `MSG_PVS[_R]`, `MSG_ONE`, `MSG_ONE_UNRELIABLE`, `MSG_SPEC` | константы `XASH/common/const.h:574-583`; выбор надёжности, PVS/PAS и адресата — `XASH/engine/server/sv_game.c:369-415` |
| протокольный максимум edict — 8192, но текущая игра задаёт `max_edicts 1800` | `XASH/engine/common/protocol.h:116-119`; `src/cse/cstrike/gameinfo.txt:14`; сервер использует `GI->max_edicts` и отказывает при исчерпании — `XASH/engine/server/sv_game.c:1044-1045,5313-5320` |
| precache-лимиты различаются: модели, звуки, generic-файлы | `XASH/engine/common/protocol.h:109-125`; проверки — `XASH/engine/server/sv_init.c:116-175,252-260` |
| карта может читать `.res` и `reslist.txt`, а WAD добавляются как generic resources | `XASH/engine/server/sv_init.c:299-360` |
| сервер объявляет загрузку ресурсов и `sv_downloadurl`; клиент учитывает `cl_allowdownload` и `cl_download_ingame` | `XASH/engine/server/sv_main.c:51-60`; `XASH/engine/server/sv_custom.c:544-566`; `XASH/engine/client/cl_main.c:35-38`; `XASH/engine/client/cl_custom.c:45-83` |
| serverdata содержит CRC BSP; клиент сравнивает его со своей картой и отключается при отличии | `XASH/engine/server/sv_client.c:1483-1492`; `XASH/engine/client/parse/cl_parse.c:873-883` |

## 4. Как действие становится видимым другим игрокам

### 4.1. Состояние сущности и обычная репликация

Дверь — не собственный user message. `func_door` связан с `CBaseDoor`, его `Use` запоминает
активатора и запускает `DoorActivate`/`DoorGoUp`, меняя серверное состояние и движение
сущности (`REGAME/regamedll/dlls/doors.cpp:187,457-532`). Xash отправляет дельты состояний
сущностей через `SV_EmitPacketEntities` и `MSG_WriteDeltaEntity`
(`XASH/engine/server/sv_frame.c:224-350,601-689`). Поэтому видимая дверь требует совпадающей
карты и обычной репликации entity state, а не нового HUD-сообщения.

`env_sprite` работает аналогично на уровне своей сущности: `Use` переключает `TurnOn`/`TurnOff`
и `pev->effects` (`REGAME/regamedll/dlls/effects.cpp:1180-1205,1343-1354`). Это не тот же
механизм, что у beam или текстового события.

### 4.2. GameDLL user messages

`env_shake` вызывает `UTIL_ScreenShake`; сервер отправляет `gmsgShake` каждому подходящему
игроку через `MSG_ONE`, учитывая radius и `FL_ONGROUND`
(`REGAME/regamedll/dlls/effects.cpp:1762-1806`; `REGAME/regamedll/dlls/util.cpp:497-539`).
`env_fade` выбирает `UTIL_ScreenFade` для активатора или `UTIL_ScreenFadeAll`, оба пути
используют `gmsgFade` и `MSG_ONE` (`REGAME/regamedll/dlls/effects.cpp:1808-1857`;
`REGAME/regamedll/dlls/util.cpp:557-586`).

Это отличается от `SVC_TEMPENTITY`: user message имеет имя, зарегистрированное сервером до
подключения клиента, и обработчик `HOOK_MESSAGE` на клиенте. Если адресат не является частью
контракта, нельзя автоматически заменять его на `MSG_ALL`.

### 4.3. `SVC_TEMPENTITY`

`game_text` с флагом All Players не посылает `MSG_ALL`: `CGameText::Use` вызывает
`UTIL_HudMessageAll`, а та проходит по игрокам и для каждого вызывает `UTIL_HudMessage`
(`REGAME/regamedll/dlls/maprules.cpp:109-224`; `REGAME/regamedll/dlls/util.cpp:595-650`).
Внутри используется `MSG_ONE`, `SVC_TEMPENTITY` и `TE_TEXTMESSAGE`
(`REGAME/regamedll/dlls/util.cpp:595-638`). Обычный `TextMsg` — отдельный user message,
зарегистрированный в `client.cpp:156-159` и обработанный в `CLIENT/cl_dll/text_message.cpp:32-39`.

`env_beam` выбирает `SVC_TEMPENTITY` и `MSG_BROADCAST` для beam-сообщений
(`REGAME/regamedll/dlls/effects.cpp:611-651,716-720`). `ambient_generic` вызывает
движковый `EMIT_AMBIENT_SOUND`; для `Play Everywhere` используется `ATTN_NONE`, а обычная
рассылка ambient sound в текущем Xash идёт через `MSG_ALL`
(`REGAME/regamedll/dlls/sound.h:100-106`; `sound.cpp:67-94,194-224`;
`REGAME/regamedll/dlls/util.cpp:458-474`; `XASH/engine/server/sv_game.c:2068-2100`).

## 5. Уровень 1 — карта без нового кода

Ниже рецепты, которые подтверждены цепочкой `LINK_ENTITY_TO_CLASS` → `Use` → targets.
Они описывают конфигурацию созданного исходника карты; игровой стенд ещё не запускался.

| Цель | Цепочка | Важное условие |
|---|---|---|
| Открыть дверь от кнопки | `func_button` → `func_door` | Кнопка должна иметь `target`, дверь — соответствующий `targetname`; `CBaseDoor::Use` принимает активатора (`REGAME/regamedll/dlls/buttons.cpp:438,695-729`; `doors.cpp:187,457-491`) |
| Показать сообщение всем | `func_button`/`trigger_multiple` → `game_text` | Spawnflag `All Players = 1`; FGD предлагает каналы 1–4 (`REGAME/regamedll/dlls/maprules.h:93-106`; FGD `1765-1792`). Код канал не ограничивает, поэтому 1–4 — стабильный контракт редактора, а не runtime clamp |
| Проиграть звук всем | кнопка/триггер → `ambient_generic` | `Play Everywhere = 1` даёт `ATTN_NONE`; `Start Silent = 16` только откладывает старт, WAV всё равно precache-ится (`REGAME/regamedll/dlls/sound.h:100-106`; `sound.cpp:75-94,198-224`) |
| Сделать визуальный эффект | target на `env_sprite`, `env_beam`, `env_shake` или `env_fade` | Выбирать сущность по семантике: sprite — entity state, beam — tempentity, shake/fade — user messages |
| Выдать оружие нажавшему | `func_button` → `game_player_equip` | Ставить `Use Only = 1` (`SF_PLAYEREQUIP_USEONLY`), target должен быть прямым или сохранять player `pActivator`; `EquipPlayer` вызывает `GiveNamedItemEx` (`REGAME/regamedll/dlls/maprules.h:245-259`; `maprules.cpp:574-607`) |
| Вылечить активатора | `func_button`/`trigger_multiple` → `game_player_hurt` | Отрицательный `dmg` вызывает `TakeHealth(-dmg)`, положительный — `TakeDamage` (`REGAME/regamedll/dlls/maprules.cpp:456-477`) |
| Добавить очки | кнопка/триггер → `game_score` | Меняется player frags либо счёт команды, если включён соответствующий spawnflag; это не деньги (`REGAME/regamedll/dlls/maprules.cpp:53-90`; `maprules.h:66-84`) |
| Сложить несколько действий | `func_button`/`trigger_multiple` → `multi_manager` → до 16 целей | `multi_manager` сохраняет `pActivator` и запускает цели по задержкам (`REGAME/regamedll/dlls/triggers.cpp:179-204,289-363`; `triggers.h:94`) |

Для действия конкретного нажавшего не вставлять `trigger_relay` между активатором и целью,
если цель требует игрока: relay делает `this` новым активатором
(`REGAME/regamedll/dlls/triggers.cpp:127-167`). `multi_manager` для этой задачи подходит,
поскольку его `ManagerUse` сохраняет исходный `pActivator` (`triggers.cpp:343-363`).

## 6. Граница штатных сущностей

| Хочу | Доступно ли стоком | Вывод |
|---|---|---|
| Выдать/отнять деньги | Не найдено среди проверенных `game_*` сущностей | `CBasePlayer::AddAccount` существует как серверный метод (`REGAME/regamedll/dlls/player.h:482,744`; реализация `player.cpp:3544-3588`), но `maprules.cpp` его не вызывает. Нужен новый серверный код или существующая отдельная серверная команда/расширение; плагинный путь не подтверждён |
| Ограничить действие master-условием, командой или счётчиком | Частично да | Использовать `master`, `game_team_master`, `game_counter`/`game_counter_set`; их проверка и `USE_TYPE` уже есть (`REGAME/regamedll/dlls/maprules.cpp:228-353,479-538`; `subs.cpp:122-168`). Произвольное выражение всё равно требует кода |
| Действовать только на активатора или на всех | Да, но цепочка важна | Активатор доступен через `pActivator`; для всех есть `game_text` All Players, `ambient_generic` Everywhere, fade/shake с собственными правилами получателей (`REGAME/regamedll/dlls/maprules.cpp:196-218`; `sound.cpp:75-94`; `effects.cpp:1803-1854`) |
| Сохранить пользовательское состояние между раундами | Не закрыто статическим чтением | В штатных сущностях есть локальное состояние счётчиков и задержек (`REGAME/regamedll/dlls/maprules.cpp:479-538`; `triggers.cpp:289-363`), но нужный reset/персистентность конкретного дизайна требует отдельной проверки стендом |
| Занять отдельный текстовый канал | Ограниченно | FGD предлагает четыре канала `game_text`; совпадение с другими HUD-текстами — конфликт контента, а не новый сетевой протокол (`regamedll-cs.fgd:1785-1792`; `util.cpp:602`) |
| Сделать полностью новый визуальный HUD-виджет | Нет, не одной картой | Карта может вызвать существующий текстовый путь, но новый тип данных и отрисовка требуют уровня 3 (`REGAME/regamedll/dlls/client.cpp:143-180`; `CLIENT/cl_dll/cl_util.h:33-37`; `CLIENT/cl_dll/hud.cpp:409`) |

## 7. Уровни 2–3 — расширение

### Уровень 2: серверное расширение

Для нового classname нужен экспорт, который Xash сможет разрешить по имени
(`XASH/engine/server/sv_game.c:1061-1108`). В ReGameDLL это естественно оформляется как
`LINK_ENTITY_TO_CLASS` с `KeyValue`, `Spawn`, `Precache` и `Use`, но это будет изменение
серверной C++ DLL. Новый исходник нужно добавить в явный `GAMEDLL_SRCS`, затем пересобрать и
установить `mp.dll` (`REGAME/regamedll/CMakeLists.txt:203-255,400-413`).

YaPB действительно имеет прокси для user messages и Xash `SV_CreateEntity`
(`YAPB/src/linkage.cpp:770-783,1121-1140`), но по этим участкам нельзя обещать, что внешний
AMXX/ReAPI/Metamod-плагин будет загружен, зарегистрирует classname и совместимо проживёт на
стороннем vanilla-сервере. Это отдельное решение и отдельный runtime-тест.

### Уровень 3: серверный эвент и HUD

Проверенная схема:

```text
map entity
    -> C++ Use(pActivator)
    -> registered user message
    -> client HOOK_MESSAGE
    -> HUD state / Draw()
```

Серверная регистрация должна произойти до подключения клиента через `LinkUserMessages`
(`REGAME/regamedll/dlls/client.cpp:143-180,3866`). Клиентский `cl_dll` добавляет обработчик
через `HOOK_MESSAGE` (`CLIENT/cl_dll/cl_util.h:33-37`), а визуальный элемент живёт в
HUD-модулях (`CLIENT/cl_dll/CMakeLists.txt:6-10`; текущий `CHud::m_TeamBar.Init()` —
`CLIENT/cl_dll/hud.cpp:409`).

Сначала следует проверить, покрывает ли задачу существующий `HudText`, `HudTextPro` или
`TextMsg` (`REGAME/regamedll/dlls/client.cpp:156-159`; `CLIENT/cl_dll/message.cpp:44-54`).
Если нужен отдельный контракт, предварительный вариант для будущего решения такой — он не
зарегистрирован и не реализован:

| Поле | Предложение |
|---|---|
| Имя | `CSEMapEvent` |
| Версия | `uint8 version = 1` первым байтом |
| Payload | фиксированные `uint8 event_type`, `uint16 source_entindex`, `int32 value` — всего 8 байт |
| Получатели | выбирать для каждого события: `MSG_ONE`, `MSG_ALL`, `MSG_PVS[_R]` или иной подходящий адресат |
| Регистрация | `REG_USER_MSG("CSEMapEvent", 8)` до коннекта |
| Клиент | `HOOK_MESSAGE(..., CSEMapEvent)` с проверкой версии и размера |
| Ограничение | payload существенно меньше текущих 2048 байт (`XASH/engine/common/common.h:136`) |

`MSG_ALL` здесь не является универсальным решением: адресат — часть контракта события,
а Xash различает надёжность, PVS/PAS и отправку одному игроку
(`XASH/common/const.h:574-583`; `XASH/engine/server/sv_game.c:369-415`).

## 8. Альтернативы и архитектурное решение

| Вариант | Что даёт | Ограничение/решение |
|---|---|---|
| Штатные map entities | Уже работают в текущем `mp.dll`/ReGameDLL и не требуют нового артефакта | Выбранный путь для уровня 1 |
| `maps/<map>.ent` | Быстро меняет entity lump без перекомпиляции BSP; Xash поддерживает более новый `.ent` | Это patch/прототип, не исходник карты и не выбранный способ поставки; его доставка клиенту и CRC ещё должны быть проверены (`XASH/engine/common/mod_bmodel.c:2298-2340`) |
| `entpatch` | Позволяет получить entity patch из текущей карты | Удобен для эксперимента, но не заменяет `.map` и install-контракт (`XASH/engine/server/sv_cmds.c:596-620,1034-1046`) |
| Поддерживаемый plugin path | Может избежать изменения исходника ReGameDLL, если loader реально предоставляет нужные hooks | В текущем исследовании доказаны только YaPB wrappers, не загрузка произвольного плагина; до реализации нужен отдельный proof |
| Форк ReGameDLL | Прямой и контролируемый путь для custom classname/user message | Нарушает правило «собственный код только в `src/cse/`». Сейчас exception не принят; перед ним нужны решение, зафиксированный fork SHA, обновление CMake и install/deploy |
| AMXX/ReAPI как предположение | Может быть знакомым экосистемным решением | Не объявлять доступным без проверки установленного загрузчика и API именно этой сборки |

Неизвестный point classname в текущем Xash ожидаемо даёт `No spawn function for ...` и
освобождение edict (`XASH/engine/server/sv_game.c:1078-1129`). Это подтверждает точечный
probe-сценарий. Поведение связанной с неизвестным brush classname геометрии/коллизии
статически не фиксирую: нужен отдельный runtime-тест, и результат нельзя переносить на
сторонний vanilla-сервер.

## 9. Тулчейн и доставка карты

Источник карты и производный артефакт связаны так:

```text
src/cse/maps/<name>.map
        -> Hammer / J.A.C.K. + выбранные компиляторы
        -> производный <name>.bsp
        -> будущий идемпотентный install script
        -> runtime/cstrike/maps/<name>.bsp
```

Исходник стенда создан в `src/cse/maps/cse_test_actions.map`. Он использует штатные текстуры из
`halflife.wad` и существующий `buttons/button3.wav`; отдельные WAD/WAV-ассеты проекта не добавлялись.
J.A.C.K./ZHLT 3.4 собрал `hlcsg → hlbsp → hlvis → hlrad` без ошибок; производный
`cse_test_actions.bsp` установлен локально в `runtime/cstrike/maps/` и не является версионируемым
исходником. Проектные FGD/VHLT и `tools/install_maps.ps1` не добавлялись. Текущий FGD ReGameDLL
находится в `REGAME/regamedll/extra/Toolkit/GameDefinitionFile/regamedll-cs.fgd`; его
classname-описания сверены с `LINK_ENTITY_TO_CLASS`.

Текущий build/deploy-контур собирает engine и client, копирует их в `runtime`, затем запускает
только install-скрипты локализации, YaPB map configs и HUD layout
(`build-cse.cmd:13-50`). `tools/install_yapb_map_configs.ps1:17-78,90-117` читает уже
установленные `.bsp` из `runtime/cstrike/maps` или архивов, создаёт отсутствующие cfg в
`src/cse/yapb/conf/maps` и копирует cfg в runtime. Он **не устанавливает карты**.

Для реальной доставки ресурсная цепочка такая:

1. Xash читает `maps/<map>.res` и `reslist.txt`, регистрирует generic resources и WAD
   (`XASH/engine/server/sv_init.c:299-360`).
2. Сервер передаёт resource list и, если задан, `sv_downloadurl`
   (`XASH/engine/server/sv_custom.c:544-566`).
3. Сервер разрешает загрузку только при `sv_allowdownload`, а клиент учитывает
   `cl_allowdownload` и `cl_download_ingame`
   (`XASH/engine/server/sv_main.c:55-60`; `sv_client.c:2005-2026`;
   `XASH/engine/client/cl_main.c:35-38`; `cl_custom.c:45-83`).
4. Сервер отправляет CRC BSP в `serverdata`; при несовпадении клиент пишет
   `Your map [...] differs from the server's.` и отключается
   (`XASH/engine/server/sv_client.c:1483-1492`; `XASH/engine/client/parse/cl_parse.c:873-883`).

YaPB map cfg и waypoint graph — разные артефакты. Текущий install script касается только cfg;
документация YaPB направляет waypoint graph в отдельный репозиторий
(`YAPB/README.md:12`). Для стенда нельзя считать наличие waypoint гарантированным: после
старта нужно либо отключить ботов `yb_quota 0`, либо заранее обеспечить graph.

## 10. Ограничения и риски

* `MAX_USERMSG_LENGTH` в этой сборке равен 2048, но это свойство текущего Xash, а не обещание
  совместимости с GoldSrc или другим клиентом (`XASH/engine/common/common.h:136`).
* В user message доступны 197 слотов; при добавлении сообщения надо учитывать уже занятые
  ReGameDLL messages (`XASH/engine/common/protocol.h:123-125`; `REGAME/regamedll/dlls/client.cpp:143-231`).
* `max_edicts 1800` — лимит этой gameinfo, а 8192 в protocol header — только протокольный
  верхний предел. Превышение реального `GI->max_edicts` заканчивается ошибкой no free edicts
  (`src/cse/cstrike/gameinfo.txt:14`; `XASH/engine/server/sv_game.c:1044-1045`).
* Precache моделей, звуков и generic resources имеет отдельные лимиты; не смешивать их с
  edicts, leafs или размером user message (`XASH/engine/common/protocol.h:109-125,171`;
  `XASH/engine/server/sv_init.c:116-175,252-260`).
* Клиент с другой картой не является корректным негативным тестом «действие не пришло»:
  штатная реакция Xash — CRC mismatch и disconnect. Нужно отдельно зафиксировать cvars,
  resource list и фактическую фазу загрузки.
* Новый серверный C++ затронет `mp.dll`/YaPB deployment и потребует повторной проверки
  клиент-серверной совместимости. Прямой форк сейчас не выбран, чтобы не нарушать правило
  хранения собственного кода в `src/cse/`.
* Карта, FGD, WAD и прочие производные ассеты могут иметь отдельные лицензии; перед
  распространением нужен юридический и asset-аудит. В этой итерации ассеты не добавлялись.

## 11. Рекомендация и следующий шаг

Для ближайшего результата выбрать уровень 1: собрать одну тестовую карту на штатных сущностях
и доказать на двух клиентах `game_text`, звук, дверь, очки, HP и экипировку. Самый короткий
путь к видимому событию — `func_button`/`trigger_multiple` → `multi_manager` → `game_text` с
All Players; для персонального эффекта — прямой target на `game_player_equip` или
`game_player_hurt`.

После стенда отдельным решением выбрать одно из двух направлений:

1. существующие серверные сущности и существующий HUD-текст;
2. поддерживаемый путь уровня 2/3: ReGameDLL fork с явным exception в архитектуре либо
   доказанный plugin loader.

Только после этого фиксировать контракт `CSEMapEvent`, добавлять серверный classname и
клиентский HUD. В текущей итерации ни fork, ни exception, ни C++-реализация не принимаются.

## 12. Приложение: протокол стенда

### Подготовка

Стендовая карта называется `cse_test_actions`; её исходник создан в
`src/cse/maps/cse_test_actions.map`, а производный BSP уже собран и установлен локально в
`runtime/cstrike/maps/cse_test_actions.bsp`. Запуск — `server.cmd cse_test_actions`. Клиент B должен
использовать отдельный runtime-каталог или другую машину:
общий runtime не проверяет отсутствие файла у клиента.

Обычный `server.cmd` задаёт `BOT_QUOTA=9` и передаёт `+yb_quota 9`
(`server.cmd`, значения по умолчанию). Для `cse_lobby` предусмотрен отдельный
`server.cmd cse_lobby -nobots`, который не загружает YaPB. В тесте доставки явно
записать `sv_allowdownload`, `sv_downloadurl`, `cl_allowdownload` и `cl_download_ingame`.

### Конфигурация созданной карты

| Сущность | Настройка |
|---|---|
| `func_button btn_global` | target `mm_global`, `Don't move`, wait 3 |
| `multi_manager mm_global` | `txt1 0`, `snd1 0`, `door1 0.5`, `score1 1`, `heal1 1`; не более 16 целей |
| `game_text txt1` | `CSE TEST OK`, All Players `1`, channel 3, holdtime 5 |
| `ambient_generic snd1` | `buttons/button3.wav`, Play Everywhere `1`, Start Silent `16` |
| `func_door door1` | обычная Toggle-дверь |
| `game_score score1` | points 1 |
| `game_player_hurt heal1` | `dmg = -25`; активатору заранее оставить недостающее HP |
| `func_button btn_equip` | прямой target `eq1` |
| `game_player_equip eq1` | Use Only `1`, `weapon_ak47` |
| `trigger_multiple trg_global` | target `mm_global`, wait 5 |
| `cse_unknown_probe` | точечная неизвестная сущность без targets; не заменять ей brush-сущность |

### Результаты

| # | Проверяем | Критерий | Фактический результат |
|---|---|---|---|
| 1 | `game_text` для всех | текст виден A и B; без All Players — только активатору | не проверено: BSP собран и установлен, запуск не выполнялся |
| 2 | Звук | оба клиента слышат звук; записать влияние расстояния и Everywhere | не проверено: BSP собран и установлен, запуск не выполнялся |
| 3 | Репликация | дверь открывается у обоих без собственного user message | не проверено: BSP собран и установлен, запуск не выполнялся |
| 4 | Очки и HP | A получает +1 frag и +25 HP; B видит изменение фрага | не проверено: BSP собран и установлен, запуск не выполнялся |
| 5 | Оружие | AK-47 получает только нажавший | не проверено: BSP собран и установлен, запуск не выполнялся |
| 6 | Триггер и delay | `trigger_multiple` даёт ту же цепочку, wait подавляет повтор | не проверено: BSP собран и установлен, запуск не выполнялся |
| 7 | Неизвестный classname | лог `No spawn function ...`; точечная probe не ломает карту | не проверено: BSP собран и установлен, запуск не выполнялся |
| 8 | Конец раунда | зафиксировать reset состояния и delayed `multi_manager` после рестарта | не проверено: BSP собран и установлен, запуск не выполнялся |
| 9 | Доставка: карты нет | зафиксировать поведение при явных download cvars | не проверено: отдельный runtime не подготовлен |
| 10 | Доставка: BSP устарел | зафиксировать CRC-поведение | не проверено: отдельный runtime не подготовлен |
| 11 | Лог и ресурсы | `runtime/engine.log` без precache-ошибок; ресурсы перечислены | не проверено: запуск не выполнялся |

Результаты стенда будут дополнением к этому документу и не заменят статические ссылки на
исходники.
