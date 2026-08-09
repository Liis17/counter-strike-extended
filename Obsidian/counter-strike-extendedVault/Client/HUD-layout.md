# HUD layout (кастомизация позиций HUD)

Parent: [[Index]] | Domain: [[Client/cs16-client]]

## Назначение
Система пользовательской настройки позиций и масштаба элементов HUD (HP, броня, патроны, деньги,
таймер и др.) через внешний текстовый файл `scripts/HudLayout.txt`. Координаты — абсолютные, в
сырых пикселях; якорь (`anchor`) определяет, от какого края экрана отсчитываются значения.
Опциональный параметр `scale` растягивает цифры и иконки элемента. Без файла поведение
идентично ванильному CS 1.6.

Тот же файл содержит второй, необязательный блок `HudDecorations` — линии-разделители,
затемнения и панели-подложки под текст (см. [[#Декорации (необязательные элементы)]]). Оба блока
можно редактировать визуально через `tools/hud-editor` (см. [[Tooling/Tools]]).

## Точки кода

| Файл | Что |
|------|-----|
| `src/cs16-client/cl_dll/hud.h` | `enum HudAnchor`, `enum HudDecorationType`, `struct HudDecoration`, поля `CHudBase::m_szLayoutId/m_iLayoutX/m_iLayoutY/m_eLayoutAnchor/m_bLayoutOverridden/m_flLayoutScale`, методы `GetLayoutPos()`, `GetLayoutScale()`, `CHud::LoadLayout()`, `CHud::DrawDecorations()`, `CHud::m_LayoutDecorations`, `CHud::hud_layout_reload` |
| `src/cs16-client/cl_dll/hud_layout.cpp` | `ResolveAnchoredPos()` (общая anchor-математика), `CHudBase::GetLayoutPos()`, `Decoration_ResolveTopLeft()`, парсер `CHud::LoadLayout()` (оба блока), `CHud::DrawDecorations()` |
| `src/cs16-client/cl_dll/hud.cpp` | Регистрация cvar `hud_layout_reload`, вызов `LoadLayout()` в конце `CHud::Init()` |
| `src/cs16-client/cl_dll/hud_redraw.cpp` | Проверка `hud_layout_reload` в `CHud::Think()`; вызов `DrawDecorations()` в начале `CHud::Redraw()`, перед циклом отрисовки HUD-элементов |
| `src/cs16-client/cl_dll/include/draw_util.h` + `draw_util.cpp` | `DrawUtils::SPR_DrawAdditiveScaled()` (ручной textured quad через `pTriAPI` — `SpriteTexture`+`RenderMode`+`Begin/TexCoord/Vertex/End`; **не** через `pfnSPR_DrawGeneric`, см. «Известные грабли»), параметр `scale` у `DrawHudNumber*` |
| `src/cs16-client/extras/HudLayout.txt` | Образец файла с комментариями |
| `tools/hud-editor/index.html` | Визуальный веб-редактор (см. [[Tooling/Tools]]) |

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
| `Health` | `cl_dll/health.cpp` | позиция иконки cross + числа HP | да — растяг cross + цифр |
| `Battery` | `cl_dll/battery.cpp` | позиция иконки брони + числа | да |
| `Ammo` | `cl_dll/ammo.cpp` | правый край блока патронов + базовая Y | да — цифры, bar, ammo-иконка |
| `AmmoSecondary` | `cl_dll/ammo_secondary.cpp` | правый край + Y для вторичного боезапаса | нет (пока) |
| `Money` | `cl_dll/hud/money.cpp` | правый край блока денег + Y | да — dollar, plus/minus, число |
| `Timer` | `cl_dll/hud/timer.cpp` | позиция левого верхнего угла таймера | да — stopwatch + цифры + colon |
| `Flashlight` | `cl_dll/flashlight.cpp` | правый край + Y фонарика | нет (пока) |
| `DeathNotice` | `cl_dll/death.cpp` | правый край + Y верхней строки killfeed | нет (текст через консольный шрифт) |
| `StatusBar` | `cl_dll/statusbar.cpp` | базовый отступ слева + отступ снизу | нет (текст через консольный шрифт) |

## Не поддерживается (отложено)

- **Radar** — точки рисуются через `iMaxRadius` (центр радара = half-width от (0,0)),
  требует декомпозиции на `center_pos + half_width`, не сделано в этой итерации.
- **SayText / StatusBar / DeathNotice scale** — эти элементы рисуются через консольный шрифт
  движка (`pfnDrawConsoleString`), у которого нет API масштабирования. Потребуется переход на
  quad-рендеринг шрифта, что выходит за рамки текущей итерации.

## Формат `HudLayout.txt`

```
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
Якоря: `top_left`, `top_right`, `bottom_left`, `bottom_right`, `center`. Scale — float, по
умолчанию 1.0 (1.5 = +50% к размеру, 0.75 = −25%). Комментарии вне `"HudLayout { ... }"` не
поддерживаются (используйте закомментированные строки-образцы в файле — они просто не матчатся
с id элементов).

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
  к размеру элемента, а не к координате.
- Для right-aligned элементов (`Ammo`, `Money`, `Flashlight`, `DeathNotice`) семантика `x` =
  «правый край блока», имеет смысл использовать только `top_right`/`bottom_right`. Иные якоря
  дадут неожиданные позиции.
- HP и броня исторически на одной `y` и разнесены по `x` вручную. При свободном позиционировании
  возможно наложение — ответственность пользователя через `HudLayout.txt`.
- Scale применяется только к элементам, у которых он реализован (Health, Battery, Ammo, Money,
  Timer). SayText/StatusBar/DeathNotice используют консольный шрифт движка без API масштабирования.
- Очень маленький scale (например 0.1) может дать артефакты из-за целочисленного округления.

## Связанные cvar'ы
- `hud_layout_reload` — set to 1 для перечитывания `scripts/HudLayout.txt` в рантайме.
