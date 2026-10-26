extends Node
## Реестр локаций и замена комнаты без пересоздания игрока.

signal transition_started(location_id: StringName)
signal location_changed(location_id: StringName, spawn_name: StringName)
signal transition_failed(location_id: StringName, reason: String)

const Player = preload("res://scripts/player/player.gd")

@export var initial_locations: Dictionary[StringName, String] = {}

var _locations: Dictionary[StringName, String] = {}
var _location_root: Node3D
var _player: Player
var _current_location: Node3D
var _current_location_id: StringName = &""
var _transitioning: bool = false
var _request_number: int = 0
var _movement_was_enabled: bool = true


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


func setup(location_root: Node3D, player: Player, current_location: Node3D, location_id: StringName) -> bool:
	if is_instance_valid(_location_root):
		return _reject("Контейнер локаций уже подключён.")
	for node: Node in [location_root, player, current_location]:
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion():
			return _reject("Для подключения нужны действительные узлы в дереве сцены.")
	if not player.is_node_ready() or location_root.is_ancestor_of(player) or player.is_ancestor_of(location_root):
		return _reject("Готовый игрок должен находиться вне контейнера локаций.")
	if location_root.get_child_count() != 1 or current_location.get_parent() != location_root:
		return _reject("В контейнере должна находиться одна начальная локация.")
	if not has_location(location_id) or current_location.scene_file_path != _locations[location_id]:
		return _reject("Начальная локация не соответствует записи в реестре.")
	if _contains_player_or_camera(current_location):
		return _reject("Локация не должна содержать игрока, XROrigin3D или активную камеру.")
	_location_root = location_root
	_player = player
	_current_location = current_location
	_current_location_id = location_id
	_location_root.tree_exiting.connect(_clear_context, CONNECT_ONE_SHOT)
	return true


func get_current_location_id() -> StringName:
	return _current_location_id


func is_transitioning() -> bool:
	return _transitioning


func change_location(location_id: StringName, spawn_name: StringName = &"Spawn_Default") -> bool:
	# true означает, что запрос принят. Итог приходит отдельным сигналом.
	if _transitioning:
		return _reject("Переход уже выполняется.")
	if not _context_is_ready():
		return _reject("Сначала нужно подключить Main через setup().")
	if not has_location(location_id):
		return _reject("Неизвестная локация: %s" % location_id)
	var marker_name: String = String(spawn_name)
	if marker_name.is_empty() or marker_name.validate_node_name() != marker_name:
		return _reject("Нужно имя Marker3D, расположенного непосредственно в корне локации.")
	_transitioning = true
	_request_number += 1
	_movement_was_enabled = _player.is_movement_enabled()
	_player.set_movement_enabled(false)
	_perform_transition.call_deferred(location_id, spawn_name, _request_number)
	transition_started.emit(location_id)
	return true


func _perform_transition(location_id: StringName, spawn_name: StringName, request_number: int) -> void:
	# Запрос от уже закрытого Main не должен менять новый экземпляр Main.
	if request_number != _request_number:
		return
	if not _context_is_ready():
		_fail_transition(location_id, "Игрок или локация больше не доступны.")
		return
	var packed_scene: PackedScene = ResourceLoader.load(_locations[location_id], "PackedScene") as PackedScene
	if packed_scene == null or not packed_scene.can_instantiate():
		_fail_transition(location_id, "Не удалось загрузить сцену локации.")
		return
	var instance: Node = packed_scene.instantiate()
	var next_location: Node3D = instance as Node3D
	if next_location == null or _contains_player_or_camera(next_location):
		instance.free()
		_fail_transition(location_id, "Нужна локация Node3D без игрока, XROrigin3D и активной камеры.")
		return
	var spawn: Marker3D = next_location.get_node_or_null(NodePath(String(spawn_name))) as Marker3D
	if spawn == null:
		next_location.free()
		_fail_transition(location_id, "В локации нет точки Marker3D: %s" % spawn_name)
		return
	# До этого места текущая комната и удерживаемые предметы не менялись.
	_player.release_held_objects()
	var previous_location: Node3D = _current_location
	_location_root.remove_child(previous_location)
	_location_root.add_child(next_location)
	# Старую комнату сохраняем до успешного размещения для возврата при ошибке.
	if not is_instance_valid(spawn) or spawn.is_queued_for_deletion() or not _player.place_at_spawn(spawn):
		_location_root.remove_child(next_location)
		next_location.queue_free()
		_location_root.add_child(previous_location)
		_fail_transition(location_id, "Не удалось разместить игрока у точки появления.")
		return
	_current_location = next_location
	_current_location_id = location_id
	previous_location.queue_free()
	_player.set_movement_enabled(_movement_was_enabled)
	_transitioning = false
	location_changed.emit(location_id, spawn_name)


func _context_is_ready() -> bool:
	for node: Node in [_location_root, _player, _current_location]:
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion():
			return false
	return _player.is_node_ready() and _current_location.get_parent() == _location_root


func _contains_player_or_camera(location: Node3D) -> bool:
	var nodes: Array[Node] = [location]
	nodes.append_array(location.find_children("*", "", true, false))
	for node: Node in nodes:
		if node is Player or node is XROrigin3D:
			return true
		if node is Camera3D and node.current:
			return true
	return false


func _fail_transition(location_id: StringName, reason: String) -> void:
	if is_instance_valid(_player):
		_player.set_movement_enabled(_movement_was_enabled)
	_transitioning = false
	push_warning("SceneManager: %s" % reason)
	transition_failed.emit(location_id, reason)


func _reject(reason: String) -> bool:
	push_warning("SceneManager: %s" % reason)
	return false


func _clear_context() -> void:
	if _transitioning and is_instance_valid(_player):
		_player.set_movement_enabled(_movement_was_enabled)
	_request_number += 1
	_transitioning = false
	_location_root = null
	_player = null
	_current_location = null
	_current_location_id = &""
