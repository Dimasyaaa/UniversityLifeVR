extends Node
## Реестр локаций и замена комнаты без пересоздания игрока.

signal transition_started(location_id: StringName)
signal location_changed(location_id: StringName, spawn_name: StringName)
signal location_entered(location_id: StringName)
signal transition_failed(location_id: StringName, reason: String)

const Player = preload("res://scripts/player/player.gd")

@export var initial_locations: Dictionary[StringName, String] = {}
@export_range(0.0, 2.0, 0.05) var fade_duration: float = 1.0

@onready var _fade: XRToolsFade = $TransitionFade

var _locations: Dictionary[StringName, String] = {}
var _location_root: Node3D
var _player: Player
var _current_location: Node3D
var _current_location_id: StringName = &""
var _transitioning: bool = false
var _request_number: int = 0
var _movement_was_enabled: bool = true
var _fade_level: float = 0.0
var _fade_tween: Tween


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
	location_entered.emit(location_id)
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
	_fade_to(1.0, _replace_after_black.bind(location_id, spawn_name, request_number))


func _replace_after_black(location_id: StringName, spawn_name: StringName, request_number: int) -> void:
	# XR Tools обновит материал в _process; даём полностью чёрному кадру отрисоваться.
	await get_tree().process_frame
	await get_tree().process_frame
	if request_number != _request_number:
		return
	var path: String = _locations[location_id]
	var packed_scene: PackedScene
	var reason: String = ""
	var error: Error = ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK:
		reason = "Не удалось начать загрузку локации: %s" % error_string(error)
	else:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Между проверками продолжаются отрисовка и отслеживание головы.
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path)
		# Завершаем начатый запрос даже при закрытии Main, не блокируя поток ожиданием.
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			packed_scene = ResourceLoader.load_threaded_get(path) as PackedScene
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path)
			reason = "Не удалось загрузить сцену локации."
		else:
			reason = "Запрос фоновой загрузки локации недействителен."
	if request_number != _request_number:
		return
	if reason.is_empty():
		reason = _replace_location(location_id, spawn_name, packed_scene)
	if request_number != _request_number:
		return
	_fade_to(0.0, _finish_transition.bind(location_id, spawn_name, reason, request_number))


func _replace_location(location_id: StringName, spawn_name: StringName, packed_scene: PackedScene) -> String:
	if not _context_is_ready():
		return "Игрок или локация больше не доступны."
	if packed_scene == null or not packed_scene.can_instantiate():
		return "Не удалось загрузить сцену локации."
	var instance: Node = packed_scene.instantiate()
	var next_location: Node3D = instance as Node3D
	if next_location == null or _contains_player_or_camera(next_location):
		instance.free()
		return "Нужна локация Node3D без игрока, XROrigin3D и активной камеры."
	var spawn: Marker3D = next_location.get_node_or_null(NodePath(String(spawn_name))) as Marker3D
	if spawn == null:
		next_location.free()
		return "В локации нет точки Marker3D: %s" % spawn_name
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
		return "Не удалось разместить игрока у точки появления."
	_current_location = next_location
	_current_location_id = location_id
	previous_location.queue_free()
	return ""


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


func _fade_to(level: float, finished: Callable) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	if fade_duration <= 0.0:
		_set_fade_level(level)
		finished.call_deferred()
		return
	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_method(_set_fade_level, _fade_level, level, fade_duration)
	_fade_tween.tween_callback(finished)


func _set_fade_level(level: float) -> void:
	_fade_level = clampf(level, 0.0, 1.0)
	_fade.set_fade_level(self, Color(0, 0, 0, _fade_level))


func _finish_transition(location_id: StringName, spawn_name: StringName, reason: String, request_number: int) -> void:
	if request_number != _request_number:
		return
	_fade_tween = null
	# Удаляем только запрос SceneManager, не затрагивая другие эффекты XR Tools.
	_set_fade_level(0.0)
	if is_instance_valid(_player):
		_player.set_movement_enabled(_movement_was_enabled)
	_transitioning = false
	if reason.is_empty():
		location_entered.emit(location_id)
		location_changed.emit(location_id, spawn_name)
	else:
		push_warning("SceneManager: %s" % reason)
		transition_failed.emit(location_id, reason)


func _reject(reason: String) -> bool:
	push_warning("SceneManager: %s" % reason)
	return false


func _clear_context() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_set_fade_level(0.0)
	if _transitioning and is_instance_valid(_player):
		_player.set_movement_enabled(_movement_was_enabled)
	_request_number += 1
	_transitioning = false
	_location_root = null
	_player = null
	_current_location = null
	_current_location_id = &""
