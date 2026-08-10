# HUD layout (кастомизация позиций HUD)

Parent: [[Index]] | Domain: [[Client/cs16-client]]

## Назначение
Система пользовательской настройки позиций и масштаба элементов HUD (HP, броня, патроны, деньги,
таймер и др.) через внешний текстовый файл `scripts/HudLayout.txt`. Координаты — абсолютные, в
сырых пикселях; якорь (`anchor`) определяет, от какого края экрана отсчитываются значения.
Опциональный параметр `scale` растягивает цифры и иконки элемента. Без файла поведение
идентично ванильному CS 1.6.

Источник проектной настройки — `src/cse/cstrike/scripts/HudLayout.txt`. Скрипт
`tools/install_hud_layout.ps1` устанавливает его в `runtime/cstrike/scripts/`; этот шаг
также выполняется в конце `build-cse.cmd`.

Тот же файл содержит второй, необязательный блок `HudDecorations` — линии-разделители,
затемнения и панели-подложки под текст (см. [[#Декорации (необязательные элементы)]]). Оба блока
можно редактировать визуально через `tools/hud-editor` (см. [[Tooling/hud-editor]]). Редактор показывает
ориентировочные габариты реального HUD, включая правую точку привязки для патронов/денег и
эффективный `scale` только для поддерживаемых элементов.

## Точки кода

| Файл | Что |
|------|-----|
| `src/cs16-client/cl_dll/hud.h` | `enum HudAnchor` (9 значений, сетка 3×3), `enum HudDecorationType`, `struct HudDecoration`, `struct HudLayoutSlot`, поля `CHudBase::m_szLayoutId/m_iLayoutX/m_iLayoutY/m_eLayoutAnchor/m_bLayoutOverridden/m_flLayoutScale`, методы `GetLayoutPos()`, `GetLayoutScale()`, `CHud::LoadLayout()`, `CHud::GetLayoutSlot()`, `CHud::DrawDecorations()`, `CHud::m_LayoutDecorations`, `CHud::m_LayoutSlots`, `CHud::hud_layout_reload` |
| `src/cs16-client/cl_dll/hud_layout.cpp` | `ResolveAnchoredPos()` (общая anchor-математика, две независимые оси), `g_LayoutAnchorNames[]` + `Layout_ParseAnchor()` (таблица имён и алиасов), `g_LayoutSlotNames[]` + `Layout_IsSlotName()`, `CHudBase::GetLayoutPos()`, `CHud::GetLayoutSlot()`, `Decoration_ResolveTopLeft()`, парсер `CHud::LoadLayout()` (оба блока), `CHud::DrawDecorations()` |
| `src/cs16-client/cl_dll/hud.cpp` | Регистрация cvar `hud_layout_reload`, вызов `LoadLayout()` в конце `CHud::Init()` |
| `src/cs16-client/cl_dll/hud_redraw.cpp` | Проверка `hud_layout_reload` в `CHud::Think()`; вызов `DrawDecorations()` в начале `CHud::Redraw()`, перед циклом отрисовки HUD-элементов |
| `src/cs16-client/cl_dll/include/draw_util.h` + `draw_util.cpp` | `DrawUtils::SPR_DrawAdditiveScaled()` и `SPR_DrawHolesScaled()` — общий `SPR_DrawScaledMode()`, ручной textured quad через `pTriAPI` (`SpriteTexture`+`RenderMode`+`Begin/TexCoord/Vertex/End`; **не** через `pfnSPR_DrawGeneric`, см. «Известные грабли»); различаются только режимом (`kRenderTransAdd` / `kRenderTransAlpha`). Параметр `scale` у `DrawHudNumber*` |
| `src/cs16-client/extras/HudLayout.txt` | Образец файла с комментариями |
| `src/cse/cstrike/scripts/HudLayout.txt` | Текущая проектная настройка, устанавливаемая в runtime |
| `tools/install_hud_layout.ps1` | Идемпотентная установка файла в `runtime/cstrike/scripts/` |
| `tools/hud-editor/` | Визуальный веб-редактор: `index.html` + `editor.css` + `editor.js` (см. [[Tooling/hud-editor]]) |

## Как это работает

1. Каждый элемент в своём `Init()` вызывает `strlcpy(m_szLayoutId, "Name", sizeof(m_szLayoutId))`
   ДО `gHUD.AddHudElem(this)`.
2. После регистрации всех элементов `CHud::Init()` вызывает `LoadLayout()`, который читает
   `scripts/HudLayout.txt` (через `gEngfuncs.COM_LoadFile`), ищет записи по `m_szLayoutId`
   в `m_pHudList` и применяет `(x, y, anchor, scale)`, выставляя `m_bLayoutOverridden = true`.
3. В `Draw()` элемент вычисляет **дефолтную** позицию (как в ванилле) и вызывает:
   - `GetLayoutPos(x, y, defaultX, defaultY)` → если override есть, возвращает абсолютную
     позицию с учётом якоря; иначе `(defaultX, defaultY)`.
   - `GetLayoutScale()` (или `m_flLayoutScale` напрямую) → множитель размера, 1.0 по умолчанию.
4. Масштабирование спрайтов: `DrawUtils::SPR_DrawAdditiveScaled(spr, x, y, prc, destW, destH, r,g,b)`
   рисует ручной textured quad через `pTriAPI` (`SpriteTexture` + `RenderMode(kRenderTransAdd)` +
   `Begin(TRI_QUADS)`/`TexCoord2f`/`Vertex3f`/`End`), растягивая спрайт до произвольных `w,h`.
   Числа — через `DrawHudNumber*(... scale)`.
5. В рантайме: `hud_layout_reload 1` в консоли → `CHud::Think()` перечитывает файл и сбрасывает cvar.

### Известные грабли: блендинг при масштабировании спрайтов

Первая версия `SPR_DrawAdditiveScaled()` использовала движковый `pfnSPR_DrawGeneric()` — он рисует
через `R_DrawStretchPic()`, который **игнорирует** `pTriAPI->RenderMode()` (тот влияет только на
`TRI_`-геометрию) и чьи параметры `blendsrc/blenddst` — мёртвый код (`#if 0`) в этой сборке движка
(`engine/client/dll_int/cl_game.c`). Результат — спрайты рисовались непрозрачным квадом вместо
additive-прозрачных глифов. Исправлено переходом на ручной `pTriAPI`-quad (см. выше) — тот же
паттерн, что уже использовался в `CBaseParticle.cpp`/`hud_spectator.cpp`.

## Поддерживаемые элементы

| ID | Файл Draw | Что задаёт layout | Scale |
|----|-----------|-------------------|-------|
Отсутствие записи в файле — значимое состояние: элемент рисуется по своему дефолту. Для части
элементов дефолт вычисляется в рантайме и константой не выражается (столбец «Дефолт»), поэтому
редактор по умолчанию их не пишет — см. [[Tooling/hud-editor]].

| `Health` | `cl_dll/health.cpp` | позиция иконки cross + числа HP | да — растяг cross + цифр |
| `Battery` | `cl_dll/battery.cpp` | позиция иконки брони + числа | да |
| `Ammo` | `cl_dll/ammo.cpp` | правый край блока патронов + базовая Y | да — цифры, bar, ammo-иконка |
| `AmmoSecondary` | `cl_dll/ammo_secondary.cpp` | правый край + Y для вторичного боезапаса | нет (пока) |
| `Money` | `cl_dll/hud/money.cpp` | правый край блока денег + Y | да — dollar, plus/minus, число |
| `Timer` | `cl_dll/hud/timer.cpp` | позиция левого верхнего угла таймера | да — stopwatch + цифры + colon |
| `Flashlight` | `cl_dll/flashlight.cpp` | правый край + Y фонарика | нет (пока) |
| `DeathNotice` | `cl_dll/death.cpp` | правый край + Y верхней строки killfeed | нет (текст через консольный шрифт) |
| `StatusBar` | `cl_dll/statusbar.cpp` | базовый отступ слева + отступ снизу | нет (текст через консольный шрифт) |
| `TeamBar` | `cl_dll/hud/teambar.cpp` | **центр** блока счёта по X + верх ленты по Y (единственный центрированный элемент) | да — слоты, зазоры и цифры счёта |
| `Radar` | `cl_dll/hud/radar.cpp` | левый верхний угол коробки радара; точки и текст локации следуют за ней | да — спрайт, радиус и маркеры |
| `WeaponMenu` | `cl_dll/ammo.cpp` (`DrawWList`) | левый верхний угол блока выбора оружия. **Слот**, не элемент | да — bucket'ы, картинки оружия, рамка выбора, ammo bar, зазоры |
| `StatusIcons` | `cl_dll/status_icons.cpp` | **низ** колонки иконок (стек растёт вверх) | нет |
| `Scenario` | `cl_dll/hud/scenario.cpp` | позиция иконки сценария (бомба/заложники) | нет |
| `AmmoHistory` | `cl_dll/ammohistory.cpp` | **правый нижний угол** истории подбора (стек растёт вверх). **Слот**, не элемент | нет |
| `ProgressBar` | `cl_dll/hud/timer.cpp` (`CHudProgressBar`) | левый верхний угол полосы; с заголовком — угол текста, полоса строкой ниже | нет |
| `SayText` | `cl_dll/saytext.cpp` | левый верхний угол первой строки чата | нет (консольный шрифт) |
| `Train` | `cl_dll/train.cpp` | позиция панели управления вагонеткой | нет |

### Дефолты, которые нельзя записать в файл

| ID | Почему |
|----|--------|
| `WeaponMenu` | `m_Radar.m_hRadar.rect.right + 10` — зависит от спрайта радара и разрешения |
| `Scenario` | `gHUD.m_Timer.m_right` — фактический правый край таймера, известен только после его отрисовки в этом кадре |
| `ProgressBar` | `ScreenWidth/4`, `ScreenHeight*2/3` — доли экрана, которых нет в сетке якорей |
| `SayText` | `Y_START` пересчитывается на каждое сообщение из `line_height` и режима наблюдателя |
| `Train` | `ScreenWidth/3` — доля экрана |

Остальные элементы дефолт выражают якорем точно: `Radar` → `0 0 top_left`,
`StatusIcons` → `5 0 center_left`, `AmmoHistory` → `0 0 bottom_right`.

## Слоты (`HudLayoutSlot`)

`m_szLayoutId` — поле `CHudBase`, поэтому виджет, не являющийся зарегистрированным элементом, его
не имеет. Таких два: меню выбора оружия рисует `CHudAmmo::DrawWList()` (id этого элемента уже занят
значением `"Ammo"`), а история подбора — `HistoryResource gHR`, вообще не наследник `CHudBase`.

Записи, чей id входит в белый список `g_LayoutSlotNames[]` (`hud_layout.cpp`), попадают в
`CHud::m_LayoutSlots` и читаются через
`CHud::GetLayoutSlot( name, x, y, defaultX, defaultY, scale = NULL )`. Id вне белого списка
по-прежнему даёт `Con_DPrintf` — иначе опечатка в имени элемента молча превращалась бы в слот,
который никто не читает. Параметр `scale` — необязательный указатель: у немасштабируемых слотов
он не передаётся.

## Не поддерживается (отложено)

- **SayText / StatusBar / DeathNotice scale** — эти элементы рисуются через консольный шрифт
  движка (`pfnDrawConsoleString`), у которого нет API масштабирования. Потребуется переход на
  quad-рендеринг шрифта, что выходит за рамки текущей итерации.

## Формат `HudLayout.txt`

```
// Editor preview resolution: 2560x1440 (game uses its current screen resolution).
// EditorGroups: [{"name":"HP-блок","members":["el:Health","el:Battery","dec:1"]}]
"HudLayout"
{
    "Health"        "10"   "40"  "bottom_left"   "1.5"
    "Battery"       "120"  "40"  "bottom_left"   "1.5"
    "Ammo"          "20"   "40"  "bottom_right"  "1.5"
    "Money"         "20"   "75"  "bottom_right"  "1.3"
    "Timer"         "0"    "35"  "center"        "1.3"
}

"HudDecorations"
{
    "Shade" "0"  "0"  "top_left" "1920" "36" "0"  "0"  "0"  "140" "0"
    "Line"  "10" "40" "top_left" "300"  "2"  "255" "140" "0" "255" "0"
    "Panel" "10" "50" "top_left" "220"  "70" "20" "20" "20" "200" "12"
}
```

Каждая запись `HudLayout` = 4 обязательных токена + 1 опциональный: `"id" "x" "y" "anchor" ["scale"]`.
Scale — float, по умолчанию 1.0 (1.5 = +50% к размеру, 0.75 = −25%). Комментарии вне
`"HudLayout { ... }"` не поддерживаются (используйте закомментированные строки-образцы в файле —
они просто не матчатся с id элементов).

Комментарии-метаданные редактора (`COM_ParseFile` пропускает `//`, игра их не видит):

| Комментарий | Что хранит |
|-------------|-----------|
| `// Editor preview resolution: WxH` | Размер холста для повторного открытия в редакторе |
| `// EditorGroups: [...]` | Именованные группы элементов (одна строка JSON). Элементы — `el:<Id>`, декорации — `dec:<индекс в блоке HudDecorations>`; индекс маппится в рантайм-uid при загрузке. Битый JSON и несуществующие члены молча отбрасываются |

### Якоря

Полная сетка 3×3, имя читается «вертикаль_горизонталь», одиночное `center` = центр по обеим осям:

| | left | center | right |
|-|------|--------|-------|
| **top** | `top_left` | `top_center` | `top_right` |
| **center** | `center_left` | `center` | `center_right` |
| **bottom** | `bottom_left` | `bottom_center` | `bottom_right` |

Оси резолвятся независимо (`ResolveAnchoredPos()` — два отдельных `switch`): по каждой оси
значение это либо отсчёт от края (`…_left` / `top…`), либо отступ от противоположного края
(`…_right` / `bottom…`), либо знаковое смещение от центра (`…_center` / `center…`). Привязка к
центральной половине держит элемент у своей части экрана на любом разрешении — в отличие от
`center` с большим смещением, которое «уезжает» при смене разрешения.

`Layout_ParseAnchor()` дополнительно принимает алиасы: написание без подчёркивания
(`topright`, `bottomleft`, …) и обратный порядок `center_top` / `center_bottom` / `left_center` /
`right_center`. Неизвестное имя → `top_left`.

Блок `HudDecorations` необязателен (если его нет в файле — декораций просто нет). Каждая запись —
фиксированные 11 токенов: `"Type" "x" "y" "anchor" "w" "h" "r" "g" "b" "a" "radius"`. `radius`
игнорируется для `Line`/`Shade`, используется только `Panel`.

## Декорации (необязательные элементы)

В отличие от 9 обязательных HUD-элементов, декорации — произвольный список, не привязанный ни к
каким `CHudBase`. Хранятся в `CHud::m_LayoutDecorations` (`CUtlVector<HudDecoration>`), рисуются
`CHud::DrawDecorations()`, вызываемым в начале `CHud::Redraw()` **до** цикла по
`HUDLIST`/`CHudBase::Draw()` — поэтому декорации всегда оказываются под текстом и иконками любого
HUD-элемента (порядок отрисовки = порядок в файле, никакого отдельного z-поля нет).

| Type | Рендер | Назначение |
|------|--------|------------|
| `Line` | один `FillRGBABlend(x,y,w,h,r,g,b,a)` | тонкий прямоугольник-разделитель (тонкая `w` или `h` — выбор пользователя, отдельного поля ориентации нет) |
| `Shade` | один `FillRGBABlend(x,y,w,h,r,g,b,a)` | полупрозрачный блок затемнения |
| `Panel` | средняя полоса на всю ширину + `radius` строк сверху/снизу с инсетом по формуле окружности (`inset = radius - floor(sqrt(radius² - dy²))`) | подложка под текст со скруглёнными (пиксельный срез) углами |

`Panel` **не** использует TriAPI — только построчные `FillRGBABlend`, чтобы не наступить на грабли
с блендингом, описанные выше для `SPR_DrawAdditiveScaled`. `x/y/anchor` резолвятся той же
anchor-математикой, что и HUD-элементы (`ResolveAnchoredPos()` в `hud_layout.cpp`, общая для
`CHudBase::GetLayoutPos()` и `Decoration_ResolveTopLeft()`); прямоугольник всегда растёт вправо/вниз
от резолвнутой точки, независимо от якоря.

## Ограничения

- Координаты — в **сырых пикселях** экрана (не масштабируются под разрешение). На разных
  разрешениях лейаут выглядит по-разному — это сознательный выбор. Scale, напротив, применяется
  к размеру элемента, а не к координате. Смягчить это можно выбором якоря: элемент, привязанный
  к `top_center`/`bottom_center`/`center_*` с небольшим смещением, остаётся у своей части экрана
  при смене разрешения.
- Якорь задаёт только точку привязки, но **не** центрирует блок по его ширине: у `top_center`
  с `x = 0` элемент начинается от центра и растёт вправо (для right-aligned элементов — влево).
  Чтобы визуально отцентрировать блок, задайте `x = -w/2`; это константа, от разрешения она не
  зависит. То же касается декораций (`Decoration_ResolveTopLeft()` не зеркалит по w/h).
- В редакторе выбирайте фактическое разрешение игрового окна (`ScreenWidth × ScreenHeight`),
  иначе якоря и декорации будут визуально смещены. Для текущего `runtime/cstrike/video.cfg`
  используется пресет `2560×1440`; выбранный размер сохраняется в комментарии файла.
  См. [[Tooling/hud-editor]].
- Для right-aligned элементов (`Ammo`, `Money`, `Flashlight`, `DeathNotice`) семантика `x` =
  «правый край блока», поэтому естественны якоря с горизонталью `right`. Иные якоря работают, но
  блок будет расти влево от точки привязки.
- HP и броня исторически на одной `y` и разнесены по `x` вручную. При свободном позиционировании
  возможно наложение — ответственность пользователя через `HudLayout.txt`.
- Scale применяется только к элементам, у которых он реализован (Health, Battery, Ammo, Money,
  Timer, TeamBar, Radar, WeaponMenu). SayText/StatusBar/DeathNotice используют консольный шрифт
  движка без API масштабирования.
- `Radar` живёт в двух системах координат: `FillRGBA` — движковый `pfnFillRGBA`, принимает
  HUD-координаты (пространство `ScreenWidth`), а `Draw2DQuad` — реальные пиксели, поэтому
  `DrawColoredTexture()` домножает на `gHUD.m_flScale`. Смещение из layout прибавляется **до**
  этого умножения (`BlipX()`/`BlipY()` в `radar.cpp` — единственное место конвертации). Ничего
  производного от layout не кэшируется в `VidInit()`: `hud_layout_reload` перезапускает
  `LoadLayout()` без `VidInit()`.
- Превью стековых элементов (`StatusIcons`, `AmmoHistory`, `TeamBar`, `WeaponMenu`, `SayText`)
  показывает представительный случай: реальная высота зависит от числа активных записей.
- Очень маленький scale (например 0.1) может дать артефакты из-за целочисленного округления.

## Связанные cvar'ы
- `hud_layout_reload` — set to 1 для перечитывания `scripts/HudLayout.txt` в рантайме.
