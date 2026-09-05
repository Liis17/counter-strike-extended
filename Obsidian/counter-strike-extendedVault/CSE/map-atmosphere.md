# Атмосфера карт — первый этап

Parent: [[Index]] · Связанные: [[CSE/cse-structure]], [[CSE/map-actions]], [[Tooling/Tools]], [[Tooling/server-cmd]]

## Статус

Первый data-only этап реализован 05.09.2026. Submodule-код не изменялся,
существующие BSP не редактируются, новые WAD/модели/WAV/waypoints не добавлялись.

В состав этапа входят:

- `.ent`-dressing только для `cs_backalley` и `de_torn`;
- stock-звуки, декали из штатных WAD, `cycler_wreckage`, `env_glow`, rain/fog;
- собственная `cse_lobby` — компактный закрытый техдвор с крытой мастерской;
- отдельный внешний map pipeline и проверяющий install-скрипт.

## Источники и pipeline

```
src/cse/maps/build-list.txt
    ├── cse_test_actions.map
    └── cse_lobby.map
             │
             ▼  hlcsg → hlbsp → hlvis → hlrad
build/cse-maps/work/<map>/
             │
             ▼  только после успешного полного pipeline
build/cse-maps/output/<map>.bsp + manifest.json
             │
             ▼
runtime/cstrike/maps/<map>.bsp
```

`tools/build_cse_maps.ps1` принимает `-Root`, `-DryRun` и `-ToolchainRoot`.
Путь также можно задать `CSE_MAP_TOOLCHAIN_ROOT`; default —
`C:\Program Files\J.A.C.K.\halflife`. Компиляторы не являются частью репозитория.
При отсутствии хотя бы одного `hl*.exe` скрипт печатает красное предупреждение,
создаёт пустой manifest и успешно пропускает карты. Ошибка уже запущенного
компилятора завершает сборку; install использует только завершённый manifest.

`tools/install_cse_maps.ps1` переносит BSP из output, устанавливает `.res`, а для
`.ent` сначала выполняет синтаксическую и ресурсную проверку. При обычном вызове
`.ent` получает время на две секунды новее соответствующего BSP, как требует
проверка внешнего entity patch в Xash3D.

## Политика `.ent`

Полные snapshots лежат в `src/cse/maps/ent/<map>.ent`; соответствующие manifests —
в `src/cse/maps/res/<map>.res`. Каждый `.res` snapshot обязан содержать
`maps/<map>.ent`. Install сравнивает первые entity-блоки snapshot с entity lump
текущего BSP без изменения порядка; новые блоки допускаются только в конце.

Разрешённые добавленные классы: `ambient_generic`, `infodecal`, `env_rain`,
`env_snow`, `env_fog`, `env_sprite`, `env_glow`, `cycler_wreckage`.
`light*`, brush `func_*`, `cycler` и `cycler_sprite` запрещены. Модельные props
используют только `cycler_wreckage`, который в текущем ReGameDLL несолидный.

Лимиты на одну карту: максимум 24 новых entities, 8 props, 4 ambient-звука,
12 decals, один weather entity и один fog entity. Фактический пилот добавляет
на каждую карту 13 entities: 4 props, 2 ambient, 4 decals, rain, fog и glow.

## `cse_lobby`

Карта использует только `halflife.wad` и `cstrike.wad`, но не содержит собственных
текстур. Геометрия — небольшой закрытый двор со sky-оболочкой и крытой мастерской;
освещение запекается `hlrad` через `light_environment` и три точечных `light`.
На карте нет bomb/hostage objectives и нет waypoint-графа YaPB. Она присутствует
в `CseMapCatalog.json`, но намеренно отсутствует в `src/cse/cstrike/mapcycle.txt`.

Запуск:

```cmd
server.cmd cse_lobby -nobots
```

Для `cse_lobby` `-nobots` выбирает штатный `mp.dll` без YaPB/proxy и передаёт
`+yb_quota 0`; обычная ротация карт при этом не меняется.

## Проверка и следующий gate

Уже проверено: dry-run обоих скриптов, красное предупреждение при отсутствующем
toolchain, успешная реальная сборка `cse_test_actions`/`cse_lobby`, отсутствие leak/
compile errors в логах, сохранение entity-блоков, ресурсы и timestamp `.ent`.
Dedicated smoke-test `server.cmd cse_lobby -nobots` загрузил карту как `12 player
server` без запуска YaPB и без missing texture/sound.

До расширения dressing остаётся обязательный игровой gate: два клиента должны
загрузить один и тот же stock BSP, второй получить `.ent` через `.res`, а затем
нужно проверить props/decals/rain/fog, CRC, проходы, site-lines, прострелы,
spawn-зоны, round restart и `edict_usage` на `cs_backalley` и `de_torn`. До этого
новые stock-карты не добавлять.
