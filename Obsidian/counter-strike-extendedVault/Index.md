# counter-strike-extended — База знаний

Мета-репозиторий поверх движка Xash3D FWGS и клиента CS16Client. Собирает форк Half-Life-совместимого движка + реверс-инженеренный клиент Counter-Strike 1.6 в единый билд-контур. Оба движка подключены как git submodules, собственный код репозитория — обвязка (инструменты, конфигурация сборки, gitignore рантайма).

## Навигация

### Архитектура
- [[Архитектура]] — состав репозитория, сабмодули, сквозной build/run поток

### Engine
| Файл | Компонент | Описание |
|------|-----------|----------|
| [[Engine/xash3d-fwgs]] | xash3d-fwgs | Форк движка Xash3D (Half-Life engine compatible), submodule |

### Client
| Файл | Компонент | Описание |
|------|-----------|----------|
| [[Client/cs16-client]] | cs16-client | Реверс-инженеренный клиент CS 1.6, submodule |
| [[Client/HUD-layout]] | HUD-layout | Кастомизация позиций/декораций HUD через `scripts/HudLayout.txt`, редактируется визуально через `tools/hud-editor` |
| [[Client/HUD-TeamBar]] | HUD TeamBar | Лента «слоты T / счёт / слоты CT» (`cl_dll/hud/teambar.cpp`) со Steam-аватарами через [[CSE/rich_presence]] и случайными аватарами ботов от сервера |

### CSE (собственный код проекта)
| Файл | Компонент | Описание |
|------|-----------|----------|
| [[CSE/cse-structure]] | src/cse/ | Правило «все моды/изменения проекта — только здесь» + структура |
| [[Localization/Локализация]] | src/cse/localization/ | Русские переводы (GameUI, valve, mainui, CS, токены Steam RP) |
| [[CSE/rich_presence]] | src/cse/rich_presence/ | Steam Rich Presence helper (`cse_steamrp.exe`) — внешний wrapper xash3d |
| [[CSE/menu]] | mainui_cpp (форк) | Упрощённое главное меню с отдельным входом в персонализацию |
| [[CSE/personalization]] | Player personalization | Скины оружия по уровню и сохранённые T/CT-оперативники с автовыбором класса |
| [[CSE/progression]] | Player progression | Локальный профиль, статистика, XP и уровни в клиенте |
| [[CSE/map-actions]] | Действия на картах | Исследование штатных кнопок/триггеров, серверного расширения и кастомного HUD-события |
| [[CSE/de_dust2]] | Исходник de_dust2 | Приближённая декомпиляция BSP для редактирования в Hammer/J.A.C.K. |

### Tooling
| Файл | Компонент | Описание |
|------|-----------|----------|
| [[Tooling/Tools]] | tools/ | Вспомогательные скрипты (скриншот окна игры, install локализации) и веб-редактор HUD-конфига |
| [[Tooling/hud-editor]] | tools/hud-editor | Визуальный редактор `HudLayout.txt`: выделение/группы, привязки, выравнивание, история |
| [[Tooling/server-cmd]] | server.cmd | Dedicated-сервер CS + боты YaPB; нюанс: `-dll` = путь относительно gamedir |
| [[Tooling/mcp-game]] | tools/mcp-game | MCP-сервер `game` для opencode: build/deploy/run игры через tools |

## Правила обновления базы знаний

При работе с проектом обновляй соответствующий файл, если изменилась архитектура, добавлен компонент,
изменились зависимости или конфигурация. Новый компонент → `{Domain}/{Name}.md` + ссылка здесь.
Wikilinks — `[[Файл]]` или `[[Домен/Файл]]`.

Sub-модули (`src/xash3d-fwgs`, `src/cs16-client`) — сторонний код в fork'ах Liis17. Заметки о них
описывают роль в сборке и точки интеграции, а не внутреннюю структуру апстрима — при обновлении версии
submodule достаточно сверить, не изменился ли способ сборки/установки (CMakePresets, Waf).
