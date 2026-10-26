# Архитектура проекта "VR-Симулятор жизни студента"

## 1. Правила Git
- Основная ветка для разработки: `dev`. Ветка `main` только для релизов.
- Каждый модуль разрабатывается в ветке `feature/module-X-название` (например, `feature/module-1-dorm`).
- Запрещен `git push --force` в `dev` и `main`.
- Перед мержем в `dev` убедитесь, что ваша сцена запускается и не выдает ошибок в консоли.

## 2. Именование и Точки перехода (Scene Manager)
- Точки входа/выхода в локациях ВСЕГДА называются `Marker3D`/`Area3D` с именами:
  - `SpawnPoint` (Marker3D — точка появления игрока в этой локации, Y ≈ 1.31 — уровень головы)
  - `TransitionTo_ИмяЛокации` (Area3D — зона выхода, например `TransitionTo_Cafeteria`)
- Зона перехода использует скрипт `res://scripts/core/transition_point.gd`:
  проп `target_scene` (путь к .tscn), `target_spawn` (имя Marker3D в цели).
  Если целевая сцена ещё не собрана — игрок отталкивается обратно, показывается подсказка.
- Сцены локаций сохраняются как: `res://scenes/locations/module_XX_name.tscn`

## 3. Группы физики и Коллизии (КРИТИЧНО ВАЖНО)
Чтобы избежать ошибок назначения `collision_layer` на `MeshInstance3D`:
- Никогда не добавляйте `CollisionShape3D` напрямую в `MeshInstance3D`.
- Для интерактивных объектов используйте иерархию:
  `StaticBody3D` (или `Area3D`) → `CollisionShape3D` + `MeshInstance3D` (как дочерний).
- Группы коллизий (Collision Layers/Masks):
  - Layer 1 (бит 1): World (стены, пол, неинтерактивные объекты)
  - Layer 2 (бит 2): Interactable (зоны взаимодействия — только они!)
  - Layer 3 (бит 4): Player (тело игрока: `collision_layer = 4`, `collision_mask = 7`)
- Указка игрока (`FunctionPointer` на правом контроллере) имеет `collision_mask = 2`,
  `collide_with_areas = true`, `show_laser = COLLIDE` — лазер виден только над интерактивом.
- Десктоп-тест (клавиша E) использует тот же рейкаст со слоем 2.

## 4. API Менеджеров (Autoload)

### HintSystem (`res://scripts/core/hint_system.gd`)
- `show_hint(text: String, duration := 2.5)` — временная подсказка (Label3D перед камерой, видна и в VR).
- `show_prompt(text)` / `hide_prompt()` — постоянная подсказка при наведении указкой.
- Сигнал: `hint_shown(text, duration)`.

### GameStateManager (`res://scripts/core/game_state_manager.gd`)
- Показатели: `energy, satiety, knowledge, mood, health, money` (0–100, money — до 99999).
- `change_stat(stat_name, delta)` / `get_stat(stat_name)` / `set_stat(name, value)` (кламп + автосейв).
- Сигнал: `player_stat_changed(stat_name, new_value)`.
- Игровое время: старт **06:50**, часы идут только после `set_awake(true)` (1 игровая мин = 2 реальные сек, настройка `seconds_per_game_minute`).
  `game_minutes`, `get_time_string()`, `add_time(min)`, `start_clock()/stop_clock()`, сигнал `time_changed(hours, minutes)`.
- Флаги квестов: `get_flag(name)` / `set_flag(name, value)` (сигнал `flag_changed`).
- Флаги Модуля 1: `awake`, `has_breakfast_products`, `breakfast_made`, `dressed`.
- Сохранение: `save_game()` / `load_game()` → `user://game_state.cfg` (автосейв при изменении и закрытии окна).

### QuestManager (`res://scripts/core/quest_manager.gd`)
- Квесты (каталог в скрипте): `main_exam, breakfast, library, cafeteria, gym, party, job, robot, checkup, deanery, ducks`.
- `register_quest(id)`, `complete_quest(id)`, `is_quest_completed(id)`, `get_active_quests()`.
- Достижения: `early_bird, bookworm, athlete, party_animal, hard_worker, excellent_student, explorer`;
  `unlock_achievement(id)`, `is_achievement_unlocked(id)`.
- Сигналы: `quest_completed(quest_id)`, `achievement_unlocked(achievement_id)`.
- Прогресс хранится в БД: `user://quest_progress.cfg` (сохраняется между запусками).

### SceneManager (`res://scripts/core/scene_manager.gd`)
- `transition_to(scene_path, spawn_marker_name := "SpawnPoint")` — fade, асинхронная загрузка,
  установка игрока на Marker3D с именем `spawn_marker_name` (группа `player`).
- Сигналы: `transition_started(path)`, `transition_finished(path)`, флаг `is_transitioning`.

## 5. Взаимодействие (Interactable)
- Базовый класс: `InteractableBase` (`res://scripts/core/interactable_base.gd`, наследует **Area3D**).
- Все интерактивные зоны: `Area3D` + `CollisionShape3D`, слой принудительно 2, группа `interactable` — автоматически в `_ready()`.
- В наследниках переопределяйте `_on_interact(source)`; текст при наведении — экспорт `prompt`.
- События VR-указки доставляет godot-xr-tools методом `pointer_event(event)` (реализовано в базе).
- Десктоп: `res://scripts/core/desktop_interact.gd`, действие ввода `interact` (клавиша **E**).
- Группы: `interactable` (зона интерактива), `exit_point` (зона перехода), `player` (корень префаба игрока).

## 6. Модуль 1 — «Комната в общежитии» (готов)
Сцена `res://scenes/locations/RoomDorm/RoomDorm.tscn`, узлы:
| Узел | Скрипт | Механика |
|---|---|---|
| `AlarmClock` | `scripts/RoomDorm/alarm_clock.gd` | Пробуждение: +25 Энергии, старт часов, достижение «Ранняя пташка» (<07:00), подсказка главного квеста |
| `FridgeInteract` | `fridge_interact.gd` | Достать продукты (флаг `has_breakfast_products`) |
| `MicrowaveInteract` | `microwave_interact.gd` | Готовка 3 c → +30 Сытости, квест `breakfast`, +10 игровых минут |
| `ClothesRack/InteractArea` (+ `Shirt1..3`) | `clothes_rack.gd` | Выбор одежды, +5 Настроения (флаг `dressed`) |
| `Bed1Interact`, `Bed2Interact` | `bed_rest.gd` | Сон: +15 Энергии, +30 минут |
| `WindowInteract` | `window_time.gd` | Смена времени суток (пресеты освещения, визуально) |
| `DoorInteract` → `Room/Door` | `door_interact.gd` + `door.gd` | Открытие/закрытие двери |
| `TransitionTo_Transport` | `scripts/core/transition_point.gd` | Выход → `module_02_road.tscn` (зона за дверью, шагом) |
| `SpawnPoint` | Marker3D | Точка появления игрока |

## 7. Инструменты разработки (не для игры)
- `godot --headless --path . -s res://tools/measure.gd` — проверка парсинга всех скриптов + AABB мебели.
- `godot --headless --path . -s res://tools/smoke_test.gd` — функциональный smoke-тест Модуля 1 (24 проверки).
