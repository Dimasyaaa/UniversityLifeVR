extends Node
## Хранит пути зарегистрированных локаций. Переходы будут добавлены отдельно.

@export var initial_locations: Dictionary[StringName, String] = {}

var _locations: Dictionary[StringName, String] = {}


func _ready() -> void:
	for location_id: StringName in initial_locations:
		register_location(location_id, initial_locations[location_id])


func register_location(location_id: StringName, scene_path: String) -> bool:
	if String(location_id).strip_edges().is_empty():
		push_warning("SceneManager: идентификатор локации не должен быть пустым.")
		return false
	if _locations.has(location_id):
		push_warning("SceneManager: локация уже зарегистрирована: %s" % location_id)
		return false
	var path: String = scene_path.simplify_path()
	if not path.begins_with("res://scenes/locations/") or path.get_extension() not in ["tscn", "scn"]:
		push_warning("SceneManager: ожидается сцена в res://scenes/locations/: %s" % scene_path)
		return false
	if not ResourceLoader.exists(path, "PackedScene"):
		push_warning("SceneManager: сцена локации не найдена: %s" % path)
		return false
	# Проверяем ресурс синхронно, не создавая узлы локации.
	var scene: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null or not scene.can_instantiate():
		push_warning("SceneManager: ресурс не содержит готовую сцену: %s" % path)
		return false
	_locations[location_id] = path
	return true


func has_location(location_id: StringName) -> bool:
	return _locations.has(location_id)


func get_location_path(location_id: StringName) -> String:
	if not _locations.has(location_id):
		push_warning("SceneManager: неизвестная локация: %s" % location_id)
		return ""
	return _locations[location_id]
