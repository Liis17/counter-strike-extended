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
