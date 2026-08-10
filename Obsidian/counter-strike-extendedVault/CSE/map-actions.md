# Действия на картах

Parent: [[Index]] | Связано: [[Архитектура]], [[Client/HUD-TeamBar]]

Статическое исследование завершено: [custom-map-actions.md](../../../docs/research/custom-map-actions.md).
Исходник стенда создан: `src/cse/maps/cse_test_actions.map`. J.A.C.K./ZHLT 3.4 собрал BSP,
который локально установлен в `runtime/cstrike/maps/cse_test_actions.bsp`; install-скрипта и
C++-реализации пока нет.

Штатный уровень 1 покрывает кнопки, триггеры, двери, текст, звук, `env_*`, оружие, HP и очки.
Цепочка — `func_button`/`trigger_multiple` → `target`/`targetname`; `multi_manager` сохраняет
активатора, а `trigger_relay` заменяет его собой.

Уровень 2 требует серверного C++ либо доказанного plugin path. Уровень 3 требует схемы
`map entity → server Use → user message → HOOK_MESSAGE → HUD`; для простого текста сначала
используются `game_text`, `TextMsg`, `HudText` или `HudTextPro`.

Следующий практический шаг — запустить двухклиентский стенд уровня 1 и записать фактические результаты. Fork ReGameDLL и exception из
правила `src/cse/` пока не приняты; текущий launcher/plugin path нужно доказать отдельно.
