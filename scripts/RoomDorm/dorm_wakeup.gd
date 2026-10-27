extends Node3D
## Временная поза единого игрока. Игровое состояние хранит dorm_room.gd.

signal stood_up()

const Player = preload("res://scripts/player/player.gd")

@export_range(0.0, 2.0, 0.05) var desktop_rise_duration: float = 0.85

@onready var _head: Marker3D = $LyingHead
@onready var _standing: Marker3D = $StandingSpawn
@onready var _screen: XRToolsViewport2DIn3D = $Screen

var _player: Player
var _button: Button
var _base_origin: Transform3D
var _base_physics: bool = true
var _base_collision_disabled: bool = false
var _base_movement: bool = true
var _base_move_speed: float = 2.5
var _lying: bool = false
var _rising: bool = false
var _waiting_calibration: bool = false
var _owns_pose: bool = false
var _rise_tween: Tween
var _xr_interface: OpenXRInterface
var _menu: Node3D
var _standing_placed: bool = false


func _ready() -> void:
	_button = _screen.get_scene_instance().get_node("Panel/Margin/Content/Stand") as Button
	_button.pressed.connect(_request_stand)
	_screen.enabled = false
	_screen.hide()
	SceneManager.transition_started.connect(_on_transition_started)
	SceneManager.transition_failed.connect(_on_transition_failed)


func activate(completed: bool) -> void:
	if _owns_pose or _waiting_calibration:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not camera.get_parent().get_parent() is Player:
		push_error("Dorm wakeup: общий игрок не найден.")
		return
	_player = camera.get_parent().get_parent() as Player
	if completed:
		if not _standing_placed:
			_standing_placed = _player.place_at_spawn(_standing)
		return
	_menu = _player.get_parent().get_node_or_null("MainMenuPanel") as Node3D
	if _menu != null and not _menu.visibility_changed.is_connected(_sync_screen):
		_menu.visibility_changed.connect(_sync_screen)
	_base_physics = _player.is_physics_processing()
	_base_movement = _player.is_movement_enabled()
	_base_move_speed = _player.move_speed
	_base_collision_disabled = _player.body_collision.disabled
	_xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if get_viewport().use_xr:
		# Калибровку выполняет общий игрок; после неё можно сохранить его XR-origin.
		_waiting_calibration = true
		_player.calibrated.connect(_on_calibrated)
		if _xr_interface != null:
			_xr_interface.pose_recentered.connect(_on_pose_recentered)
		_player.move_speed = 0.0
		_player.request_calibration()
	else:
		_apply_lying_pose()


func is_lying() -> bool:
	return _lying or _waiting_calibration


func is_rising() -> bool:
	return _rising


func _apply_lying_pose() -> void:
	if not _player.place_at_spawn(_standing):
		return
	_base_origin = _player.xr_origin.transform
	_owns_pose = true
	_lying = true
	_waiting_calibration = false
	_player.move_speed = _base_move_speed
	_player.velocity = Vector3.ZERO
	_player.body_collision.set_deferred("disabled", true)
	# Остановка только физического шага игрока сохраняет работу его рук и UI.
	# Movement-флаг остаётся обычным: SceneManager и меню сохраняют его сами.
	_player.set_physics_process(false)
	if not get_viewport().use_xr:
		# В шлеме углы головы полностью принадлежат трекингу OpenXR.
		_player.xr_origin.global_basis = _head.global_basis * _player.camera.basis.inverse()
	_player.xr_origin.global_position += _head.global_position - _player.camera.global_position
	_player.reset_physics_interpolation()
	_button.disabled = false
	_button.text = "Встать"
	_screen.global_position = _player.camera.global_position - _player.camera.global_basis.z * 0.95
	_screen.global_basis = _player.camera.global_basis
	_sync_screen()


func _sync_screen() -> void:
	var active: bool = _lying and not _rising and not _waiting_calibration and (_menu == null or not _menu.visible)
	_screen.visible = active
	_screen.enabled = active


func _request_stand() -> void:
	if not _lying or _rising or SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	if _menu != null and _menu.visible:
		return
	_rising = true
	_button.disabled = true
	_button.text = "Встаём…"
	_screen.enabled = false
	var duration: float = 0.0 if get_viewport().use_xr else desktop_rise_duration
	if duration <= 0.0:
		_finish_stand.call_deferred()
	else:
		_rise_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_rise_tween.tween_property(_player.xr_origin, "transform", _base_origin, duration)
		_rise_tween.tween_callback(_finish_stand)


func _finish_stand() -> void:
	if not _rising or _waiting_calibration:
		return
	_rise_tween = null
	_player.xr_origin.transform = _base_origin
	if not _player.place_at_spawn(_standing):
		_rising = false
		_apply_lying_pose()
		return
	_standing_placed = true
	_restore_player()
	_lying = false
	_rising = false
	stood_up.emit()


func _restore_player() -> void:
	if _rise_tween != null:
		_rise_tween.kill()
		_rise_tween = null
	_screen.enabled = false
	_screen.hide()
	if is_instance_valid(_menu) and _menu.visibility_changed.is_connected(_sync_screen):
		_menu.visibility_changed.disconnect(_sync_screen)
	if is_instance_valid(_player):
		_player.move_speed = _base_move_speed
		if _owns_pose:
			_player.xr_origin.transform = _base_origin
			_player.body_collision.set_deferred("disabled", _base_collision_disabled)
		_player.set_physics_process(_base_physics)
		if not SceneManager.is_transitioning() and not SaveManager.is_loading() and (_menu == null or not _menu.visible):
			_player.set_movement_enabled(_base_movement)
		if _player.calibrated.is_connected(_on_calibrated):
			_player.calibrated.disconnect(_on_calibrated)
	if is_instance_valid(_xr_interface) and _xr_interface.pose_recentered.is_connected(_on_pose_recentered):
		_xr_interface.pose_recentered.disconnect(_on_pose_recentered)
	_owns_pose = false
	_waiting_calibration = false


func _on_calibrated(_height: float) -> void:
	if _waiting_calibration:
		_finish_calibration.call_deferred()


func _finish_calibration() -> void:
	if _waiting_calibration and is_inside_tree() and SceneManager.get_current_location() == get_parent():
		_apply_lying_pose()


func _on_pose_recentered() -> void:
	if not _lying:
		return
	if _rise_tween != null:
		_rise_tween.kill()
		_rise_tween = null
	_rising = false
	_waiting_calibration = true
	_player.xr_origin.transform = _base_origin
	_player.move_speed = 0.0
	_player.set_physics_process(true)
	_sync_screen()


func _on_transition_started(_location_id: StringName) -> void:
	# SceneManager захватил флаг движения; вернём обычную позу до place_at_spawn.
	if _owns_pose or _waiting_calibration:
		_restore_player()
		_rising = false


func _on_transition_failed(_location_id: StringName, _reason: String) -> void:
	if _lying and SceneManager.get_current_location() == get_parent():
		activate(false)


func _exit_tree() -> void:
	if _owns_pose or _waiting_calibration:
		_restore_player()
