# xash3d-fwgs

Parent: [[Index]]

## Назначение
Форк движка Xash3D — совместим с Half-Life Engine, расширяет его (мультиплеер, рендереры, VFS, мобильная поддержка).
Основной репозиторий: https://github.com/Liis17/xash3d-fwgs. Апстрим: https://github.com/FWGS/xash3d-fwgs.
Подключён как git submodule в `src/xash3d-fwgs` (ветка `continuous`); изменения движка отправляются в fork.

## Файлы
- `src/xash3d-fwgs/` — корень апстрим-репозитория движка (engine/, filesystem/, game_launch/, pm_shared/, common/, android/, 3rdparty/)
- `src/xash3d-fwgs/Documentation/` — апстрим-документация (goldsrc-протокол, порты, донат)

## Сборка
Waf build system (не CMake). x86 по умолчанию на Windows/Linux для совместимости со Steam-релизами Half-Life.

## Ключевые особенности (из апстрим README)
| Особенность | Описание |
|---|---|
| HLSDK 2.5 | Совместимость со Steam Half-Life |
| Кроссплатформенность | Windows, Linux, BSD, Android + порты |
| Мультиплеер | Множественные мастер-серверы, headless dedicated server, voice chat, GoldSrc protocol, IPv6 |
| Рендереры | OpenGL, GLESv1, GLESv2, Software |
| VFS | `.pk3`/`.pk3dir`, совместимость с GoldSrc FS, case-insensitivity |

## Зависимости
- Используется в: [[Tooling/Tools]] (запуск/скриншот `xash3d.exe`)
- Требует легальный `valve/` каталог из Steam-версии Half-Life (копируется в `runtime/`, в репозиторий не входит)

## Важные детали
Только официальные бинарники/сборки из апстрим-релизов — README апстрима явно предупреждает про вредоносные
репаки. При обновлении версии submodule сверяться с CONTRIBUTING.md апстрима на предмет смены build-флоу.
