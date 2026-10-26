extends Node
## Хранит текущие показатели. Локации изменяют их через публичные методы.

signal player_stat_changed(stat_name: StringName, value: int)
signal money_earned(amount: int)

@export_group("Initial Stats")
@export_range(0, 100, 1) var initial_energy: int = 80
@export_range(0, 100, 1) var initial_satiety: int = 50
@export_range(0, 100, 1) var initial_knowledge: int = 0
@export var initial_money: int = 200
@export_range(0, 100, 1) var initial_mood: int = 70
@export_range(0, 100, 1) var initial_health: int = 100

var _stats: Dictionary[StringName, int] = {}


func _ready() -> void:
	reset_stats()


func get_stat(stat_name: StringName) -> int:
	if not _stats.has(stat_name):
		push_warning("Неизвестный показатель: %s" % stat_name)
		return 0
	return _stats[stat_name]


func set_stat(stat_name: StringName, value: int) -> void:
	if not _stats.has(stat_name):
		push_warning("Неизвестный показатель: %s" % stat_name)
		return
	var new_value: int = _limit_value(stat_name, value)
	if _stats[stat_name] == new_value:
		return
	_stats[stat_name] = new_value
	player_stat_changed.emit(stat_name, new_value)


func change_stat(stat_name: StringName, amount: int) -> void:
	if not _stats.has(stat_name):
		push_warning("Неизвестный показатель: %s" % stat_name)
		return
	set_stat(stat_name, _stats[stat_name] + amount)
	if stat_name == &"money" and amount > 0:
		money_earned.emit(amount)


func get_stats() -> Dictionary[StringName, int]:
	# Внешний код получает копию, чтобы не менять состояние в обход методов.
	return _stats.duplicate()


func reset_stats() -> void:
	var previous_stats: Dictionary[StringName, int] = _stats
	_stats = {
		&"energy": initial_energy,
		&"satiety": initial_satiety,
		&"knowledge": initial_knowledge,
		&"money": initial_money,
		&"mood": initial_mood,
		&"health": initial_health,
	}
	for stat_name: StringName in _stats:
		_stats[stat_name] = _limit_value(stat_name, _stats[stat_name])
	# Сначала восстанавливаем все значения, затем уведомляем подписчиков.
	for stat_name: StringName in _stats:
		if previous_stats.has(stat_name) and previous_stats[stat_name] != _stats[stat_name]:
			player_stat_changed.emit(stat_name, _stats[stat_name])


func _limit_value(stat_name: StringName, value: int) -> int:
	if stat_name == &"money":
		return maxi(0, value)
	return clampi(value, 0, 100)
