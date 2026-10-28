extends Node3D
## Локальное состояние комнаты; общий SaveManager вызывает эти методы сам.

const DormAlarm = preload("res://scripts/RoomDorm/alarm_clock.gd")
const DormWakeup = preload("res://scripts/RoomDorm/dorm_wakeup.gd")
const FridgeDoor = preload("res://scripts/RoomDorm/fridge_door.gd")
const BreakfastFood = preload("res://scripts/RoomDorm/breakfast_food.gd")
const DormMicrowave = preload("res://scripts/RoomDorm/microwave.gd")
const ClothesRack = preload("res://scripts/RoomDorm/clothes_rack.gd")
const BedRest = preload("res://scripts/RoomDorm/bed_rest.gd")
const WindowTime = preload("res://scripts/RoomDorm/window_time.gd")

const FRIDGE_INTERIOR: AABB = AABB(Vector3(-0.46, 0, -0.414), Vector3(0.92, 1.955, 0.5275))
const ROOM_LAYOUT_VERSION: int = 2
## Области прежней расстановки 5.5 м: однократный перенос предмета вместе с мебелью.
const PREVIOUS_LAYOUT_AREAS: Array[Dictionary] = [
	{"bounds": AABB(Vector3(-2.68, 0, 0.975), Vector3(0.8625, 0.8625, 1.725)), "offset": Vector3(-0.25, 0, 0.25)},
	{"bounds": AABB(Vector3(-1.628505, 0, 1.731368), Vector3(0.797009, 1.2075, 0.737265)), "offset": Vector3(-0.25, 0, 0.25)},
	{"bounds": AABB(Vector3(-2.681617, 0, -2.4), Vector3(0.829617, 1.955, 0.92)), "offset": Vector3(-0.25, 0, -0.25)},
	{"bounds": AABB(Vector3(-2.68, 1.035, -1.36), Vector3(0.797892, 0.345, 0.555833)), "offset": Vector3(-0.25, 0, -0.25)},
	{"bounds": AABB(Vector3(-2.68, 0.989, -1.455833), Vector3(0.7475, 0.046, 0.7475)), "offset": Vector3(-0.25, 0, -0.25)},
	{"bounds": AABB(Vector3(1.503439, 0, 0.3425), Vector3(1.196562, 0.785833, 2.3575)), "offset": Vector3(0.25, 0, 0.25)},
	{"bounds": AABB(Vector3(0.3425, 0, -2.7), Vector3(2.3575, 0.785833, 1.196562)), "offset": Vector3(0.25, 0, -0.25)},
	{"bounds": AABB(Vector3(-2.680044, -0.000062, -0.30007), Vector3(1.009953, 1.954994, 0.932121)), "offset": Vector3(-0.25, 0, 0)},
	{"bounds": AABB(Vector3(-1.631667, 1.2765, -0.742476), Vector3(0.06325, 0.55775, 1.817)), "offset": Vector3(-0.25, 0, 0)},
]

@onready var _alarm: DormAlarm = $AlarmClock
@onready var _wakeup: DormWakeup = $Wakeup
@onready var _fridge: FridgeDoor = $Room/Fridge
@onready var _pizza: BreakfastFood = $BreakfastPizza
@onready var _microwave: DormMicrowave = $Room/Microwave
@onready var _clothes: ClothesRack = $ClothesRack
@onready var _bed: BedRest = $Room/Bed
@onready var _window: WindowTime = $WindowTime

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
	_clothes.outfit_changed.connect(_on_outfit_changed)
	_bed.setup(_wakeup, $BedRestScreen)
	_bed.rested.connect(_on_bed_rested)
	_window.setup($WorldEnvironment.environment, $WindowStreet, _wakeup)
	_window.waited.connect(_on_window_waited)
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
		"layout_version": ROOM_LAYOUT_VERSION,
		"alarm": {"started": _alarm_started, "disabled": _alarm_disabled},
		"wakeup_completed": _wakeup_completed,
		"fridge": _fridge.get_save_data(),
		"foods": {String(_pizza.item_id): _pizza.get_save_data()},
		"microwave": microwave_data,
		"clothes": _clothes.get_save_data(),
	}


func restore_save_data(data: Dictionary) -> void:
	var fridge_data: Variant = data.get("fridge", {})
	_fridge.restore_save_data(fridge_data if fridge_data is Dictionary else {})
	var foods: Variant = data.get("foods", {})
	var pizza_data: Variant = foods.get(String(_pizza.item_id), {}) if foods is Dictionary else {}
	var food_data: Dictionary = pizza_data if pizza_data is Dictionary else {}
	var layout_version: Variant = data.get("layout_version", 1)
	if not (layout_version is int and layout_version >= ROOM_LAYOUT_VERSION):
		food_data = _migrate_food_layout(food_data)
	_pizza.restore_save_data(food_data)
	var microwave_data: Variant = data.get("microwave", {})
	_microwave.restore_save_data(microwave_data if microwave_data is Dictionary else {})
	var clothes_data: Variant = data.get("clothes", {})
	_clothes.restore_save_data(clothes_data if clothes_data is Dictionary else {})
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


func _migrate_food_layout(data: Dictionary) -> Dictionary:
	var saved_pose: Variant = data.get("transform")
	if not saved_pose is Transform3D or not saved_pose.is_finite():
		return data
	var pose: Transform3D = saved_pose
	for area: Dictionary in PREVIOUS_LAYOUT_AREAS:
		var old_bounds: AABB = area["bounds"]
		if old_bounds.grow(0.03).has_point(pose.origin):
			var offset: Vector3 = area["offset"]
			pose.origin += offset
			var migrated: Dictionary = data.duplicate()
			migrated["transform"] = pose
			return migrated
	# Свободный предмет в проходе остаётся на сохранённом месте.
	return data


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


func _on_outfit_changed(_item_id: StringName) -> void:
	if not SaveManager.is_loading() and not SceneManager.is_transitioning():
		SaveManager.save_game.call_deferred()


func _on_bed_rested() -> void:
	if not SaveManager.is_loading() and not SceneManager.is_transitioning():
		SaveManager.save_game.call_deferred()


func _on_window_waited() -> void:
	if not SaveManager.is_loading() and not SceneManager.is_transitioning():
		SaveManager.save_game.call_deferred()


func _sync_food_access() -> void:
	var inside_fridge: bool = FRIDGE_INTERIOR.has_point(_fridge.to_local(_pizza.global_position))
	var fridge_access: bool = not inside_fridge or (_fridge.is_open and not _fridge.is_moving)
	_pizza.set_pickup_enabled(fridge_access and _microwave.can_pick_up_food())


func _save_food_state() -> void:
	if not SaveManager.is_loading() and not SceneManager.is_transitioning():
		SaveManager.save_game.call_deferred()
