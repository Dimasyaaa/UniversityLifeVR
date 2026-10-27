extends Node3D
## Локальное состояние комнаты; общий SaveManager вызывает эти методы сам.

const DormAlarm = preload("res://scripts/RoomDorm/alarm_clock.gd")
const DormWakeup = preload("res://scripts/RoomDorm/dorm_wakeup.gd")

@onready var _alarm: DormAlarm = $AlarmClock
@onready var _wakeup: DormWakeup = $Wakeup

var _alarm_started: bool = false
var _alarm_disabled: bool = false
var _wakeup_completed: bool = false
var _wakeup_state_restored: bool = false


func _ready() -> void:
	_alarm.switched_off.connect(_on_alarm_switched_off)
	_wakeup.stood_up.connect(_on_stood_up)
	SceneManager.location_entered.connect(_on_location_entered)
	SaveManager.game_loaded.connect(_on_game_loaded)
	SaveManager.new_game_started.connect(_activate_if_current)


func _on_location_entered(_location_id: StringName) -> void:
	# При загрузке дождёмся восстановления менеджеров и разрешения событий.
	if not SaveManager.is_loading():
		_activate_if_current()


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
	return {
		"alarm": {"started": _alarm_started, "disabled": _alarm_disabled},
		"wakeup_completed": _wakeup_completed,
	}


func restore_save_data(data: Dictionary) -> void:
	var completed: Variant = data.get("wakeup_completed", true)
	_wakeup_completed = completed is bool and completed
	_wakeup_state_restored = true
	var alarm_data: Variant = data.get("alarm", {})
	if not alarm_data is Dictionary:
		return
	var started: Variant = alarm_data.get("started", false)
	var disabled: Variant = alarm_data.get("disabled", false)
	_alarm_disabled = disabled is bool and disabled
	_alarm_started = _alarm_disabled or (started is bool and started)
	# Звук включится после location_entered / game_loaded, не под затемнением.
	_alarm.set_ringing(false)
