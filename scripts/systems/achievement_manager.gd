extends Node
## Проверяет условия и один раз открывает каждое достижение.

signal achievement_unlocked(achievement_id: StringName)

@export var achievement_definitions: Array[AchievementDefinition] = []

var _definitions: Dictionary[StringName, AchievementDefinition] = {}
var _unlocked_ids: Array[StringName] = []
var _event_started_at: Dictionary[StringName, int] = {}


func _ready() -> void:
	for definition: AchievementDefinition in achievement_definitions:
		if definition != null:
			_definitions[definition.achievement_id] = definition
	StatisticsManager.money_earned_changed.connect(_on_stat_value_changed)
	StatisticsManager.location_visited.connect(_on_location_visited)
	TimeManager.time_changed.connect(_on_stat_value_changed)
	QuestManager.event_received.connect(_on_event_received)
	_check_achievements()


func unlock_achievement(achievement_id: StringName) -> bool:
	if not _definitions.has(achievement_id):
		push_warning("AchievementManager: неизвестное достижение: %s" % achievement_id)
		return false
	if is_achievement_unlocked(achievement_id):
		return false
	_unlocked_ids.append(achievement_id)
	achievement_unlocked.emit(achievement_id)
	return true


func is_achievement_unlocked(achievement_id: StringName) -> bool:
	return _unlocked_ids.has(achievement_id)


func get_unlocked_achievement_ids() -> Array[StringName]:
	return _unlocked_ids.duplicate()


func get_achievement_definition(achievement_id: StringName) -> AchievementDefinition:
	return _definitions.get(achievement_id)


func get_save_data() -> Dictionary:
	var elapsed_times: Dictionary[StringName, int] = {}
	var now: int = Time.get_ticks_msec()
	# В файл записываем длительность, а не счётчик текущего запуска Godot.
	for achievement_id: StringName in _event_started_at:
		if not is_achievement_unlocked(achievement_id):
			elapsed_times[achievement_id] = now - _event_started_at[achievement_id]
	return {
		"unlocked_ids": _unlocked_ids.duplicate(),
		"timed_event_elapsed_ms": elapsed_times,
	}


func restore_save_data(data: Dictionary) -> void:
	_unlocked_ids.assign(data["unlocked_ids"])
	_event_started_at.clear()
	var now: int = Time.get_ticks_msec()
	for achievement_id: StringName in data["timed_event_elapsed_ms"]:
		# Время вне игры не добавляется к сохранённой длительности.
		_event_started_at[achievement_id] = now - data["timed_event_elapsed_ms"][achievement_id]


func _on_stat_value_changed(_value: int) -> void:
	_check_achievements()


func _on_location_visited(_location_id: StringName, _visits: int) -> void:
	_check_achievements()


func _check_achievements() -> void:
	for definition: AchievementDefinition in _definitions.values():
		if not is_achievement_unlocked(definition.achievement_id) and _condition_met(definition):
			unlock_achievement(definition.achievement_id)


func _condition_met(definition: AchievementDefinition) -> bool:
	match definition.condition:
		AchievementDefinition.Condition.MONEY_EARNED:
			return StatisticsManager.get_money_earned() >= definition.threshold
		AchievementDefinition.Condition.LOCATION_VISITS:
			return StatisticsManager.get_location_visit_count(definition.location_id) >= definition.threshold
		AchievementDefinition.Condition.LOCATION_TIME:
			return StatisticsManager.get_location_time_seconds(definition.location_id) > definition.threshold
	return false


func _on_event_received(event_id: StringName) -> void:
	for definition: AchievementDefinition in _definitions.values():
		var achievement_id: StringName = definition.achievement_id
		if is_achievement_unlocked(achievement_id):
			continue
		if definition.condition == AchievementDefinition.Condition.EVENT:
			if event_id == definition.event_id:
				unlock_achievement(achievement_id)
		elif definition.condition == AchievementDefinition.Condition.TIMED_EVENT:
			if event_id == definition.start_event_id:
				_event_started_at[achievement_id] = Time.get_ticks_msec()
			elif event_id == definition.event_id and _event_started_at.has(achievement_id):
				var elapsed_ms: int = Time.get_ticks_msec() - _event_started_at[achievement_id]
				if elapsed_ms <= roundi(definition.threshold * 1000.0):
					unlock_achievement(achievement_id)
