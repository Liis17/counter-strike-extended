# menu — упрощённое главное меню

Parent: [[Index]]
Связанные: [[CSE/cse-structure]], [[Client/cs16-client]], [[Tooling/Tools]], [[Архитектура]]

## Назначение

`src/cse/menu/` — патчи главного меню игры. Хранятся как обычные `git diff`
и применяются к submodule перед сборкой (см. [[CSE/cse-structure]] — своё только в `src/cse/`).

## Где живёт меню (важно)

Движок грузит библиотеку меню по пути `cl_dlls/menu.dll` **внутри gamedir**, и только
при её отсутствии — из корня установки (`engine/common/lib_common.c`,
`COM_GenerateClientLibraryPath`). В нашей сборке gamedir — `cstrike`, поэтому
работает `runtime/cstrike/cl_dlls/menu.dll`, который собирает **cs16-client** из
своего submodule `src/cs16-client/3rdparty/mainui_cpp` (Velaron/mainui_cpp).

`src/xash3d-fwgs/3rdparty/mainui` (FWGS/mainui_cpp) собирает `runtime/menu.dll` — он
перекрывается клиентским и на экран не попадает. Правки меню вносить в
**cs16-client'овский** mainui_cpp.

`runtime/menu_tui.dll` — артефакт старой сборки с TUI-меню, не используется.

## Состав меню после патча

Класс `CMenuMain` (`menus/Main.cpp`) обслуживает и главное меню, и in-game меню по ESC.

| Кнопка | Действие | Видимость |
|--------|----------|-----------|
| `console` | открыть консоль | только при `developer` |
| `disconnect` | отключиться от сервера | только в игре и при `maxClients >= 2` |
| `resumeGame` | вернуться в игру | только в игре |
| `configuration` | `UI_Options_Menu` | всегда |
| `multiPlayer` | `UI_MultiPlayer_Menu` (Internet/LAN/игрок/управление) | всегда |
| `quit` | диалог выхода | всегда |

Удалены: ~~newGame~~, ~~hazardCourse~~, ~~saveRestore~~, ~~customGame~~, ~~readme~~,
~~previews~~ (удалены: 2026-08-09) вместе с колбэками `HazardCourseCb`/`HazardCourseDialogCb`,
флагами `bTrainMap`/`bCustomGame` и связанной логикой `SetGrayed`.

`resumeGame` и `disconnect` намеренно оставлены: без них игрок в матче теряет
«Продолжить»/«Отключиться» в ESC-меню.

«Онлайн-игра» ведёт в подменю Multiplayer, а не сразу в браузер серверов: только там
доступны PlayerSetup (имя/модель) и проверка имени (`CMenuMultiplayer::Show`),
в `UI_Options_Menu` их нет.

## Применение патча

```
tools\apply_menu_patch.ps1 [-DryRun] [-Root <path>]
```

Идемпотентно: перед применением проверяет `git apply --reverse --check` — если патч
уже в дереве, шаг пропускается. Вызывается автоматически шагом `[1/5]` в `build-cse.cmd`.

Если апстрим mainui_cpp обновился и патч перестал накладываться — скрипт падает с
сообщением; патч нужно перегенерировать:

```
git -C src/cs16-client/3rdparty/mainui_cpp diff -- menus/Main.cpp > src/cse/menu/main-menu-simplify.patch
```

## Ограничения

Подписи кнопок берутся из строк клиента (`Configuration`, `Play CS`, `Quit`) и на
момент патча не локализованы — это отдельный домен, см. [[Localization/Локализация]].
