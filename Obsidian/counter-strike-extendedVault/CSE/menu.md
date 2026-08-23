# menu — упрощённое главное меню

Parent: [[Index]]
Связанные: [[Client/cs16-client]], [[CSE/cse-structure]], [[Архитектура]]

## Где живёт меню (важно)

Движок грузит библиотеку меню по пути `cl_dlls/menu.dll` **внутри gamedir**, и только
при её отсутствии — из корня установки (`engine/common/lib_common.c`,
`COM_GenerateClientLibraryPath`). В нашей сборке gamedir — `cstrike`, поэтому
работает `runtime/cstrike/cl_dlls/menu.dll`, который собирает **cs16-client** из
своего submodule `3rdparty/mainui_cpp`.

`src/xash3d-fwgs/3rdparty/mainui` (FWGS/mainui_cpp) собирает `runtime/menu.dll` — он
перекрывается клиентским и на экран не попадает. Правки меню вносить в
**cs16-client'овский** mainui_cpp.

`runtime/menu_tui.dll` — артефакт старой сборки с TUI-меню, не используется.

## Форк и ветка

| Что | Значение |
|-----|----------|
| Submodule | `src/cs16-client/3rdparty/mainui_cpp` |
| origin | `https://github.com/Liis17/mainui_cpp` (форк `Velaron/mainui_cpp`) |
| upstream | `https://github.com/Velaron/mainui_cpp` (remote настроен локально) |
| Ветка с правками | `cs16-client` — от неё же форкается апстрим, master форка не трогаем |

Это исключение из правила «весь свой код в `src/cse/`» ([[CSE/cse-structure]]): правка —
C++ внутри mainui_cpp, вынести её из submodule нельзя, поэтому она живёт в форке,
как и правки самого клиента.

В `.gitmodules` клиента задан только `url`, коммит закреплён по SHA — после
`git submodule update --recursive` дерево оказывается в detached HEAD, а не на
ветке `cs16-client`. Перед любой правкой: `git checkout cs16-client`.

Обновление с апстрима: `git fetch upstream && git rebase upstream/cs16-client`
внутри submodule, затем bump указателя в `src/cs16-client` и в мета-репозитории.

## Состав меню

Класс `CMenuMain` (`menus/Main.cpp`) обслуживает и главное меню, и in-game меню по ESC.

Порядок сверху вниз:

| Кнопка | Действие | Видимость |
|--------|----------|-----------|
| `disconnect` | отключиться от сервера | только в игре и при `maxClients >= 2` |
| `resumeGame` | вернуться в игру | только в игре |
| `multiPlayer` | `UI_MultiPlayer_Menu` (Internet/LAN/игрок/управление) | всегда |
| `personalization` | `UI_Personalization_Menu` (скины оружия и T/CT-оперативники) | всегда |
| `configuration` | `UI_Options_Menu` | всегда |
| `console` | открыть консоль | только при `developer` |
| `quit` | диалог выхода | всегда |

Подсказки справа от кнопок (status text) убраны: во все `SetNameAndStatus` передаётся
`NULL`. Убирать вместо этого флаг `QMF_NOTIFY` нельзя — тогда тот же текст начнёт
рисоваться внизу экрана при наведении (`controls/Framework.cpp`).

`console` занимает слот в стеке только когда виден, иначе между `configuration` и
`quit` осталась бы дыра. `Think()` пересчитывает раскладку при переключении
`developer` в рантайме.

Удалены: ~~newGame~~, ~~hazardCourse~~, ~~saveRestore~~, ~~customGame~~, ~~readme~~,
~~previews~~ (удалены: 2026-08-09) вместе с колбэками `HazardCourseCb`/`HazardCourseDialogCb`,
флагами `bTrainMap`/`bCustomGame` и связанной логикой `SetGrayed`.

`resumeGame` и `disconnect` намеренно оставлены: без них игрок в матче теряет
«Продолжить»/«Отключиться» в ESC-меню.

«Онлайн-игра» ведёт в подменю Multiplayer, а не сразу в браузер серверов: только там
доступны PlayerSetup (имя/модель) и проверка имени (`CMenuMultiplayer::Show`),
в `UI_Options_Menu` их нет.

Кнопка «Персонализация» открывает отдельный экран `CMenuPersonalization`
(`menus/Personalization.cpp`). Экран и автоматический выбор класса после стороны описаны в
[[CSE/personalization]].

## Выбор карт в Create Game

Экран создания локального сервера (`menus/CreateGame.cpp`) читает общий `maps.lst`,
но показывает карты через два фильтра: группу (`Базовые`, `Расширенные`, `Другие`,
`Все карты`) и конкретный префикс внутри группы. По умолчанию открывается группа
`Базовые`. Базовые префиксы — `de_`, `cs_`, `as_`,
`es_`, `csde_`; расширенные — `aim_`, `awp_`, `fy_`, `he_`, `ka_`, `dm_`, `gg_`,
`bhop_`, `surf_`, `kz_`, `1hp_`, `35hp_`, `zm_`, `ze_`. Карты остаются в общей папке
`maps/`; разделение выполняется только в UI.

`CMenuMapListModel::Update()` сохраняет исходный набор карт, а `SetFilter()` и
`Rebuild()` перестраивают отображаемый набор и оставляют `< Случайная карта >` внутри
текущего фильтра. `CMenuCreateGame::UpdateMapTypeFilter()` пересоздаёт список префиксов
при смене группы. Неизвестные префиксы попадают в группу `Другие`, а прежнее исключение
карт `tr_` сохраняется.

| Метод/данные | Назначение |
|---|---|
| `s_baseMapTypes`, `s_extendedMapTypes` | Таблицы поддерживаемых префиксов и подписей типов карт |
| `MapHasPrefix()`, `MapMatchesAnyType()`, `MapGroupForName()`, `MapGroupForValue()`, `AddMapTypeItems()` | Классификация имени карты, значения группы и заполнение фильтра префиксов |
| `CMenuMapListModel::Update()` | Чтение общего `maps.lst` в исходный набор карт |
| `CMenuMapListModel::SetFilter()`, `IsMapVisible()`, `Rebuild()` | Фильтрация и перестроение отображаемой модели |
| `CMenuCreateGame::ApplyMapFilter()` | Применение текущей группы/префикса и сброс выбранной строки |
| `CMenuCreateGame::UpdateMapTypeFilter()` | Обновление списка префиксов после смены группы |

## Локализация кнопок и `render_picbutton_text`

`CMenuPicButton` рендерится двумя способами (`PicButton.cpp:259`):

1. **BMP-атлас** `gfx/shell/btns_main.bmp` — если файл найден в VFS (а он есть в
   `cstrike/extras.pk3`, 864 КБ). Текст кнопок **запечён в растровый атлас** как
   английские надписи, локализация игнорируется.
2. **Текстовым рендерером** (Trebuchet MS через `CWinAPIFont`) — если атлас
   отсутствует **или** выставлен флаг `render_picbutton_text` в `gameinfo.txt`.
   В этом режиме подпись берётся из локализованной строки (`L("GameUI_Options")` и
   т.д.), и кириллица отображается корректно.

Чтобы кнопки главных меню показывались на русском, в `src/cse/cstrike/gameinfo.txt`
выставлен флаг:

```
render_picbutton_text		1
```

Это заставляет `uiStatic.renderPicbuttonText = true` (`BaseMenu.cpp:1192`) и
переключает `PicButton::Draw` на текстовый рендер. Установка —
`tools/install_gameinfo.ps1` (идемпотентно копирует `src/cse/*/gameinfo.txt` →
`runtime/*/gameinfo.txt`).

Без этого флага кнопки всегда английские, даже при `ui_language "russian"` и
полностью переведённых `gameui_russian.txt` / `mainui_russian.txt` — словарь
`L()` отдаёт русские значения, но они не используются, т.к. `hPic != 0`.
