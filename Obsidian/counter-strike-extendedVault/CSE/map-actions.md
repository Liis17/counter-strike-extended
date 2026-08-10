# Действия на картах

Parent: [[Index]] | Связано: [[Архитектура]], [[CSE/cse-structure]], [[Client/HUD-TeamBar]]

## Статус

Статическое исследование завершено по текущим SHA submodule. Карта, компиляторы, install-скрипт
и C++-реализация ещё не создавались.

Подробный документ: [исследование действий на картах](../../../docs/research/custom-map-actions.md).

## Вывод

| Уровень | Возможности | Новый код |
|---|---|---|
| 1. Штатная карта | Кнопки, триггеры, двери, текст, звук, `env_*`, оружие, HP, очки | Нет |
| 2. Серверное расширение | Новый classname, сложное правило или серверное состояние с существующим UI | Серверный C++ либо доказанный plugin path |
| 3. Новый HUD-эвент | `map entity → server Use → user message → HOOK_MESSAGE → HUD` | Серверный и клиентский C++ |

Штатная цепочка — `func_button`/`trigger_multiple` → `target`/`targetname`; активатор
передаётся дальше. `multi_manager` сохраняет игрока, а `trigger_relay` заменяет его собой,
поэтому relay нельзя ставить перед целью, которой нужен именно нажавший игрок.

Для простого общего текста сначала использовать `game_text` с All Players или существующие
`TextMsg`/`HudText`/`HudTextPro`. Новый HUD требует серверного контракта и клиентского
обработчика; текущий Xash ограничивает user message 2048 байт.

## Точки интеграции

| Область | Источник |
|---|---|
| map entities и игровые действия | `src/cs16-client/3rdparty/ReGameDLL_CS/regamedll/dlls/maprules.cpp`, `buttons.cpp`, `triggers.cpp`, `doors.cpp` |
| серверная DLL | `src/cs16-client/3rdparty/ReGameDLL_CS/regamedll/CMakeLists.txt`, `src/cse/cstrike/gameinfo.txt` |
| существующие user messages | `ReGameDLL_CS/regamedll/dlls/client.cpp` → `cs16-client/cl_dll/message.cpp`, `text_message.cpp` |
| клиентский HUD | `src/cs16-client/cl_dll/hud.cpp`, `cl_dll/hud/*.cpp`, `cl_dll/cl_util.h` |
| карта и доставка | будущие `src/cse/maps/` и install-скрипт; сейчас карта не добавлена |

Полный список проверенных исходников, SHA и протокол двухклиентского стенда находятся в
[исследовательском документе](../../../docs/research/custom-map-actions.md).

## Решение проекта

На текущем этапе выбран только уровень 1 как следующий практический шаг. Fork ReGameDLL и
исключение из правила «собственный код только в `src/cse/`» не приняты. До реализации уровня
2/3 нужно отдельно доказать plugin loader либо принять и задокументировать поддерживаемый fork.
