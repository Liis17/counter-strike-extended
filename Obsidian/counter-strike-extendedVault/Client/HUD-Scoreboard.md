# HUD Scoreboard — современная таблица матча

Parent: [[Index]] | Domain: [[Client/cs16-client]] | Связано: [[Client/HUD-layout]], [[Tooling/hud-editor]], [[Client/HUD-TeamBar]]

## Назначение

`CHudScoreboard` теперь рисует компактный CS2-подобный overlay вместо старой табличной отрисовки.
Команда открывается теми же `+showscores/-showscores`: удержание Tab, touch/force-вызов,
intermission и `cl_show_scoreboard_on_death` используют один renderer. Сигнатура `showscoreboard2`
сохранена — переданные legacy RGBA-аргументы принимаются, но тема всё равно берётся из
`ScoreboardStyle`.

## Состав и порядок

- Секции команд идут вертикально; команда локального игрока первая, для зрителя порядок CT → T.
- Заголовок содержит название команды, число игроков и раундовый счёт из `TeamScore`.
- Строка содержит квадратный Steam/bot/fallback-аватар, имя, статус, K, D и ping/BOT.
- Статусы: `DEAD`, `C4`, `VIP`, `KIT`; `cl_showplayerversion` заменяет статус версией клиента.
- Локальный игрок подсвечивается, мёртвые строки и аватары затемняются. HP и деньги намеренно
  не выводятся.
- Игроки сортируются по убийствам по убыванию, смертям по возрастанию, затем по индексу слота.
  Все подключённые игроки показываются; зрители и unassigned идут отдельной компактной строкой.
- Размеры автоматически уменьшаются, если список не помещается в экран или bounds `showscoreboard2`.
  Длинные имена обрезаются без разрыва UTF-8-кодовой точки.

## Точки кода

| Файл | Ответственность |
|------|-----------------|
| `src/cs16-client/cl_dll/hud/scoreboard.cpp` | renderer, сортировка, сообщения `ScoreInfo/TeamInfo/TeamScore`, `+showscores`, `showscoreboard2` |
| `src/cs16-client/cl_dll/hud.h` | `ScoreboardStyle`, состояние force-bounds и API темы |
| `src/cs16-client/cl_dll/hud_layout.cpp` | независимый опциональный разбор `ScoreboardStyle`, сброс defaults при reload |
| `src/cs16-client/cl_dll/cse_player_avatars.{cpp,h}` | общий кэш Steam-аватаров до `MAX_PLAYERS`, bot/fallback pipeline, wanted.txt |
| `src/cs16-client/cl_dll/hud/teambar.cpp` | потребитель общего avatar pipeline; собственного writer'а `wanted.txt` нет |
| `src/cse/cstrike/scripts/HudLayout.txt` | запись `Scoreboard` и проектный CS2 preset |
| `tools/hud-editor/` | draggable элемент, тема, preview, parser/serializer и undo/redo |

## HudLayout и тема

Элемент подключается обычной записью:

```text
"Scoreboard" "0" "0" "center" "1"
```

После `HudLayout`/`HudDecorations` может находиться независимый блок `ScoreboardStyle`.
Все размеры — базовые пиксели до `scale`; отсутствующий блок оставляет встроенный preset:

```text
"ScoreboardStyle"
{
    "width" "960" "row_height" "36" "header_height" "40" "avatar_size" "28"
    "padding" "14" "row_gap" "2" "section_gap" "10" "corner_radius" "8"
    "status_width" "84" "kills_width" "56" "deaths_width" "56" "ping_width" "72"
    "scrim_color" "0,0,0,72" "panel_color" "11,16,23,232"
    "row_color" "22,29,39,210" "border_color" "84,96,112,120"
    "ct_color" "86,164,255,96" "t_color" "229,183,78,96"
    "self_color" "255,255,255,34" "text_color" "238,242,247"
    "muted_color" "153,164,179" "dead_alpha" "112"
}
```

`CHud::LoadLayout()` сначала возвращает тему к defaults, затем разбирает оба блока независимо.
Неизвестные ключи игнорируются, неверные значения остаются defaults или clamp'ятся. Редактор
сохраняет блок только если включён `theme override`, поэтому файл без `ScoreboardStyle` проходит
open → save без скрытого добавления темы.

## Аватары

`CSE_PlayerAvatars_UpdateWanted()` вызывается TeamBar раз в 0,5 секунды и записывает отсортированный
набор SteamID подключённых игроков в единый `cache/avatars/wanted.txt`. `CSE_DrawPlayerAvatar()`
использует общий кэш текстур, затем `CSE_BotAvatar`, затем первую UTF-8-безопасную букву имени.
Сброс кэша и bot list выполняются в `VidInit`; Scoreboard и TeamBar больше не конкурируют за файл.

## Проверка

После добавления `.cpp` требуется повторить CMake configure (glob источников не использует
`CONFIGURE_DEPENDS`), затем собрать Release и установить client в runtime. В игре проверить
удержание/отпускание Tab, intermission/death, `showscoreboard2`, сортировку, CT/T score, 5×5,
10×10 и большие составы, статусы, fallback аватаров, TeamBar и `engine.log`.
