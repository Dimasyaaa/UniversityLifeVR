extends Node3D
## Локальное состояние комнаты; общий SaveManager вызывает эти методы сам.

const DormAlarm = preload("res://scripts/RoomDorm/alarm_clock.gd")
const DormWakeup = preload("res://scripts/RoomDorm/dorm_wakeup.gd")
const FridgeDoor = preload("res://scripts/RoomDorm/fridge_door.gd")
const BreakfastFood = preload("res://scripts/RoomDorm/breakfast_food.gd")
const DormMicrowave = preload("res://scripts/RoomDorm/microwave.gd")

const FRIDGE_INTERIOR: AABB = AABB(Vector3(-0.46, 0, -0.414), Vector3(0.92, 1.955, 0.5275))

@onready var _alarm: DormAlarm = $AlarmClock
@onready var _wakeup: DormWakeup = $Wakeup
@onready var _fridge: FridgeDoor = $Room/Fridge
@onready var _pizza: BreakfastFood = $BreakfastPizza
@onready var _microwave: DormMicrowave = $Room/Microwave

var _alarm_started: bool = false
var _alarm_disabled: bool = false
var _wakeup_completed: bool = false
var _wakeup_state_restored: bool = false


func _ready() -> void:
	_alarm.switched_off.connect(_on_alarm_switched_off)
	_wakeup.stood_up.connect(_on_stood_up)
	_fridge.door_state_changed.connect(_on_fridge_state_changed)
	_pizza.picked_up.connect(_on_pizza_picked_up)
	_pizza.released.connect(_on_pizza_released)
	_pizza.eaten.connect(_on_pizza_eaten)
	_microwave.setup_food(_pizza)
	_microwave.state_changed.connect(_save_food_state)
	_sync_food_access()
	SceneManager.location_entered.connect(_on_location_entered)
	SaveManager.game_loaded.connect(_on_game_loaded)
	SaveManager.new_game_started.connect(_activate_if_current)


func _on_location_entered(_location_id: StringName) -> void:
	# При загрузке дождёмся восстановления менеджеров и разрешения событий.
	if not SaveManager.is_loading():
		_activate_if_current()


func _physics_process(_delta: float) -> void:
	_sync_food_access()


func _activate_if_current() -> void:
	if SceneManager.get_current_location() != self or SaveManager.is_loading():
		return
	if not _alarm_started:
		# Совместимость с сохранениями, созданными до состояния комнаты.
		var achievement_state: Dictionary = AchievementManager.get_save_data()
		_alarm_disabled = AchievementManager.is_achievement_unlocked(&"early_bird")
		_alarm_started = _alarm_disabled or achievement_state["timed_event_elapsed_ms"].has(&"early_bird")
		if not _alarm_started:
			_alarm_started = true
			QuestManager.notify_event(&"alarm_started")
	_alarm.set_ringing(not _alarm_disabled)
	_wakeup.activate(_wakeup_completed)


func _on_game_loaded() -> void:
	if not _wakeup_state_restored:
		# До добавления пробуждения все старые сохранения создавались стоя.
		_wakeup_completed = true
	_activate_if_current()


func _on_stood_up() -> void:
	if _wakeup_completed:
		return
	_wakeup_completed = true
	SaveManager.save_game.call_deferred()


func _on_alarm_switched_off() -> void:
	if not _alarm_started or _alarm_disabled:
		return
	_alarm_disabled = true
	QuestManager.notify_event(&"alarm_disabled")
	# Состояние комнаты и результат события попадут в один общий файл.
	SaveManager.save_game.call_deferred()


func get_save_data() -> Dictionary:
	# Сначала синхронизируем разогрев, чтобы флаг пиццы и остаток времени совпали.
	var microwave_data: Dictionary = _microwave.get_save_data()
	return {
		"alarm": {"started": _alarm_started, "disabled": _alarm_disabled},
		"wakeup_completed": _wakeup_completed,
		"fridge": _fridge.get_save_data(),
		"foods": {String(_pizza.item_id): _pizza.get_save_data()},
		"microwave": microwave_data,
	}


func restore_save_data(data: Dictionary) -> void:
	var fridge_data: Variant = data.get("fridge", {})
	_fridge.restore_save_data(fridge_data if fridge_data is Dictionary else {})
	var foods: Variant = data.get("foods", {})
	var pizza_data: Variant = foods.get(String(_pizza.item_id), {}) if foods is Dictionary else {}
	_pizza.restore_save_data(pizza_data if pizza_data is Dictionary else {})
	var microwave_data: Variant = data.get("microwave", {})
	_microwave.restore_save_data(microwave_data if microwave_data is Dictionary else {})
	_sync_food_access()
	var completed: Variant = data.get("wakeup_completed", true)
	_wakeup_completed = completed is bool and completed
	_wakeup_state_restored = true
	if _wakeup_completed:
		# location_loaded вызывается под затемнением: разместим игрока до проявления.
		_wakeup.activate(true)
	var alarm_data: Variant = data.get("alarm", {})
	if not alarm_data is Dictionary:
		return
	var started: Variant = alarm_data.get("started", false)
	var disabled: Variant = alarm_data.get("disabled", false)
	_alarm_disabled = disabled is bool and disabled
	_alarm_started = _alarm_disabled or (started is bool and started)
	# Звук включится после location_entered / game_loaded, не под затемнением.
	_alarm.set_ringing(false)


func _on_fridge_state_changed(_opened: bool) -> void:
	_sync_food_access()
	SaveManager.save_game.call_deferred()


func _on_pizza_picked_up(first_time: bool) -> void:
	if first_time:
		QuestManager.give_quest(&"breakfast")
	_save_food_state()


func _on_pizza_released() -> void:
	_sync_food_access()
	_save_food_state()


func _on_pizza_eaten() -> void:
	# +30 Сытости выдаёт только награда существующего квеста.
	QuestManager.notify_event(&"breakfast_eaten")
	_save_food_state()


func _sync_food_access() -> void:
	var inside_fridge: bool = FRIDGE_INTERIOR.has_point(_fridge.to_local(_pizza.global_position))
	var fridge_access: bool = not inside_fridge or (_fridge.is_open and not _fridge.is_moving)
	_pizza.set_pickup_enabled(fridge_access and _microwave.can_pick_up_food())


func _save_food_state() -> void:
	if not SaveManager.is_loading() and not SceneManager.is_transitioning():
		SaveManager.save_game.call_deferred()
