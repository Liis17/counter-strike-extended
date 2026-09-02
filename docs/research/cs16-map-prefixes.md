# CS 1.6: префиксы карт и игровые режимы

Дата исследования: 2026-08-23.

## Краткий вывод

В CS 1.6 префикс имени карты в основном является соглашением, а не источником серверных правил. ReGameDLL_CS, используемый как читаемый reverse-engineered ориентир GameDLL CS 1.6, ставит обычный `CHalfLifeMultiplay` для multiplayer и затем определяет сценарии по сущностям карты: `func_bomb_target` / `info_bomb_target`, `hostage_entity`, `func_vip_safetyzone`, `func_escapezone`. Клиентский код дополнительно проверяет `as_` и `de_` по имени карты для отдельных UI/клиентских решений.

Проверенные стандартные для Counter-Strike 1.6 префиксы:

| Префикс | Режим / тип | Что подтверждено |
|---|---|---|
| `de_` | Bomb Defusal / Bomb Target | Valve Developer Community указывает `de_` для Bomb Defusal; ReGameDLL включает bomb-сценарий по `func_bomb_target` или `info_bomb_target`; клиентская функция `IsDEMapType()` проверяет `maps/de_` и `de_`. |
| `cs_` | Hostage Rescue | Valve Developer Community указывает `cs_` для Hostage Rescue; ReGameDLL использует `hostage_entity` для hostage timeout и `func_hostage_rescue` как rescue zone. В найденном коде нет серверной проверки префикса `cs_`. |
| `as_` | Assassination / VIP escape | Valve Developer Community указывает `as_` для Assassination; ReGameDLL включает VIP-сценарий по `func_vip_safetyzone`; клиентская функция `IsASMapType()` проверяет `maps/as_` и `as_`. |
| `es_` | Terrorist Escape, исторический/defunct | ReGameDLL всё ещё проверяет `func_escapezone` и имеет round timeout для prison/terrorist escape; Valve Developer Community map-prefix page помечает `es_` как Terrorist Escape, now defunct. В локальном CS 1.6 mapcycle `es_` карт нет. |

Важно: `de_`, `cs_`, `as_`, `es_` не являются единственным техническим механизмом режима. Карта с другим именем, но с нужными сущностями, может активировать соответствующую серверную логику; карта с правильным префиксом, но без сущностей, не становится полноценным сценарием только из-за имени.

## Кастомные и community-префиксы

Для этих префиксов не найдено подтверждения, что vanilla CS 1.6 GameDLL назначает режим по имени. Проверяемый статус такой: это распространённые community labels, обычно обслуживаемые AMX Mod X/Metamod/ReAPI плагинами, настройками по prefix-config или просто соглашением mapper/server community.

| Префикс | Обычно означает | Проверяемое основание |
|---|---|---|
| `aim_` | Aim/training карта | Valve Developer Community map-prefix page перечисляет `aim_` среди unofficial/community prefixes; vanilla/ReGameDLL logic не найдена. |
| `awp_` | AWP-only/sniper карта | AMX Mod X документация прямо приводит `awp` как пример map-prefix config. |
| `fy_` | Fight Yard / small weapon arena | AMX Mod X документация приводит `fy_iceworld` как пример third-party map с отдельной конфигурацией. |
| `ka_` | Knife Arena | Valve Developer Community map-prefix page перечисляет `ka_` среди unofficial/community prefixes; vanilla/ReGameDLL logic не найдена. |
| `he_` | HE grenade arena | Valve Developer Community map-prefix page перечисляет `he_` среди unofficial/community prefixes; vanilla/ReGameDLL logic не найдена. |
| `surf_` | Surf карта | AMX Mod X документация прямо приводит `surf` как пример map-prefix config. |
| `kz_` | Kreedz / climbing / jump map | Kreedz.com позиционирует себя как official CS 1.6 KZ speedrunning community; это отдельная community-модель карт/серверов, не GameDLL-префикс. |
| `bhop_` | Bunny hop карта | Valve Developer Community map-prefix page перечисляет `bhop_` среди unofficial/community prefixes; может пересекаться с KZ, но vanilla/ReGameDLL logic не найдена. |
| `gg_` | GunGame | Подтверждён как отдельный CS 1.6 GunGame mode/plugin ecosystem; префикс `gg_` остаётся convention, не GameDLL-режимом. |
| `dm_` | Deathmatch | Подтверждён как отдельный deathmatch plugin/mod ecosystem, например ReDeathmatch; префикс `dm_` остаётся convention. |
| `zm_` | Zombie Mod / Zombie Plague | Zombie Plague archive описывает отдельный AMXX mod для CS 1.6/CZ; префикс `zm_` остаётся convention. |
| `ze_` | Zombie Escape | Подтверждён как Zombie Plague Special / Zombie Escape ecosystem в community sources; не найдено vanilla/ReGameDLL назначение режима по `ze_`. |

AMX Mod X важен как инфраструктурное подтверждение того, что серверная экосистема реально работает с префиксами карт: с версии 1.8.0 можно задавать `configs/maps/prefix_<prefix>.cfg` и `plugins-<prefix>.ini`; документация прямо приводит `de`, `cs`, `awp`, `surf` как примеры и `fy_iceworld` как пример third-party map. Это подтверждает применимость prefix convention, но не доказывает семантику каждого кастомного префикса.

## Источники

### Код в репозитории

- ReGameDLL_CS в текущей рабочей копии: `src/cs16-client/3rdparty/ReGameDLL_CS`, SHA `7be9d59dca1ee11d270e4631d7e3be0c67a1a82b`.
- CS16Client в текущей рабочей копии: `src/cs16-client`, SHA `142dd93d01072a3b356c83dc9a38682b83c60aba`.
- `InstallGameRules()` выбирает `CHalfLifeMultiplay` для deathmatch/multiplayer, не карту по префиксу: `src/cs16-client/3rdparty/ReGameDLL_CS/regamedll/dlls/gamerules.cpp:134-142`.
- `CheckMapConditions()` ищет `func_bomb_target`, `info_bomb_target`, `func_hostage_rescue`, `func_escapezone`, `func_vip_safetyzone`: `src/cs16-client/3rdparty/ReGameDLL_CS/regamedll/dlls/multiplay_gamerules.cpp:1640-1670`.
- Round timeout branch различает bomb, hostage, escape, VIP по найденным сущностям/флагам: `src/cs16-client/3rdparty/ReGameDLL_CS/regamedll/dlls/multiplay_gamerules.cpp:3058-3075`.
- Клиентские helpers проверяют только `as_` и `de_` по имени карты: `src/cs16-client/cl_dll/hud.h:90-99`.
- Локальный mapcycle содержит штатные `de_`, `cs_`, `as_` карты: `src/cse/cstrike/mapcycle.txt:1-17`.

### Внешние ссылки

- Valve Developer Community, Counter-Strike page: <https://developer.valvesoftware.com/wiki/Counter-Strike>
- Valve Developer Community, Map prefixes and suffixes: <https://developer.valvesoftware.com/wiki/Map_prefixes_and_suffixes>
- ReHLDS documentation for ReGameDLL_CS as reverse-engineered CS 1.6/CZ GameDLL replacement: <https://rehlds.dev/docs/regamedll-cs/>
- ReGameDLL_CS upstream source, `multiplay_gamerules.cpp`: <https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp>
- ReGameDLL_CS upstream source, `gamerules.cpp`: <https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/gamerules.cpp>
- AMX Mod X map config documentation: <https://wiki.alliedmods.net/Configuring_amx_mod_x#Maps>
- AMX Mod X 1.8.0 per-map prefix feature: <https://wiki.alliedmods.net/Amx_mod_x_1.8.0_changes#Per-Map_Features>
- AMX Mod X legacy maps documentation with `fy_iceworld`: <https://www.amxmodx.org/doc/source/configuration/maps.htm>
- Kreedz GitHub organization, described as official CS 1.6 Kreedz community: <https://github.com/kreedzcom>
- ReDeathmatch documentation: <https://redeathmatch.github.io/en/Getting-started/>
- GunGame CS 1.6 ReAPI plugin repository: <https://github.com/d3m37r4/regg>
- Zombie Plague Mod archive: <https://github.com/Sh1ft0x0EF/Zombie-Plague-Mod>
- Zombie Plague Special / Zombie Escape discussion source for `ze_` support: <https://forums.alliedmods.net/archive/index.php/t-260845.html>
