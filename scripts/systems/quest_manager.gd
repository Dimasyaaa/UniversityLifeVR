extends Node
## Хранит описания квестов и список выданных активных квестов.

signal quest_started(quest_id: StringName)

@export var quest_definitions: Array[QuestDefinition] = []
@export var initial_quests: Array[StringName] = []

var _definitions: Dictionary[StringName, QuestDefinition] = {}
var _active_quest_ids: Array[StringName] = []


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
	if is_quest_active(quest_id):
		return false
	_active_quest_ids.append(quest_id)
	quest_started.emit(quest_id)
	return true


func is_quest_active(quest_id: StringName) -> bool:
	return _active_quest_ids.has(quest_id)


func get_active_quest_ids() -> Array[StringName]:
	return _active_quest_ids.duplicate()


func get_quest_definition(quest_id: StringName) -> QuestDefinition:
	return _definitions.get(quest_id)
