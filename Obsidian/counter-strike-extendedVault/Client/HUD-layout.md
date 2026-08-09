# HUD layout (кастомизация позиций HUD)

Parent: [[Index]] | Domain: [[Client/cs16-client]]

## Назначение
Система пользовательской настройки позиций элементов HUD (HP, броня, патроны, деньги, таймер и др.)
через внешний текстовый файл `scripts/HudLayout.txt`. Координаты — абсолютные, в сырых пикселях;
якорь (`anchor`) определяет, от какого края экрана отсчитываются значения. Без файла поведение
идентично ванильному CS 1.6.

## Точки кода

| Файл | Что |
|------|-----|
| `src/cs16-client/cl_dll/hud.h` | `enum HudAnchor`, поля `CHudBase::m_szLayoutId/m_iLayoutX/m_iLayoutY/m_eLayoutAnchor/m_bLayoutOverridden`, метод `GetLayoutPos()`, `CHud::LoadLayout()`, `CHud::hud_layout_reload` |
| `src/cs16-client/cl_dll/hud_layout.cpp` | Реализация `CHudBase::GetLayoutPos()` и парсера `CHud::LoadLayout()` |
| `src/cs16-client/cl_dll/hud.cpp` | Регистрация cvar `hud_layout_reload`, вызов `LoadLayout()` в конце `CHud::Init()` |
| `src/cs16-client/cl_dll/hud_redraw.cpp` | Проверка `hud_layout_reload` в `CHud::Think()` |
| `src/cs16-client/extras/HudLayout.txt` | Образец файла с комментариями |

## Как это работает

1. Каждый элемент в своём `Init()` вызывает `strlcpy(m_szLayoutId, "Name", sizeof(m_szLayoutId))`
   ДО `gHUD.AddHudElem(this)`.
2. После регистрации всех элементов `CHud::Init()` вызывает `LoadLayout()`, который читает
   `scripts/HudLayout.txt` (через `gEngfuncs.COM_LoadFile`), ищет записи по `m_szLayoutId`
   в `m_pHudList` и применяет `(x, y, anchor)`, выставляя `m_bLayoutOverridden = true`.
3. В `Draw()` элемент вычисляет **дефолтную** позицию (как в ванилле) и вызывает
   `GetLayoutPos(x, y, defaultX, defaultY)`:
   - если override есть — возвращает абсолютную позицию с учётом якоря;
   - если нет — возвращает `(defaultX, defaultY)`, поведение идентично ванильному.
4. В рантайме: `hud_layout_reload 1` в консоли → `CHud::Think()` перечитывает файл и сбрасывает cvar.

## Поддерживаемые элементы

| ID | Файл Draw | Что задаёт layout |
|----|-----------|-------------------|
| `Health` | `cl_dll/health.cpp` | позиция иконки cross + числа HP (опорная точка) |
| `Battery` | `cl_dll/battery.cpp` | позиция иконки брони + числа |
| `Ammo` | `cl_dll/ammo.cpp` | правый край блока патронов + базовая Y |
| `AmmoSecondary` | `cl_dll/ammo_secondary.cpp` | правый край + Y для вторичного боезапаса |
| `Money` | `cl_dll/hud/money.cpp` | правый край блока денег + Y |
| `Timer` | `cl_dll/hud/timer.cpp` | позиция левого верхнего угла таймера |
| `Flashlight` | `cl_dll/flashlight.cpp` | правый край + Y фонарика |
| `DeathNotice` | `cl_dll/death.cpp` | правый край + Y верхней строки killfeed |
| `StatusBar` | `cl_dll/statusbar.cpp` | базовый отступ слева + отступ снизу для текстовых строк |

## Не поддерживается (отложено)

- **Radar** — точки рисуются через `iMaxRadius` (центр радара = half-width от (0,0)),
  требует декомпозиции на `center_pos + half_width`, не сделано в этой итерации.
- **SayText** — позиция хранится в глобальной `Y_START`, вычисляется в `SayTextPrint`, а не в `Draw`.

## Формат `HudLayout.txt`

```
"HudLayout"
{
    "Health"        "10"   "40"  "bottom_left"
    "Battery"       "120"  "40"  "bottom_left"
    "Ammo"          "20"   "40"  "bottom_right"
}
```

Каждая запись = 4 токена: `"id" "x" "y" "anchor"`. Якоря: `top_left`, `top_right`,
`bottom_left`, `bottom_right`, `center`. Комментарии вне `"HudLayout { ... }"` не поддерживаются
(используйте закомментированные строки-образцы в файле — они просто не матчатся с id элементов).

## Ограничения

- Координаты — в **сырых пикселях** экрана (не масштабируются под разрешение). На разных разрешениях
  лейаут выглядит по-разному — это сознательный выбор. Будущая опция `scale_with_resolution`
  может добавить пропорциональное масштабирование.
- Для right-aligned элементов (`Ammo`, `Money`, `Flashlight`, `DeathNotice`) семантика `x` =
  «правый край блока», имеет смысл использовать только `top_right`/`bottom_right`. Иные якоря
  дадут неожиданные позиции.
- HP и броня исторически на одной `y` и разнесены по `x` вручную. При свободном позиционировании
  возможно наложение — ответственность пользователя через `HudLayout.txt`.

## Связанные cvar'ы
- `hud_layout_reload` — set to 1 для перечитывания `scripts/HudLayout.txt` в рантайме.
