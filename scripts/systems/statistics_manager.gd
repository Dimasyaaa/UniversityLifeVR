extends Node
## Статистика дня: заработанные деньги, посещения и время в локациях.

signal money_earned_changed(total: int)
signal location_visited(location_id: StringName, visits: int)

var _money_earned: int = 0
var _location_visits: Dictionary[StringName, int] = {}
var _location_time_seconds: Dictionary[StringName, float] = {}
var _last_location_id: StringName = &""
var _location_entered_at: float = 0.0


func _ready() -> void:
	GameStateManager.money_earned.connect(_on_money_earned)
	SceneManager.location_entered.connect(_on_location_entered)


func get_money_earned() -> int:
	return _money_earned


func get_location_visit_count(location_id: StringName) -> int:
	return _location_visits.get(location_id, 0)


func get_visited_location_ids() -> Array[StringName]:
	var location_ids: Array[StringName] = []
	location_ids.assign(_location_visits.keys())
	return location_ids


func get_location_time_seconds(location_id: StringName) -> float:
	var total: float = _location_time_seconds.get(location_id, 0.0)
	if location_id == _last_location_id and location_id != &"":
		total += TimeManager.get_total_seconds() - _location_entered_at
	return total


func get_save_data() -> Dictionary:
	var location_times: Dictionary[StringName, float] = _location_time_seconds.duplicate()
	# Включаем текущий визит, не меняя накопленные значения в игре.
	if _last_location_id != &"":
		location_times[_last_location_id] = get_location_time_seconds(_last_location_id)
	return {
		"money_earned": _money_earned,
		"location_visits": _location_visits.duplicate(),
		"location_time_seconds": location_times,
		"current_location_id": _last_location_id,
	}


func restore_save_data(data: Dictionary) -> void:
	_money_earned = data["money_earned"]
	_location_visits.assign(data["location_visits"])
	_location_time_seconds.assign(data["location_time_seconds"])
	_last_location_id = data["current_location_id"]
	# Время текущего визита уже включено в сохранённые итоги.
	_location_entered_at = TimeManager.get_total_seconds()


func _on_money_earned(amount: int) -> void:
	_money_earned += amount
	money_earned_changed.emit(_money_earned)


func _on_location_entered(location_id: StringName) -> void:
	# Перезагрузка текущей локации не считается повторным посещением.
	if location_id == _last_location_id:
		return
	if _last_location_id != &"":
		_location_time_seconds[_last_location_id] = get_location_time_seconds(_last_location_id)
	_location_entered_at = TimeManager.get_total_seconds()
	_last_location_id = location_id
	_location_visits[location_id] = get_location_visit_count(location_id) + 1
	location_visited.emit(location_id, _location_visits[location_id])
