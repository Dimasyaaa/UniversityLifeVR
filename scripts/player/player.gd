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
	_handle_turn()
	_update_body()
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
	calibrated.emit(eye_height)
	print("VR Player calibrated: eye height ", eye_height)


func set_pointers_enabled(active: bool) -> void:
	pointers_enabled = active
	for hand: XRController3D in [left_hand, right_hand]:
		var pointer: Node3D = hand.get_node("FunctionPointer")
		pointer.set("enabled", active)
		pointer.visible = active
