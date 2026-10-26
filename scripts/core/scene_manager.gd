extends Node

## Менеджер сцен — плавные переходы между локациями (Модуль 7).
## SceneManager.transition_to("res://scenes/locations/module_02_road.tscn")
## После загрузки игрок ставится на Marker3D с именем spawn_marker_name
## (по умолчанию «SpawnPoint»). API описан в ARCHITECTURE.md (§ SceneManager).

signal transition_started(scene_path: String)
signal transition_finished(scene_path: String)

@export var fade_duration: float = 0.4

var is_transitioning: bool = false

var _pending_spawn: String = "SpawnPoint"
var _fade_quad: MeshInstance3D
var _fade_tween: Tween

func transition_to(scene_path: String, spawn_marker_name: String = "SpawnPoint") -> void:
	if is_transitioning:
		return
	if not ResourceLoader.exists(scene_path):
		HintSystem.show_hint("Локация ещё не собрана:\n%s" % scene_path.get_file(), 3.5)
		return

	is_transitioning = true
	_pending_spawn = spawn_marker_name
	transition_started.emit(scene_path)

	await _fade(1.0)

	# Асинхронная загрузка сцены (не блокирует главный поток).
	ResourceLoader.load_threaded_request(scene_path)
	var progress: Array = []
	var load_ok := false
	while true:
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			load_ok = true
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
		await get_tree().process_frame

	if not load_ok:
		HintSystem.show_hint("Ошибка загрузки локации", 3.0)
		await _fade(0.0)
		is_transitioning = false
		return

	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	get_tree().change_scene_to_packed(packed)

	# Ждём готовности новой сцены и камеры.
	for i in 30:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_viewport().get_camera_3d() != null:
			break

	_move_player_to_spawn()
	_ensure_fade_quad(1.0)
	await _fade(0.0)

	is_transitioning = false
	transition_finished.emit(scene_path)

## Ставит игрока (узел из группы «player») на точку SpawnPoint.
func _move_player_to_spawn() -> void:
	var marker := _find_marker(get_tree().current_scene, _pending_spawn)
	if marker == null:
		push_warning("SceneManager: точка '%s' не найдена" % _pending_spawn)
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	(players[0] as Node3D).global_transform = marker.global_transform

func _find_marker(node: Node, marker_name: String) -> Node3D:
	if node == null:
		return null
	if node is Marker3D and String(node.name) == marker_name:
		return node
	for child in node.get_children():
		var found := _find_marker(child, marker_name)
		if found != null:
			return found
	return null

# --- Затемнение экрана (квад перед камерой, работает и в VR) ---------------

func _fade(target_alpha: float) -> void:
	_ensure_fade_quad(1.0 if target_alpha > 0.5 else -1.0)
	if _fade_quad == null or not is_instance_valid(_fade_quad):
		return
	var material := _fade_quad.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(material, "albedo_color:a", target_alpha, fade_duration)
	await _fade_tween.finished

func _ensure_fade_quad(initial_alpha: float = 0.0) -> void:
	if _fade_quad != null and is_instance_valid(_fade_quad) and _fade_quad.get_parent() != null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_fade_quad = null
		return
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(4, 4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var alpha := 0.0 if initial_alpha < 0.0 else clampf(initial_alpha, 0.0, 1.0)
	material.albedo_color = Color(0, 0, 0, alpha)
	quad_mesh.material = material
	_fade_quad = MeshInstance3D.new()
	_fade_quad.name = "SceneFadeQuad"
	_fade_quad.mesh = quad_mesh
	_fade_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(_fade_quad)
	_fade_quad.position = Vector3(0, 0, -0.5)
