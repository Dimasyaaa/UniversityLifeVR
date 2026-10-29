extends CharacterBody3D
## Общее тело игрока: движение, XR-калибровка и управление лучами.

signal calibrated(eye_height: float)

@export var move_speed: float = 2.5
@export var snap_turn_angle: float = 30.0
@export var eye_height: float = 1.7
@export var calibrate_on_start: bool = true
@export var align_view_on_calibration: bool = true
@export var calibration_action: StringName = &"by_button"
@export var pointers_enabled: bool = true

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var body_collision: CollisionShape3D = $CollisionShape3D

var _vr_active: bool = false
var _calibration_pending: bool = false
var _tracked_frames: int = 0
var _calibration_down: bool = false
var _turn_ready: bool = true
var _movement_enabled: bool = true
var _passenger_active: bool = false
var _passenger_anchor: Marker3D
var _passenger_eye: Marker3D
var _passenger_anchor_pose: Transform3D
var _passenger_height_offset: float = 0.0
var _passenger_collision_layer: int = 0
var _passenger_collision_mask: int = 0


func _enter_tree() -> void:
	$XROrigin3D/XRCamera3D.position.y = eye_height


func _ready() -> void:
	xr_origin.current = true
	camera.make_current()
	var interface: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	_vr_active = interface != null and interface.is_initialized()
	get_viewport().use_xr = _vr_active
	if _vr_active:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		interface.pose_recentered.connect(request_calibration)
		if calibrate_on_start:
			request_calibration()
	elif OS.has_feature("android"):
		push_error("VR Player: OpenXR не запущен. Проверь XR/OpenXR и плагин производителя в экспорте.")
	set_pointers_enabled(pointers_enabled)
	# Экземпляры игрока не делят изменяемую форму коллизии.
	body_collision.shape = body_collision.shape.duplicate()


func _physics_process(delta: float) -> void:
	if not xr_origin.current:
		return
	var pressed: bool = right_hand.is_button_pressed(calibration_action)
	if pressed and not _calibration_down:
		request_calibration()
	_calibration_down = pressed
	_try_calibrate()
	_follow_passenger_anchor()
	_update_body()
	if not _movement_enabled or _passenger_active:
		velocity = Vector3.ZERO
		return
	_handle_turn()
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	var stick: Vector2 = left_hand.get_vector2("primary")
	var direction: Vector3 = Vector3.ZERO
	if stick.length() > 0.2:
		var forward: Vector3 = -camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = -global_basis.z
		forward = forward.normalized()
		stick = stick.limit_length(1.0)
		direction = forward * stick.y + forward.cross(Vector3.UP) * stick.x
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	move_and_slide()


func set_movement_enabled(enabled: bool) -> void:
	if _movement_enabled == enabled:
		return
	_movement_enabled = enabled
	velocity = Vector3.ZERO
	# После включения ждём возврата правого стика в нейтральное положение.
	_turn_ready = false


func is_movement_enabled() -> bool:
	# Общий допуск от меню/SceneManager; кресло ограничивает ходьбу отдельно.
	return _movement_enabled


## Сохраняет XR-отслеживание, но фиксирует пассажира относительно выбранного места.
func enter_passenger_mode(anchor: Marker3D, eye_target: Marker3D) -> bool:
	if _passenger_active or not _movement_enabled:
		return false
	if not is_instance_valid(eye_target) or not eye_target.is_inside_tree() or eye_target.is_queued_for_deletion():
		return false
	if is_ancestor_of(eye_target) or not place_at_spawn(anchor):
		return false
	release_held_objects()
	_passenger_anchor = anchor
	_passenger_eye = eye_target
	_passenger_anchor_pose = _get_passenger_anchor_pose()
	_passenger_height_offset = 0.0
	_passenger_collision_layer = collision_layer
	_passenger_collision_mask = collision_mask
	_passenger_active = true
	# Капсула не должна пересекать кресло; руки и телефон продолжают взаимодействия.
	collision_layer = 0
	collision_mask = 0
	_align_passenger_eyes()
	_update_body()
	reset_physics_interpolation()
	return true


func is_passenger_mode() -> bool:
	return _passenger_active


func _clear_passenger_mode() -> void:
	if not _passenger_active:
		return
	xr_origin.position.y -= _passenger_height_offset
	collision_layer = _passenger_collision_layer
	collision_mask = _passenger_collision_mask
	_passenger_active = false
	_passenger_anchor = null
	_passenger_eye = null
	_passenger_height_offset = 0.0
	velocity = Vector3.ZERO
	_turn_ready = false


func _get_passenger_anchor_pose() -> Transform3D:
	return Transform3D(_passenger_anchor.global_basis.orthonormalized(), _passenger_anchor.global_position)


func _follow_passenger_anchor() -> void:
	if not _passenger_active:
		return
	if not _passenger_targets_valid():
		_clear_passenger_mode()
		return
	var current_pose: Transform3D = _get_passenger_anchor_pose()
	if current_pose.is_equal_approx(_passenger_anchor_pose):
		return
	global_transform = current_pose * _passenger_anchor_pose.affine_inverse() * global_transform
	_passenger_anchor_pose = current_pose


func _passenger_targets_valid() -> bool:
	return (
		is_instance_valid(_passenger_anchor) and _passenger_anchor.is_inside_tree()
		and is_instance_valid(_passenger_eye) and _passenger_eye.is_inside_tree()
	)


func _align_passenger_eyes() -> void:
	var forward: Vector3 = -_passenger_anchor.global_basis.z
	forward.y = 0.0
	var head_forward: Vector3 = -camera.global_basis.z
	head_forward.y = 0.0
	if forward.length_squared() > 0.0001 and head_forward.length_squared() > 0.0001:
		global_rotate(Vector3.UP, head_forward.normalized().signed_angle_to(forward.normalized(), Vector3.UP))
	global_position.y = _passenger_anchor.global_position.y
	var adjustment: Vector3 = _passenger_eye.global_position - camera.global_position
	global_position += Vector3(adjustment.x, 0.0, adjustment.z)
	xr_origin.position.y += adjustment.y
	_passenger_height_offset += adjustment.y
	_passenger_anchor_pose = _get_passenger_anchor_pose()


func release_held_objects() -> void:
	for hand: XRController3D in [left_hand, right_hand]:
		# Детали захвата остаются внутри сцены игрока.
		hand.get_node("VRGrab").call("_drop")


func place_at_spawn(spawn: Marker3D) -> bool:
	if not is_node_ready() or not is_inside_tree() or is_queued_for_deletion():
		push_warning("Игрок ещё не готов к размещению.")
		return false
	if not is_instance_valid(spawn) or not spawn.is_inside_tree() or spawn.is_queued_for_deletion():
		push_warning("Для размещения нужна действительная точка Marker3D в дереве сцены.")
		return false
	if is_ancestor_of(spawn):
		push_warning("Точка появления должна находиться вне игрока.")
		return false
	if _calibration_pending:
		push_warning("Перед размещением нужно дождаться завершения XR-калибровки.")
		return false
	var target_position: Vector3 = spawn.global_position
	var target_forward: Vector3 = -spawn.global_basis.z
	target_forward.y = 0.0
	if target_forward.length_squared() < 0.0001:
		push_warning("Направление точки появления должно иметь горизонтальную составляющую.")
		return false
	# Любой переход через общую точку появления завершает пассажирский режим.
	_clear_passenger_mode()
	var head_forward: Vector3 = -camera.global_basis.z
	head_forward.y = 0.0
	if head_forward.length_squared() < 0.0001:
		head_forward = -global_basis.z
		head_forward.y = 0.0
	# Поворачиваем тело вместе с XR-пространством, сохраняя локальную позу головы.
	var angle: float = head_forward.normalized().signed_angle_to(target_forward.normalized(), Vector3.UP)
	global_rotate(Vector3.UP, angle)
	var head_offset: Vector3 = camera.global_position - global_position
	head_offset.y = 0.0
	global_position = target_position - head_offset
	velocity = Vector3.ZERO
	_turn_ready = false
	_update_body()
	reset_physics_interpolation()
	return true


func _update_body() -> void:
	var head: Vector3 = to_local(camera.global_position)
	var capsule: CapsuleShape3D = body_collision.shape as CapsuleShape3D
	capsule.height = maxf(capsule.radius * 2.0, head.y + 0.15)
	body_collision.position = Vector3(head.x, capsule.height * 0.5, head.z)


func _handle_turn() -> void:
	var stick: Vector2 = right_hand.get_vector2("primary")
	if absf(stick.x) < 0.25:
		_turn_ready = true
	if not _turn_ready or absf(stick.x) < 0.75:
		return
	_turn_ready = false
	var head_before: Vector3 = camera.global_position
	rotate_y(-deg_to_rad(snap_turn_angle) * signf(stick.x))
	global_position += head_before - camera.global_position


func request_calibration() -> void:
	if not _vr_active:
		return
	_calibration_pending = true
	_tracked_frames = 0


func _try_calibrate() -> void:
	if not _calibration_pending:
		return
	var head: XRPositionalTracker = XRServer.get_tracker("head") as XRPositionalTracker
	var pose: XRPose = head.get_pose("default") if head != null else null
	if pose == null or not pose.has_tracking_data:
		_tracked_frames = 0
		return
	_tracked_frames += 1
	if _tracked_frames < 3:
		return
	if align_view_on_calibration:
		var forward: Vector3 = -camera.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			xr_origin.rotation.y = -atan2(-forward.x, -forward.z)
	var head_offset: Vector3 = xr_origin.basis * camera.position
	xr_origin.position = Vector3(-head_offset.x, eye_height - head_offset.y, -head_offset.z)
	_calibration_pending = false
	if _passenger_active:
		# Калибровка создала новый базовый offset; поверх него снова задаём высоту кресла.
		_passenger_height_offset = 0.0
		if _passenger_targets_valid():
			_align_passenger_eyes()
		else:
			_clear_passenger_mode()
	calibrated.emit(eye_height)
	print("VR Player calibrated: eye height ", eye_height)


func set_pointers_enabled(active: bool) -> void:
	pointers_enabled = active
	for hand: XRController3D in [left_hand, right_hand]:
		var pointer: Node3D = hand.get_node("FunctionPointer")
		pointer.set("enabled", active)
		pointer.visible = active
