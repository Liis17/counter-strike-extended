# План: остальные элементы HUD в редакторе и в игре

Статус: этапы 0–6 реализованы. Автоматические проверки (сборка, round-trip редактора) пройдены;
визуальная проверка в игре выполнена частично — см. «Что осталось непроверенным» в конце.

## Зачем

Сейчас система кастомного layout покрывает 10 элементов: `Health`, `Battery`, `Ammo`,
`AmmoSecondary`, `Money`, `Timer`, `Flashlight`, `DeathNotice`, `StatusBar`, `TeamBar`
(`src/cs16-client/cl_dll/hud_layout.cpp`, `tools/hud-editor/editor.js:3`). Остальные виджеты
нарисованы по жёстко зашитым координатам и не двигаются ни из редактора, ни из
`scripts/HudLayout.txt`.

Задача: довести покрытие до восьми оставшихся элементов и в игре, и в редакторе.

| Элемент | Где рисуется сейчас | Текущая позиция |
|---------|--------------------|-----------------|
| `Radar` | `cl_dll/hud/radar.cpp:281` | `0, 0` жёстко, спрайт 128×128 (640-res, `sprites/hud.txt`) |
| `WeaponMenu` | `cl_dll/ammo.cpp:1950` (`CHudAmmo::DrawWList`) | `x = m_Radar.m_hRadar.rect.right + 10`, `y = 10` |
| `StatusIcons` | `cl_dll/status_icons.cpp:52` | `x = 5`, `y = ScreenHeight / 2`, ряд растёт **вверх** |
| `Scenario` | `cl_dll/hud/scenario.cpp:59` | `x = gHUD.m_Timer.m_right + m_iFontWidth * 1.5` |
| `AmmoHistory` | `cl_dll/ammohistory.cpp:110` (`HistoryResource`) | `ScreenWidth - 24`, снизу вверх |
| `ProgressBar` | `cl_dll/hud/timer.cpp:183` | `ScreenWidth/4`, `ScreenHeight*2/3` (или `/2` с заголовком) |
| `SayText` | `cl_dll/saytext.cpp:117` | `LINE_START = 10`, `Y_START` считается в `SayTextPrint` |
| `Train` | `cl_dll/train.cpp:46` | `ScreenWidth/3 + SPR_Width/4`, снизу |

Вне области: `NVG`, `SniperScope`, `MOTD`, `Scoreboard`, `SpectatorGui`, `Menu`, прицел —
полноэкранные или жёстко центрированные, позиционировать нечего.

## Две вещи, которые определяют форму решения

### 1. Slot-таблица для того, что не является `CHudBase`

`LoadLayout()` матчит id по списку зарегистрированных элементов (`hud_layout.cpp:227`), а
`m_szLayoutId` — поле `CHudBase`. Двум элементам из набора этот путь закрыт:

- `DrawWList` — метод `CHudAmmo`, у которого id уже занят значением `"Ammo"` (`ammo.cpp:249`);
- `HistoryResource gHR` вообще не наследует `CHudBase` (`ammohistory.h:151`).

Решение: таблица именованных слотов в `CHud` по образцу `m_LayoutDecorations` — запись
`{ name, x, y, anchor, scale }`. В `LoadLayout()` ветка `if( !elem )` (`hud_layout.cpp:233`) вместо
безусловного `Con_DPrintf` кладёт запись в таблицу, если имя входит в статический белый список
допустимых слотов; иначе — прежняя диагностика (иначе опечатка в id молча станет слотом).
Читатель: `bool CHud::GetLayoutSlot( const char *name, int &x, int &y, float &scale, int defX, int defY )`.
`Purge()` слотов — рядом с `m_LayoutDecorations.Purge()` (`hud_layout.cpp:144`).

### 2. Opt-out в редакторе — обязателен, иначе ломаются вычисляемые дефолты

`serializeHudLayout` (`editor.js:391`) пишет **все** `ELEMENT_IDS` безусловно. Значит любой новый id
всегда получает запись → `m_bLayoutOverridden = true` → его vanilla-дефолт становится мёртвым кодом.
Для части элементов дефолт константой не выражается:

| Элемент | Дефолт выражается якорем? |
|---------|--------------------------|
| `Radar` | Да — `0,0` = `top_left` |
| `StatusIcons` | Да — `5, ScreenHeight/2` = `center_left` |
| `Train`, `AmmoHistory`, `ProgressBar` | Да, с точностью до размера спрайта |
| `WeaponMenu` | **Нет** — зависит от ширины спрайта радара и разрешения |
| `Scenario` | **Нет** — цепляется за фактический правый край `Timer` (`m_Timer.m_right`) |
| `SayText` | **Нет** — `Y_START` зависит от `line_height` и от `g_iUser1` (режим наблюдателя) |

Решение: у каждого элемента в редакторе — флаг «переопределять». Снят → id **не пишется** в файл, и
в игре работает существующее поведение (отсутствие записи = уже реализованный контракт, кода не
требует). При парсинге: id присутствует → флаг взведён, отсутствует → снят. Формат файла не меняется,
наличие записи **и есть** состояние флага.

Для новых элементов флаг по умолчанию снят, для десяти существующих — взведён (они уже в файле).

**Побочный эффект, принят осознанно.** Правило «отсутствует id → флаг снят» действует и на десять
существующих элементов. Сейчас файл без, например, `TeamBar` открывается со значением из
`DEFAULT_ELEMENTS` и при сохранении запись появляется; после правки id останется отсутствующим, и в
игре элемент будет рисоваться по хардкоду. Выбран именно честный round-trip: редактор перестаёт
дописывать в файл то, чего пользователь туда не клал. Значения из `DEFAULT_ELEMENTS` продолжают
служить стартовой точкой полей ввода при взведении флага.

Отвергнуто: настоящее «скрыть элемент» через формат файла — вне запроса. `hidden` в редакторе
остаётся тем, чем является сейчас, — свойством превью.

### 3. Грабли радара (проявятся только на целевом разрешении)

- **Две системы координат.** `DrawColoredTexture` (`radar.cpp:418`) умножает на `gHUD.m_flScale`, а
  `FillRGBA`-ветки в `DrawRadarDot`/`DrawCross`/`DrawT`/`DrawFlippedT` — нет: `FillRGBA` это прямой
  вызов движка `pfnFillRGBA` (`cl_util.h:63`), клиент масштаб к нему не применяет. Смещение от layout
  прибавлять **до** умножения на `m_flScale` в TriAPI-ветке и без умножения в `FillRGBA`-ветке; это
  вывод из определений, проверить на первом же запуске. Иначе точки разъедутся ровно при
  `m_flScale != 1`, то есть на 2560×1440.
- **`iMaxRadius` кэшируется в `VidInit`** (`radar.cpp:192`), а `hud_layout_reload` (`hud.cpp:360`,
  `hud_redraw.cpp:53`) перезапускает только `LoadLayout()`, без `VidInit()`. Масштабированный радиус
  считать в `Draw()` каждый кадр, в `VidInit` не запекать.
- **`cl_radartype 1` рисуется через `SPR_DrawHoles`** (`radar.cpp:295`), а scaled-хелпер в
  `draw_util.h:63` есть только для additive. Нужен `SPR_DrawHolesScaled` — копия
  `SPR_DrawAdditiveScaled` (`draw_util.cpp:400`) с `kRenderTransAlpha` вместо `kRenderTransAdd`.
- **`m_hRadar.spr` рисуется с `&m_hRadarOpaque.rect`** (`radar.cpp:300`) — существующее расхождение
  апстрима. Не правим (правило «хирургические правки»); для расчёта footprint и scale берём
  `m_hRadarOpaque.rect` — тот, что уже используется обеими ветками.
- `DrawPlayerLocation` (`radar.cpp:388`) завязан на `m_hRadarOpaque.rect.Height()` — смещать и
  масштабировать вместе с радаром.

### 4. Элементы, растущие вверх

`ELEMENT_PREVIEWS` в редакторе умеет `align: right|center` и `originY`, но не умеет «растёт вверх».
`StatusIcons` (`y -= h + 5` до отрисовки) и `AmmoHistory` (`ScreenHeight - (PICK_HEIGHT + GAP*i)`)
рисуют выше точки привязки. Их превью задавать через `originY: -height`, иначе привязка и
выравнивание в редакторе будут врать.

Высота стека у обоих зависит от числа активных записей (`N * (h + 5)`), а превью фиксированное —
как у `TeamBar`, чьё превью не отражает вторую строку и двузначный счёт (`editor.js:46`). Это
ограничение фиксируем комментарием рядом с записью, точным превью не занимаемся.

## Этапы

Каждый этап — игровая сторона + запись в редакторе + shipped-дефолт в одном коммите, иначе этап нечем
проверить. Коммит после каждого этапа, push не делаем.

Цикл проверки: правка кода → пересборка клиента (`cmake --build build` + `cmake --install`), затем
правка layout → `hud_layout_reload 1` в консоли без перезапуска.

Игра читает `runtime/cstrike/scripts/HudLayout.txt`, а репозиторный источник —
`src/cse/cstrike/scripts/HudLayout.txt`; между ними `tools/install_hud_layout.ps1`, который
`build-cse.cmd:49` уже вызывает. Итерации подбора координат ведём прямо в `runtime/` (быстрый цикл
«правка + `hud_layout_reload 1`»), по завершении этапа результат переносим в `src/cse/` и один раз
прогоняем `install_hud_layout.ps1`, чтобы убедиться в совпадении.

```
0. Инфраструктура      → проверка: сборка чистая, поведение HUD не изменилось
1. Radar               → проверка: двигается и масштабируется в обоих cl_radartype, точки не разъезжаются
2. WeaponMenu          → проверка: без записи — как сейчас; с записью — двигается и масштабируется
3. StatusIcons + Scenario → проверка: иконки на месте, Scenario без записи по-прежнему держится Timer
4. AmmoHistory + ProgressBar → проверка: история растёт вверх от точки, полоса на месте
5. SayText + Train     → проверка: чат не съезжает при смене числа строк
6. Obsidian            → проверка: заметки описывают фактический код
```

### Этап 0 — инфраструктура

| Файл | Изменение |
|------|-----------|
| `cl_dll/hud.h` | Структура `HudLayoutSlot`, поле `m_LayoutSlots`, объявление `GetLayoutSlot` |
| `cl_dll/hud_layout.cpp` | Белый список имён слотов; ветка `if( !elem )` пишет в таблицу; `Purge()`; реализация `GetLayoutSlot` |
| `cl_dll/include/draw_util.h`, `cl_dll/draw_util.cpp` | `SPR_DrawHolesScaled` |
| `tools/hud-editor/editor.js` | Флаг `override` в модели элемента; `serializeHudLayout` пропускает элементы со снятым флагом; `parseHudLayout` взводит флаг по факту наличия id |
| `tools/hud-editor/index.html`, `editor.css` | Чекбокс «переопределять» в строке элемента |

Проверка, два шага:
1. Открыть и сохранить существующий `HudLayout.txt` — набор и порядок записей не изменились.
2. В копии файла удалить один id (например `TeamBar`), открыть, сохранить — id остался отсутствующим,
   редактор его не дописал.

### Этап 1 — Radar

| Файл | Изменение |
|------|-----------|
| `cl_dll/hud/radar.cpp` | `m_szLayoutId = "Radar"` в `Init()` **перед** `AddHudElem` (`radar.cpp:97`; контракт `hud.h:170`); в начале `Draw()` — `GetLayoutPos` (дефолт `0,0`) и `GetLayoutScale()`; смещение и масштаб в поля, читаемые пятью хелперами; scaled-отрисовка обоих спрайтов; `DrawPlayerLocation` следует за радаром |
| `cl_dll/include/hud/radar.h` | Поля смещения/масштаба, объявления не меняются по сигнатурам |
| `tools/hud-editor/editor.js` | `Radar` в трёх местах: `ELEMENT_IDS`, `ELEMENT_PREVIEWS` (128×128, `scalable: true`), `DEFAULT_ELEMENTS` (`0,0,top_left,1`) |
| `src/cse/cstrike/scripts/HudLayout.txt` | Дописать `Radar` (не трогая существующие пользовательские значения) |

Проверка: `cl_radartype 0` и `1` — во втором случае спрайт не должен превратиться в чёрный квадрат
(режим блендинга в `SPR_DrawHolesScaled` подобран по аналогии, а не взят из кода); scale 1 и 2;
точки игроков остаются внутри круга при `m_flScale != 1` (родное разрешение 2560×1440).

### Этап 2 — WeaponMenu

| Файл | Изменение |
|------|-----------|
| `cl_dll/ammo.cpp` | В `DrawWList` — `gHUD.GetLayoutSlot("WeaponMenu", ...)` с текущим выражением как дефолтом; под scale: спрайты bucket'ов, `p->rcActive`/`rcInactive`, `m_HUD_selection`, `giBucketWidth`/`Height`, `giABWidth`/`Height`, отступы `+5`, `DrawAmmoBar` |
| `tools/hud-editor/editor.js` | `WeaponMenu`, превью ≈300×280 (6 слотов × 25 px + расширенная активная колонка 170 px, высота 20 + 5×50), `scalable: true`, флаг `override` по умолчанию снят |

Проверка: без записи в файле меню рисуется точно как сейчас; с записью — двигается и масштабируется,
рамка выбора совпадает со спрайтом оружия.

### Этап 3 — StatusIcons + Scenario

| Файл | Изменение |
|------|-----------|
| `cl_dll/status_icons.cpp` | `m_szLayoutId = "StatusIcons"`; `GetLayoutPos(x, y, 5, ScreenHeight / 2)` |
| `cl_dll/hud/scenario.cpp` | `m_szLayoutId = "Scenario"`; `GetLayoutPos` с текущим выражением как дефолтом |
| `tools/hud-editor/editor.js` | `StatusIcons` (`originY: -height`, `center_left`), `Scenario`; у `Scenario` флаг снят по умолчанию |

### Этап 4 — AmmoHistory + ProgressBar

| Файл | Изменение |
|------|-----------|
| `cl_dll/ammohistory.cpp` | `gHUD.GetLayoutSlot("AmmoHistory", ...)`. Точка слота — **правый нижний угол**, дефолт `(ScreenWidth, ScreenHeight)`. Все существующие смещения остаются пер-ветковыми: `- 24`, `- weap->rcInactive.Width()`, `- rect.Width() - 10` по x и `- (AMMO_PICKUP_PICK_HEIGHT + AMMO_PICKUP_GAP * i)` по y |
| `cl_dll/hud/timer.cpp` | `CHudProgressBar`: `m_szLayoutId = "ProgressBar"`. Точка layout = левый верхний угол полосы для варианта без заголовка; для варианта с заголовком — левый верхний угол текста, полоса под ним. Ширина остаётся `ScreenWidth/2` |
| `tools/hud-editor/editor.js` | Две записи; у `AmmoHistory` — `originY: -height` и `align: "right"`; превью `ProgressBar` отражает вариант без заголовка |

Единого дефолта для `xpos`, воспроизводящего все три ветки `HISTSLOT_*`, не существует — они
используют разные выражения (`ammohistory.cpp:135`, `:162`, `:180`). Поэтому дефолт задаётся как край
экрана, а не как «текущее выражение»; при отсутствии записи получается побитово прежнее поведение.

Проверка: подобрать патроны — иконки растут вверх от точки; подобрать оружие и предмет — все три типа
записи истории выровнены по одному правому краю; заложить бомбу — полоса на месте.

### Этап 5 — SayText + Train

| Файл | Изменение |
|------|-----------|
| `cl_dll/saytext.cpp` | `m_szLayoutId = "SayText"`; в `Draw()` начальные `x`/`y` через `GetLayoutPos` с дефолтом `LINE_START` / `Y_START`. `Y_START` остаётся вычисляемым для случая без переопределения |
| `cl_dll/train.cpp` | `m_szLayoutId = "Train"`; `GetLayoutPos` с текущим выражением как дефолтом |
| `tools/hud-editor/editor.js` | Две записи; у `SayText` флаг снят по умолчанию |

Проверка: чат при переопределении не съезжает от числа занятых строк; в режиме наблюдателя без
переопределения работает прежняя логика `g_iUser1`.

### Этап 6 — Obsidian

| Заметка | Что обновить |
|---------|--------------|
| `Client/HUD-layout.md` | Таблица id: восемь новых записей; раздел про slot-таблицу и про то, что отсутствие id = vanilla-дефолт |
| `Tooling/hud-editor.md` | Флаг «переопределять», новые элементы, ограничения превью |
| `Tooling/Tools.md`, `Index.md` | Ссылки, если появились новые файлы |

## Замечания по существующему коду

- Комментарий у `DEFAULT_ELEMENTS` (`editor.js:53`) «Matches the shipped
  runtime/cstrike/scripts/HudLayout.txt defaults» уже неточен: в `src/cse/.../HudLayout.txt` лежат
  пользовательские значения (`Health "-424" "25" "bottom_center"`). Правим только если этап 0 всё
  равно трогает соседние строки.
- Расхождение `m_hRadar.spr` + `m_hRadarOpaque.rect` (`radar.cpp:300`) — апстрим, не наш. Оставляем.

## Что осталось непроверенным

Автоматически проверено: сборка клиента без предупреждений на каждом этапе; в редакторе —
round-trip файла (набор и порядок записей не меняются), удалённый вручную id остаётся удалённым,
совпадение anchor-математики с `ResolveAnchoredPos()`, наличие каждого id во всех трёх таблицах.

В игре подтверждено, что HUD с новым `HudLayout.txt` рисуется (декорации и `StatusIcons` на месте).
Не проверено визуально:

| Что | Почему |
|-----|--------|
| `cl_radartype 1` со `scale != 1` | Режим блендинга в `SPR_DrawHolesScaled` выбран по аналогии с `SPR_DrawHoles`, а не взят из кода движка. При `scale = 1` ветка не задействуется |
| Меню оружия со `scale != 1` | Требует живой сессии с набором оружия в разных слотах |
| Точки радара при `scale != 1` на `FillRGBA`-ветке | Ветка активна только без renderAPI (`g_iXash == 0`) |
