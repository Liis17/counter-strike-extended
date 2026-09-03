# Персонализация игрока

Parent: [[Index]]
Связанные: [[CSE/menu]], [[CSE/progression]], [[Client/cs16-client]], [[CSE/personalization-ProjectMap]]

## Назначение

Экран `UI_Personalization_Menu` позволяет выбрать доступный по уровню вариант из полного каталога
оружия и сохранить предпочитаемого оперативника отдельно для террористов и спецназа. Кнопка
«Персонализация» доступна в главном и ESC-меню; статистика и задачи вынесены в отдельный [[CSE/profile]].

## Компоненты

| Компонент | Путь | Назначение |
|-----------|------|------------|
| Экран | `src/cs16-client/3rdparty/mainui_cpp/menus/Personalization.cpp` | Таблица скинов, два селектора оперативников и общий 3D/TGA-preview |
| Вход из главного меню | `src/cs16-client/3rdparty/mainui_cpp/menus/Main.cpp` | Кнопка `personalization` → `UI_Personalization_Menu` |
| Автовыбор класса | `src/cs16-client/3rdparty/mainui_cpp/menus/client/JoinClass.cpp` | Переводит сохранённую модель стороны в `joinclass 1..4` |
| Каталог оперативников | `src/cs16-client/3rdparty/mainui_cpp/cse_operators.h` | Единая таблица моделей, локализаций и номеров `joinclass` для обеих DLL |
| Профиль и команды | `src/cs16-client/cl_dll/cse_profile.{h,cpp}` | Хранит `operator_t`/`operator_ct`, публикует cvar и обрабатывает `cse_operator` |
| Скины и уровни | `src/cse/cstrike/scripts/CseCosmetics.txt` | Источник 63 вариантов, порогов разблокировки и `v/p/w`-путей |

## Поток выбора

1. При открытии экран читает `cse_level`, `cse_skins`, `cse_operator_t` и `cse_operator_ct`.
2. Таблица повторно разбирает блок `weapons/variants` из `scripts/CseCosmetics.txt`; заблокированные строки
   серые, а попытка экипировать их показывает требуемый уровень. Клиентская команда `cse_skin`
   повторяет проверку уровня, поэтому UI не является границей безопасности.
3. Выбор оперативника немедленно вызывает `cse_operator <t|ct> <model>`, сохраняет профиль и обновляет
   соответствующий cvar. Доступны четыре штатных класса CS 1.6 для каждой стороны.
4. После подтверждения стороны сервер показывает штатное class-menu. `UI_JoinClassT_Show()` или
   `UI_JoinClassCT_Show()` читает предпочтение, закрывает client-menu и отправляет соответствующий
   `joinclass 1..4`; ручной экран класса остаётся fallback для пустого/неизвестного cvar.

## Хранение и границы DLL

Профиль в `client.dll` остаётся источником правды. `menu.dll` не линкуется с клиентской C++-логикой,
поэтому обмен идёт через движковые cvar и команды:

| Имя | Направление | Содержимое |
|-----|-------------|------------|
| `cse_level` | client → menu | Вычисленный текущий уровень |
| `cse_skins` | client → menu | Legacy-представление выбранных вариантов, например `ak47:steppe;awp:taiga` |
| `cse_loadout` | client → server/menu | Versioned v2-loadout со стабильными 30 слотами |
| `cse_xp`, `cse_kills`, `cse_headshots`, `cse_deaths` | client → menu | Summary lifetime-профиля |
| `cse_round_wins`, `cse_round_losses`, `cse_match_wins`, `cse_match_losses` | client → menu | Summary раундов и матчей |
| `cse_daily_0..2`, `cse_weekly_0..1` | client → menu | `id|progress|target|rewardXp|rewarded` для таблиц задач |
| `cse_profile_file` | client → menu | Имя активного SteamID/local профиля для чтения истории |
| `cse_operator_t` | client → menu | Модель T: `terror`, `leet`, `arctic` или `guerilla` |
| `cse_operator_ct` | client → menu | Модель CT: `urban`, `gsg9`, `sas` или `gign` |
| `cse_skin` | menu → client | Экипировать скин с повторной проверкой уровня или сбросить слот через `default` |
| `cse_operator` | menu → client | Сохранить предпочтение для стороны |

При первом появлении SteamID загружается его профиль. Если игрок менял персонализацию в главном меню
в текущем запуске до подключения, текущие `equipped`, `operator_t` и `operator_ct` переносятся из
локального профиля. Без такого изменения сохранённая персонализация SteamID остаётся источником правды.

## Методы

| Метод | Назначение |
|-------|------------|
| `CSE_OperatorCount()` / `CSE_OperatorModel()` / `CSE_OperatorLabel()` / `CSE_OperatorIndex()` | Общий каталог и поиск оперативников для `client.dll` и `menu.dll` |
| `CSE_RefreshProfileIdentity()` | Загружает профиль появившегося SteamID и переносит изменённую до подключения локальную персонализацию |
| `CSESkinListModel::Update()` | Читает полный каталог `CseCosmetics` и текущий уровень |
| `CSE_CurrentLevel()` / `CSE_IsSkinEquipped()` | Читает уровень из cvar и считает отсутствующую запись оружия выбором стандартного скина |
| `CSESkinListModel::GetCellText()` / `GetCellColors()` | Показывает название, уровень и состояние; затемняет заблокированные строки |
| `CSESkinListModel::OnActivateEntry()` | Передаёт двойной клик/Enter в экипировку строки |
| `CMenuPersonalization::_Init()` / `Reload()` | Строит экран и синхронизирует его с профильными cvar при открытии |
| `CMenuPersonalization::UpdateLevelLabel()` | Обновляет подпись текущего уровня после синхронизации профиля |
| `CMenuPersonalization::EquipSkin()` / `EquipSelectedSkin()` | Проверяет доступность строки и вызывает `cse_skin` |
| `CMenuPersonalization::ShowOperator()` | Загружает 3D-модель или резервный TGA-preview |
| `CMenuPersonalization::SelectTerroristOperator()` / `SelectCTOperator()` | Обновляет preview и вызывает `cse_operator` |
| `CSE_PreferredJoinClass()` / `CSE_SelectPreferredClass()` | Преобразует сохранённую модель в `joinclass` и пропускает ручной class-menu |

## Ограничения

- Собственный viewmodel, player model и world model по умолчанию разрешаются клиентом по локальному loadout;
  для weaponbox, летящих гранат и установленной C4 совместимый сервер передаёт компактный encoded variant,
  а путь модели по-прежнему остаётся локальным каталогом клиента. Явный variant предмета или игрока не
  зависит от unlock-уровня наблюдателя.
- Экран показывает только четыре стандартных класса каждой стороны. Condition Zero-классы
  `militia`/`spetsnaz` не сохраняются, потому что их доступность определяется сервером для конкретного матча.
