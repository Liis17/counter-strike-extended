# План: исследование «свои действия на картах» (кнопки и триггеры, видимые всем)

Статус: план составлен, исследование не начато.
Ветка разработки: `claude/custom-map-actions-g3c568`.

## Зачем

Вопрос владельца проекта: возможно ли сделать на картах свои действия — нажатие кнопки или вход в
триггер, — чтобы произошло действие, и оно отобразилось **для всех** игроков на карте.

Согласованные с владельцем рамки:

| Вопрос | Решение |
|--------|---------|
| Способ задания действий | Правка `.bsp` в редакторе (Hammer / J.A.C.K.), не конфиг-патч поверх стоковых карт |
| Какие действия нужны | Штатные эффекты HL + свой HUD-эвент для всех + игровые действия (оружие/деньги/HP/очки) |
| Объём первой итерации | **Только исследование** — документ-ответ. Реализацию не делаем |

Тезис, который документ должен обосновать или опровергнуть **на исходниках**: да, возможно, и
бо́льшая часть — без единой строки C++, потому что сущности карты живут на сервере и их состояние
реплицируется всем клиентам штатно. Свой код нужен только там, где стоковых сущностей не хватает.

Итог итерации — один проверенный документ + заметка в базе знаний. Реализация — следующая итерация.

## Предусловие: инициализация submodules

Сейчас `src/xash3d-fwgs` и `src/cs16-client` — **пустые директории** (`git submodule status` печатает
`-` перед SHA). Без `git submodule update --init --recursive` проверить нечего, и документ выйдет
написанным по памяти. Это первый шаг.

Серверная логика — в ReGameDLL_CS, вложенном submodule внутри `src/cs16-client` (из него собирается
`dlls/mp.dll`, объявленный в `src/cse/cstrike/gameinfo.txt`). **Точный путь проверить**, а не
предполагать: `cat src/cs16-client/.gitmodules` + `grep -n "BUILD_SERVER\|regamedll" src/cs16-client/CMakeLists.txt`.
Дальше по тексту — `<REGAME>`.

## Что читать в исходниках

Документ пишется **только** по прочитанному коду. Порядок: A → B → C → D; после A уже можно писать
разделы про сток.

### A. Сущности ReGameDLL — ядро ответа

| Файл | Что подтвердить |
|------|-----------------|
| `<REGAME>/regamedll/dlls/maprules.cpp` | **Читать первым.** В HLSDK именно здесь `CGameText` (`game_text`), `game_score`, `game_player_equip`, `game_counter`, `game_team_master`, `game_end`. Для `game_text` — флаг «All Players» и его **числовое значение** (мапперу называть его в редакторе), поля `hudtextparms_t`, сколько каналов свободно. Для `game_player_equip` — флаг «Use Only», выдаётся ли активатору. Для `game_score` — кому идут очки |
| `<REGAME>/regamedll/dlls/buttons.cpp` | `CBaseButton`: `ButtonUse`, `ButtonTouch`, числовые spawnflags (Toggle, Don't move, Touch activates), `m_flWait`/`m_flDelay`, мастер |
| `<REGAME>/regamedll/dlls/triggers.cpp` | `CBaseTrigger::MultiTouch` → `ActivateMultiTrigger` (кто становится `pActivator`), `trigger_multiple`/`trigger_once`, `CTriggerRelay`, `CMultiManager` (**лимит `MAX_MULTI_TARGETS`**), `CTriggerTeleport` |
| `<REGAME>/regamedll/dlls/subs.cpp`, `cbase.h` | `SUB_UseTargets`/`FireTargets` — цепочка `pev->target` → `targetname`; `USE_TYPE`; `UTIL_IsMasterTriggered`; макрос `LINK_ENTITY_TO_CLASS` |
| `<REGAME>/regamedll/dlls/sound.cpp` | `CAmbientGeneric`: флаг «Play Everywhere» (числовое значение), «Start Silent», требование `PRECACHE_SOUND` |
| `<REGAME>/regamedll/dlls/effects.cpp` | `env_sprite`, `env_beam`, `env_shake`, `env_fade`; примеры `MESSAGE_BEGIN(MSG_PVS/MSG_BROADCAST, SVC_TEMPENTITY)` — это **второй канал «показать всем» без своего user message** |
| `<REGAME>/regamedll/dlls/util.cpp`, `util.h` | `UTIL_ShowMessageAll`, `UTIL_ScreenFadeAll`, `UTIL_ClientPrintAll`; допустимые dest у `MESSAGE_BEGIN` (`MSG_ALL`, `MSG_ONE`, `MSG_BROADCAST`, `MSG_PVS`, `MSG_INIT`) |
| `<REGAME>/regamedll/dlls/player.cpp` | Для «игровых действий»: `AddAccount` (деньги, кап `mp_maxmoney`), `GiveNamedItem`, `pev->health`/`armorvalue`, `pev->frags` — что из этого уже дёргается map-сущностями, а что только из кода |

**Открытые вопросы этого блока** (в документ идут как факты, не как ожидания):

1. **Какие `game_*` вообще есть в ReGameDLL.** В CS 1.6 часть HL-сущностей вырезана. Проверить
   наличие `LINK_ENTITY_TO_CLASS` для каждой. От этого прямо зависит, сколько «игровых действий»
   доступно без кода.
2. **Что происходит с неизвестным classname в `.bsp`.** Ожидание: сущность отбрасывается, карта
   грузится → карта со своими `cse_*` играбельна и на ванильном сервере, просто без эффекта.
   Проверить в `world.cpp` / `DispatchSpawn`.

### B. Не изобретаем ли велосипед

| Где | Что ищем |
|-----|----------|
| `src/xash3d-fwgs/engine/common/mod_bmodel.c` (grep `\.ent`, `entpatch`) | Поддерживает ли Xash3D FWGS подмену entity-лампы файлом `maps/<map>.ent`. Владелец выбрал правку `.bsp`, решение не пересматриваем — но факт фиксируем явно: это дешёвый способ прототипировать и текстовый артефакт, дружественный к git |
| `<REGAME>` grep `regamedll_api`, `ReAPI`, `Metamod`, `gpMetaGlobals` | Есть ли hook-API, позволяющий добавить поведение **без форка ядра**. Сервер уже грузится через `-dll dlls\yapb.dll` (`server.cmd:11`) — YaPB стоит первым и цепляет `mp.dll`; понять, как именно. Может целиком снять раздел «предусловие: форк» |

### C. Свой эвент: регистрация и передача

| Файл | Что подтвердить |
|------|-----------------|
| `<REGAME>/regamedll/dlls/client.cpp` | Список `REG_USER_MSG(...)` и **из какой функции** он вызывается (`LinkUserMessages()`) — сообщение обязано быть зарегистрировано до подключения клиентов |
| `<REGAME>/regamedll/dlls/game.cpp`/`.h` | Где объявлены `gmsg*`. Заодно выписать существующие `gmsgTextMsg`, `gmsgHudTextPro`, `gmsgShowMenu` — **возможно, своего сообщения не нужно вовсе** |
| `<REGAME>/regamedll/CMakeLists.txt` | Автоподхват новых `.cpp` или явный список? В `cl_dll` это glob (`cl_dll/CMakeLists.txt:6,10`), в ReGameDLL скорее список — влияет на трудоёмкость своей сущности |
| Реальный пример CS-сущности | `grep -rn "LINK_ENTITY_TO_CLASS" <REGAME>/regamedll/dlls`, взять `func_buyzone` / `info_map_parameters` / `hostage_entity` и прочитать связку `KeyValue()` → `Spawn()` → `Precache()` → `Use()` целиком. Это шаблон для `cse_event` |
| `src/cs16-client/cl_dll/hud.cpp` | Все `HOOK_MESSAGE(...)` — список занятых имён, чтобы `CseEvent` ни с чем не столкнулся |
| `cl_util.h:33`, `hud.h`, `hud/timer.cpp:41-139`, `hud_layout.cpp:72-191`, `cl_dll/CMakeLists.txt:6,10` | Уже разведано в [`player-progression-system.md`](player-progression-system.md) — **перепроверить только номера строк** и сослаться, не переписывая |
| YaPB-проксирование | Убедиться, что прослойка прозрачно пробрасывает `pfnRegUserMsg` — иначе своё сообщение до клиента не дойдёт |

### D. Лимиты

`src/xash3d-fwgs/engine/`: реальный потолок размера user message (ожидается ~192 байта) и поведение
при переполнении; `MAX_EDICTS`/`MAX_ENT_LEAFS`/`MAX_MODELS`/`MAX_SOUNDS` — сверить с `max_edicts 1800`
из `gameinfo.txt`; `sv_client.c` grep `downloadurl`, `allow_download`, `consistency`, `crc` — как
карта доезжает до игроков и что будет у клиента со старым `.bsp`.

## Структура документа

Путь: **`docs/research/custom-map-actions.md`** (новая папка; `docs/plans/` оставляем под планы).
Стиль — как у этого файла и [`player-progression-system.md`](player-progression-system.md):
русский, таблицы «Что | Где».

| # | Раздел | Содержимое |
|---|--------|-----------|
| 1 | Вопрос и краткий ответ | Вывод в 5 строках: да, три уровня, первые два без единой строки C++ |
| 2 | Зафиксированные решения | Таблица из раздела «Зачем» выше |
| 3 | Разведка: что проверено в коде | Таблицы «Что \| Где» с `file:line` по блокам A–D. Всё дальнейшее опирается только на неё |
| 4 | Как GoldSrc показывает «всем» | Три независимых канала: репликация состояния сущностей (дверь каждый видит сам), `MESSAGE_BEGIN` на всех клиентов (`game_text`, `TextMsg`), `SVC_TEMPENTITY`. Плюс почему `ambient_generic` слышат все |
| 5 | Уровень 1 — без кода | 5.1 активаторы (`func_button`, `trigger_multiple`/`once`, `trigger_relay`, `multi_manager`, мастер-сущности, задержки); 5.2 эффекты (`game_text` + флаг All Players — разбор параметров, `ambient_generic`, двери, спрайты, `env_shake`/`env_fade`, `trigger_teleport`); 5.3 игровые действия стоком (`game_player_equip`, `game_score`, `trigger_hurt`); **5.4 рецепты «хочу X → цепочка сущностей»**, 5–7 строк — то, что можно сделать в Hammer сегодня |
| 6 | Граница стока | Таблица «хочу \| стоком нельзя, потому что»: деньги, свой HUD-элемент, условия сложнее `multi_manager`, персональный vs общий эффект, состояние между раундами, занятые каналы `game_text` |
| 7 | Уровень 2 — свой C++ | Сквозная цепочка со схемой и файлом на каждый блок: сущность в `.bsp` → `LINK_ENTITY_TO_CLASS` + `KeyValue/Spawn/Precache/Use` в ReGameDLL → `MESSAGE_BEGIN(MSG_ALL, gmsgCseEvent)` → `REG_USER_MSG` в `LinkUserMessages` → `HOOK_MESSAGE_FUNC("CseEvent")` в `cl_dll` → HUD-элемент по образцу `cl_dll/hud/timer.cpp` → строка в `HudLayout.txt` + три реестра `tools/hud-editor/editor.js`. Плюс: почему деньги/HP обязаны быть на сервере, а отрисовка — только на клиенте |
| 8 | Предусловие: форк ReGameDLL_CS | `src/cs16-client/.gitmodules` → `Velaron/ReGameDLL_CS`, нужен `Liis17/ReGameDLL_CS` по прецеденту `mainui_cpp` (`Obsidian/.../CSE/menu.md`). Один форк закрывает и план прогрессии. **Раздел сокращается или исчезает, если блок B найдёт hook-API** |
| 9 | Альтернативы и почему не выбраны | `.ent`-override движка, ReAPI/Metamod-плагин, AMXX — по строке «что даёт / почему не подходит» |
| 10 | Тулчейн и путь карты до игроков | J.A.C.K. / Hammer 3.5, FGD для CS 1.6 (**сверить FGD со списком `LINK_ENTITY_TO_CLASS` этой сборки** — в стоковом FGD есть сущности, которых в ReGameDLL нет), WAD'ы, компиляторы VHLT. Далее: исходник `.map` в git → `.bsp` → `runtime/cstrike/maps/` (`tools/install_yapb_map_configs.ps1` уже умеет находить карты и в loose `.bsp`, и в `.pk3`/`.zip`) → `server.cmd <map>`; до клиента — `sv_downloadurl` / встроенная закачка, совпадение CRC, `.res` для спрайтов и звуков, отсутствие waypoint'ов YaPB на новой карте |
| 11 | Ограничения и риски | Лимит user message; `max_edicts 1800`; регистрация сообщений до коннекта; precache обязателен (звук/спрайт без него — краш); форк = ребейз с апстримом; на чужом сервере своё сообщение не придёт; модифицированная стоковая карта — производная от ассетов Valve, плюс `wadinclude` |
| 12 | Рекомендация и следующий шаг | Что делать первым; уровень 2 — отдельный план реализации в `docs/plans/` |
| 13 | Приложение: стенд-эксперимент | Раздел «Проверка» ниже целиком, с колонкой под фактический результат |

**Правило качества:** каждое утверждение разделов 4–7 сопровождается ссылкой `file:line` либо
строкой из эксперимента. Непроверенный пункт помечается явным «не проверено» и остаётся открытым
вопросом — «по памяти о HL SDK» в документ не идёт.

## Проверка

Утверждения делятся на два вида.

**Проверяемое чтением кода** — основная работа: ссылки `file:line` из проинициализированных
submodules на каждое утверждение.

**Проверяемое только запуском игры** — документ описывает эксперимент пошагово, владелец выполняет,
результат дописывается отдельным разделом (как в коммите «Record TeamBar verification results»).

Стенд-карта `cse_test_actions` — одна комната, старты за обе команды, и:

| Сущность | Настройка |
|----------|-----------|
| `func_button` | target `mm1`, флаг «Don't move», wait 3 |
| `multi_manager` `mm1` | `txt1 0`, `snd1 0`, `door1 0.5`, `score1 1` |
| `game_text` `txt1` | «CSE TEST OK», **флаг All Players**, channel 3, holdtime 5 |
| `ambient_generic` `snd1` | стоковый wav, флаги «Play Everywhere» + «Start Silent» |
| `func_door` `door1` | обычная дверь, Toggle |
| `game_score` `score1` | points 1 |
| `game_player_equip` `eq1` | флаг «Use Only», `weapon_ak47` — на второй кнопке |
| `trigger_multiple` | отдельная зона, target `mm1`, wait 5 |

Прогон: компиляция VHLT → `runtime/cstrike/maps/cse_test_actions.bsp`; `server.cmd cse_test_actions`
с **временным `BOT_QUOTA=0`** (у новой карты нет waypoint'ов YaPB, иначе лог зашумит); два клиента.

| # | Проверяем | Критерий |
|---|-----------|----------|
| 1 | «Для всех» через `game_text` | Текст виден **и на A, и на B**. Негативный контроль: снять флаг All Players, перекомпилировать → только на A |
| 2 | Звук для всех | Оба слышат wav независимо от расстояния |
| 3 | Репликация сущностей | Дверь открылась на **обоих** экранах — доказывает, что brush-сущностям сообщения не нужны вовсе |
| 4 | Очки | У A +1 frag в табло, видно и с B |
| 5 | Оружие | Вторая кнопка выдаёт AK-47 именно нажавшему, не всем |
| 6 | Триггер как активатор | Вход в `trigger_multiple` даёт тот же эффект; `wait` блокирует повторы |
| 7 | Лог чистый | `runtime/engine.log` без `unknown classname` / ошибок precache |
| 8 | Доставка карты | Клиент B **без** файла карты: зафиксировать фактическое поведение (закачка / отказ / CRC) — это ответ раздела 10, а не догадка |

Документ готов, когда: все 8 пунктов имеют записанный результат; в разделах 4–7 нет непроверенных
утверждений; раздел 3 состоит из реальных `file:line`; заметка в базе знаний создана и слинкована.

## Не входит в объём

- Форк `Liis17/ReGameDLL_CS` и перевод submodule — только описывается как предусловие.
- Любой C++: сущность `cse_event`, `gmsgCseEvent`, `MsgFunc_CseEvent`, новый HUD-элемент.
- Правки `tools/hud-editor/editor.js` и `src/cse/cstrike/scripts/HudLayout.txt`.
- `tools/install_maps.ps1` и шаг в `build-cse.cmd` — проектируются на бумаге, не пишутся.
- Готовая игровая карта, `.fgd`, геймплейный дизайн действий.
- Конфиг-патч сущностей поверх стоковых карт — владелец выбрал правку `.bsp`.

## Сводка по файлам

**Создать**
- `docs/research/custom-map-actions.md`
- `Obsidian/counter-strike-extendedVault/CSE/map-actions.md` — короткая заметка (10–20 строк): что
  возможно, три уровня, точки кода, ссылка на документ. Полный текст не дублируем

**Изменить**
- `Obsidian/counter-strike-extendedVault/Index.md` — строка в разделе «CSE»
- `Obsidian/counter-strike-extendedVault/Архитектура.md` — сейчас там нет ReGameDLL вообще; добавить,
  что серверный `mp.dll` собирается из него (факт нужен и плану прогрессии)
- `Obsidian/counter-strike-extendedVault/Client/HUD-TeamBar.md` (~строка 220) — устаревшее «серверный
  `mp.dll` проприетарный, правки невозможны». Одна строка, прямо противоречит выводам исследования.
  Если план прогрессии уже поправил — пропустить

## Риски

| Риск | Смягчение |
|------|-----------|
| Submodules пусты — соблазн писать по памяти о HL SDK | Правило качества: утверждение без `file:line` в документ не попадает |
| CS 1.6 вырезала часть `game_*` сущностей HL | Проверка `LINK_ENTITY_TO_CLASS` по каждой до написания раздела 5.3 |
| ReGameDLL — чужой репозиторий | Форк как предусловие уровня 2; блок B может показать, что форк не нужен |
| YaPB стоит перед `mp.dll` и может не пробросить `pfnRegUserMsg` | Явная проверка в блоке C до проектирования своего сообщения |
| Стоковый FGD не совпадает со сборкой | Сверка FGD со списком `LINK_ENTITY_TO_CLASS` (раздел 10) |
| Модифицированная стоковая карта — производная от ассетов Valve | Стенд-карта своя, с нуля; вопрос распространения зафиксирован в разделе 11 |
