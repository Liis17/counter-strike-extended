# Персонализация — Project Map

Parent: [[CSE/personalization]]

## Карта потока

```text
Main.cpp
  └─ UI_Personalization_Menu
       ├─ CseCosmetics.txt::weapons/variants ──> CSESkinListModel ──> cse_skin
       └─ cse_operator <side> <model> ──> CSEProfile ──> cse_operator_t / cse_operator_ct
                                                        └─ JoinClass.cpp ──> joinclass 1..4
```

## Точки изменения

| Нужно изменить | Источник правды |
|----------------|-----------------|
| Добавить оружейный вариант | `src/cse/cstrike/scripts/CseCosmetics.txt`; модели — через `tools/install_cosmetic_models.ps1` |
| Изменить стандартный список оперативников | `src/cs16-client/3rdparty/mainui_cpp/cse_operators.h` |
| Изменить раскладку экрана | `src/cs16-client/3rdparty/mainui_cpp/menus/Personalization.cpp` |
| Изменить хранение выбора | `src/cs16-client/cl_dll/cse_profile.{h,cpp}` |
| Изменить применение после стороны | `src/cs16-client/3rdparty/mainui_cpp/menus/client/JoinClass.cpp` |

## Инварианты

- Индекс строки в `g_CSEOperators` не является номером класса: отправлять нужно поле `joinClass`.
- `client.dll` повторно валидирует уровень и имя оперативника; данным UI не доверяем.
- При переходе профиля `local → SteamID` локальная персонализация переносится только после изменения
  в текущем запуске; иначе сохранённая персонализация SteamID остаётся источником правды.
- Пустая запись оружия в `equipped` означает стандартный скин.
- `loadout.variant[]` использует стабильные индексы `CSE_WeaponCatalog`; `equipped` остаётся читаемым legacy-отображением.
- Для полноценного варианта должны существовать `v/p/w`-модели; C4 дополнительно требует `w_planted`, а щит —
  все штатные `v/p`-комбинации.
