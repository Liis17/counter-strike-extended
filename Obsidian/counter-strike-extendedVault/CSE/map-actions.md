# Действия на картах

Parent: [[Index]] | Связано: [[Архитектура]], [[Client/HUD-TeamBar]]

Статическое исследование завершено: [custom-map-actions.md](../../../docs/research/custom-map-actions.md).
Исходник стенда создан: `src/cse/maps/cse_test_actions.map`. BSP, компиляторы, install-скрипт и
C++-реализация пока отсутствуют.

Штатный уровень 1 покрывает кнопки, триггеры, двери, текст, звук, `env_*`, оружие, HP и очки.
Цепочка — `func_button`/`trigger_multiple` → `target`/`targetname`; `multi_manager` сохраняет
активатора, а `trigger_relay` заменяет его собой.

Уровень 2 требует серверного C++ либо доказанного plugin path. Уровень 3 требует схемы
`map entity → server Use → user message → HOOK_MESSAGE → HUD`; для простого текста сначала
используются `game_text`, `TextMsg`, `HudText` или `HudTextPro`.

Следующий практический шаг — скомпилировать исходник и запустить двухклиентский стенд уровня 1. Fork ReGameDLL и exception из
правила `src/cse/` пока не приняты; текущий launcher/plugin path нужно доказать отдельно.
