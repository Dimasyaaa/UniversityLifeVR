extends Node
## Хранит прогресс квестов и завершает их по событиям от локаций.

signal quest_started(quest_id: StringName)
signal quest_completed(quest_id: StringName)

@export var quest_definitions: Array[QuestDefinition] = []
@export var initial_quests: Array[StringName] = []

var _definitions: Dictionary[StringName, QuestDefinition] = {}
var _active_quest_ids: Array[StringName] = []
var _completed_quest_ids: Array[StringName] = []
var _quest_progress: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	for definition: QuestDefinition in quest_definitions:
		if definition != null:
			_definitions[definition.quest_id] = definition
	for quest_id: StringName in initial_quests:
		give_quest(quest_id)


func give_quest(quest_id: StringName) -> bool:
	if not _definitions.has(quest_id):
		push_warning("QuestManager: неизвестный квест: %s" % quest_id)
		return false
	if is_quest_active(quest_id) or is_quest_completed(quest_id):
		return false
	var progress: Dictionary = {}
	for event_id: StringName in _definitions[quest_id].required_events:
		progress[event_id] = 0
	_quest_progress[quest_id] = progress
	_active_quest_ids.append(quest_id)
	quest_started.emit(quest_id)
	return true


func is_quest_active(quest_id: StringName) -> bool:
	return _active_quest_ids.has(quest_id)


func get_active_quest_ids() -> Array[StringName]:
	return _active_quest_ids.duplicate()


func get_quest_definition(quest_id: StringName) -> QuestDefinition:
	return _definitions.get(quest_id)


func is_quest_completed(quest_id: StringName) -> bool:
	return _completed_quest_ids.has(quest_id)


func get_completed_quest_ids() -> Array[StringName]:
	return _completed_quest_ids.duplicate()


func get_quest_progress(quest_id: StringName) -> Dictionary:
	return _quest_progress.get(quest_id, {}).duplicate()


func notify_event(event_id: StringName) -> void:
	# Копия списка позволяет завершать квесты во время обхода.
	for quest_id: StringName in _active_quest_ids.duplicate():
		if not is_quest_active(quest_id):
			continue
		var definition: QuestDefinition = _definitions[quest_id]
		if not definition.required_events.has(event_id):
			continue
		var progress: Dictionary = _quest_progress[quest_id]
		progress[event_id] = mini(int(progress.get(event_id, 0)) + 1, definition.required_events[event_id])
		if _all_conditions_met(quest_id):
			_complete_quest(quest_id)


func _all_conditions_met(quest_id: StringName) -> bool:
	var definition: QuestDefinition = _definitions[quest_id]
	var progress: Dictionary = _quest_progress[quest_id]
	for event_id: StringName in definition.required_events:
		if int(progress.get(event_id, 0)) < definition.required_events[event_id]:
			return false
	return true


func _complete_quest(quest_id: StringName) -> void:
	# Сначала отмечаем завершение, чтобы повторное событие не выдало награду снова.
	_active_quest_ids.erase(quest_id)
	_completed_quest_ids.append(quest_id)
	var rewards: Dictionary[StringName, int] = _definitions[quest_id].stat_rewards
	for stat_name: StringName in rewards:
		GameStateManager.change_stat(stat_name, rewards[stat_name])
	quest_completed.emit(quest_id)
