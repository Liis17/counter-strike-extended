# Действия на картах

Parent: [[Index]] | Связано: [[Архитектура]], [[Client/HUD-TeamBar]]

Статическое исследование завершено: [custom-map-actions.md](../../../docs/research/custom-map-actions.md).
Исходник стенда хранится в `src/cse/maps/cse_test_actions.map`; J.A.C.K./ZHLT 3.4
собирает его через общий pipeline карт. Детали data-only dressing и собственного
`cse_lobby` описаны в [[CSE/map-atmosphere]].

Штатный уровень 1 покрывает кнопки, триггеры, двери, текст, звук, `env_*`, оружие, HP и очки.
Цепочка — `func_button`/`trigger_multiple` → `target`/`targetname`; `multi_manager` сохраняет
активатора, а `trigger_relay` заменяет его собой.

Уровень 2 требует серверного C++ либо доказанного plugin path. Уровень 3 требует схемы
`map entity → server Use → user message → HOOK_MESSAGE → HUD`; для простого текста сначала
используются `game_text`, `TextMsg`, `HudText` или `HudTextPro`.

Следующий практический шаг для map actions — запустить двухклиентский стенд уровня 1
и записать фактические результаты. Fork ReGameDLL и exception из правила `src/cse/`
по-прежнему не являются частью этого data-only этапа.

Исходный план контента карт — [map-content-roadmap.md](../../../docs/plans/map-content-roadmap.md);
реализованный первый этап и его ограничения — [[CSE/map-atmosphere]]. Waypoints для
`cse_lobby` не создаются: карта запускается через `server.cmd cse_lobby -nobots`.
