extends Node
## Запуск и завершение событий дня. Каждое событие запускается один раз за день.

signal event_started(event_id: StringName)
signal event_finished(event_id: StringName)

@export var event_definitions: Array[RandomEventDefinition] = []

var _definitions: Dictionary[StringName, RandomEventDefinition] = {}
var _active_event_ids: Array[StringName] = []
var _finished_event_ids: Array[StringName] = []


func _ready() -> void:
	for definition: RandomEventDefinition in event_definitions:
		if definition != null:
			_definitions[definition.event_id] = definition


func start_event(event_id: StringName) -> bool:
	if not _definitions.has(event_id):
		push_warning("RandomEventManager: неизвестное событие: %s" % event_id)
		return false
	if is_event_active(event_id) or is_event_finished(event_id):
		return false
	_active_event_ids.append(event_id)
	event_started.emit(event_id)
	return true


func finish_event(event_id: StringName) -> bool:
	if not is_event_active(event_id):
		return false
	_active_event_ids.erase(event_id)
	_finished_event_ids.append(event_id)
	event_finished.emit(event_id)
	return true


func is_event_active(event_id: StringName) -> bool:
	return _active_event_ids.has(event_id)


func is_event_finished(event_id: StringName) -> bool:
	return _finished_event_ids.has(event_id)


func get_active_event_ids() -> Array[StringName]:
	return _active_event_ids.duplicate()


func get_finished_event_ids() -> Array[StringName]:
	return _finished_event_ids.duplicate()


func get_event_definition(event_id: StringName) -> RandomEventDefinition:
	return _definitions.get(event_id)
