# cs16-client

Parent: [[Index]]

## Назначение
Реверс-инженеренный клиент Counter-Strike 1.6, рассчитан на платформы без официальной поддержки (мобильные и
не только). Fork проекта: https://github.com/Liis17/cs16-client; исходный апстрим:
https://github.com/Velaron/cs16-client. Подключён как git submodule в `src/cs16-client` (ветка `main`).

## Файлы
- `src/cs16-client/` — корень апстрим-репозитория клиента (cl_dll/, dlls/, game_shared/, pm_shared/, engine/, public/, common/)
- `src/cs16-client/CMakeLists.txt`, `CMakePresets.json` — точки сборки

## Сборка
CMake (`cmake --preset <preset>`, либо ручная генерация под платформу — Win32/Linux/macOS/Android). Устанавливается
поверх директории движка Xash3D FWGS (`--prefix <path-to-xash3d-fwgs-install>`).

## Зависит от
- [[Engine/xash3d-fwgs]] — требует последнюю dev-сборку движка для запуска
- Легальный `valve/` + `cstrike/` из Steam-версии Counter-Strike (копируются в `runtime/`, в репозиторий не входят)

## Важные детали
CVars клиента (hud_color, xhair_*, cl_weaponlag и др.) документированы в апстрим README — не дублируем здесь,
смотреть `src/cs16-client/README.md` при необходимости.

## Собственные расширения репозитория
- [[Client/HUD-layout]] — система кастомизации позиций элементов HUD (HP, броня, патроны, деньги,
  таймер, XPBar и др.) через внешний файл `scripts/HudLayout.txt`. Реализована в `cl_dll/hud_layout.cpp`,
  точки расширения в `cl_dll/hud.h` (`CHudBase::m_szLayoutId`, `GetLayoutPos()`), интеграция в
  `cl_dll/hud.cpp` (`CHud::LoadLayout()`, cvar `hud_layout_reload`).
- [[Client/HUD-Scoreboard]] — новый CS2-подобный scoreboard в `cl_dll/hud/scoreboard.cpp`: удержание
  Tab через штатные `+showscores/-showscores`, intermission/death/`showscoreboard2`, сортировка,
  командный счёт, статусы и adaptive fit; тема живёт в `HudLayout.txt` как `ScoreboardStyle`.
- [[Client/HUD-TeamBar]] — TeamBar и Scoreboard используют общий `cl_dll/cse_player_avatars.cpp`
  (Steam cache, bot avatar и буквенный fallback), поэтому `wanted.txt` пишет только один pipeline.
- [[CSE/progression]] — клиентский локальный профиль XP и статистики в `cl_dll/cse_profile.cpp` и
  разбор `scripts/CseProgression.txt` в `cl_dll/cse_progression.cpp`. События подключены к
  `DeathMsg`, `TeamScore`, `CHud::Redraw()` и `CHud::Shutdown()`; `cl_dll/cse_skins.cpp` реализует
  локальный выбор скина и подмену собственного viewmodel в `cs_wpn/cs_weapons.cpp`. `cl_dll/hud/xpbar.cpp`
  рисует уровень и прогресс XP, а `cse_progression.cpp` отдаёт HUD пороги уровней.
- [[CSE/personalization]] — `cl_dll/cse_profile.cpp` хранит выбранных T/CT-оперативников и публикует
  профильные cvar для отдельной `menu.dll`; экран в `3rdparty/mainui_cpp` выбирает скины и модели,
  а class-menu преобразует сохранённую модель в штатную команду `joinclass` после выбора стороны.
- [[CSE/profile]] — отдельный экран `3rdparty/mainui_cpp/menus/Profile.cpp`, получает summary и задачи
  через `cse_*` cvar, а полную историю матчей и статистику карт читает из текущего профиля.
- Быстрое переключение оружия — `cl_dll/ammo.cpp`: `SelectWeaponImmediately()` отправляет
  имя оружия серверу и заполняет `cmd->weaponselect`; `WeaponsResource::SelectSlot()`,
  `CHudAmmo::UserCmd_NextWeapon()` и `UserCmd_PrevWeapon()` вызывают его сразу для цифровых
  слотов и колеса, поэтому подтверждение через `IN_ATTACK` больше не требуется. `hud_fastswitch`
  оставлен зарегистрированным для совместимости со старыми конфигами, но его значение намеренно
  не отключает это поведение CSE.
