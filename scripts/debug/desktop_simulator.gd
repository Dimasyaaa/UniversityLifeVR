extends Node
## Autoload для домашних проверок: клавиатура, мышь и виртуальные XR-контроллеры.

@export var enabled_on_desktop: bool = true
@export var eye_height: float = 1.7

var enabled: bool = false
var camera: XRCamera3D
var origin: XROrigin3D
var left_tracker: XRControllerTracker
var right_tracker: XRControllerTracker
var left_pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.55, -0.8))
var right_pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.3, 1.55, -0.8))
var head_position: Vector3 = Vector3(0.0, 1.7, 0.0)
var head_rotation: Vector3 = Vector3.ZERO
var left_selected: bool = false
var right_selected: bool = false


func _ready() -> void:
	var interface: XRInterface = XRServer.find_interface("OpenXR")
	var headset_active: bool = interface != null and interface.is_initialized()
	enabled = enabled_on_desktop and not headset_active and not OS.has_feature("android")
	if enabled and (XRServer.get_tracker("left_hand") != null or XRServer.get_tracker("right_hand") != null):
		push_warning("DesktopSimulator: имена контроллеров уже заняты; симулятор отключён.")
		enabled = false
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	head_position.y = eye_height
	left_pose.origin.y = eye_height - 0.15
	right_pose.origin.y = eye_height - 0.15
	process_priority = -100
	left_tracker = _create_tracker("left_hand", XRPositionalTracker.TRACKER_HAND_LEFT)
	right_tracker = _create_tracker("right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT)
	_update_poses()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("DesktopSimulator: WASD — ходьба, мышь — взгляд, Q/E — руки, Esc — курсор.")


func _create_tracker(tracker_name: StringName, hand: XRPositionalTracker.TrackerHand) -> XRControllerTracker:
	var tracker: XRControllerTracker = XRControllerTracker.new()
	tracker.name = tracker_name
	tracker.hand = hand
	tracker.set_input("grip", 0.0)
	tracker.set_input("by_button", false)
	tracker.set_input("primary", Vector2.ZERO)
	_set_trigger(tracker, false)
	XRServer.add_tracker(tracker)
	return tracker


func _process(_delta: float) -> void:
	_refresh_devices()
	var captured: bool = camera != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	left_tracker.set_input("primary", _stick(KEY_A, KEY_D, KEY_S, KEY_W) if captured else Vector2.ZERO)
	right_tracker.set_input("primary", _stick(KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP) if captured else Vector2.ZERO)
	_update_poses()


func _refresh_devices() -> void:
	var active_camera: Camera3D = get_viewport().get_camera_3d()
	if not active_camera is XRCamera3D:
		camera = null
		origin = null
		return
	camera = active_camera as XRCamera3D
	origin = camera.get_parent() as XROrigin3D
	if origin == null or not origin.current:
		camera = null
		return
	camera.position = head_position
	camera.rotation = head_rotation


func _stick(negative_x: Key, positive_x: Key, negative_y: Key, positive_y: Key) -> Vector2:
	return Vector2(
		float(Input.is_physical_key_pressed(positive_x)) - float(Input.is_physical_key_pressed(negative_x)),
		float(Input.is_physical_key_pressed(positive_y)) - float(Input.is_physical_key_pressed(negative_y))
	).limit_length(1.0)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_clear_buttons()
			return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_refresh_devices()
	if camera == null:
		return
	if event is InputEventKey:
		if event.physical_keycode == KEY_Q:
			left_selected = event.pressed
		elif event.physical_keycode == KEY_E:
			right_selected = event.pressed
		elif event.physical_keycode == KEY_R and event.pressed and not event.echo:
			reset_view()
	elif event is InputEventMouseMotion:
		if left_selected or right_selected:
			_move_hands(event.screen_relative, Input.is_physical_key_pressed(KEY_SHIFT))
		else:
			head_rotation.y -= event.screen_relative.x * 0.002
			head_rotation.x = clampf(head_rotation.x - event.screen_relative.y * 0.002, -1.4, 1.4)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Фиксируем захват выбранной руки: одна мышь управляет двумя руками.
			if left_selected:
				left_tracker.set_input("grip", 1.0 - float(left_tracker.get_input("grip")))
			if right_selected:
				right_tracker.set_input("grip", 1.0 - float(right_tracker.get_input("grip")))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if left_selected:
					_set_trigger(left_tracker, true)
				if right_selected:
					_set_trigger(right_tracker, true)
			else:
				_set_trigger(left_tracker, false)
				_set_trigger(right_tracker, false)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step: float = 0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05
			if left_selected:
				left_pose.origin += (left_pose.origin - head_position).normalized() * step
			if right_selected:
				right_pose.origin += (right_pose.origin - head_position).normalized() * step
	_refresh_devices()
	_update_poses()


func _move_hands(motion: Vector2, rotate_hand: bool) -> void:
	var view_basis: Basis = Basis.from_euler(head_rotation)
	if rotate_hand:
		var turn: Basis = Basis(Vector3.UP, -motion.x * 0.002) * Basis(Vector3.RIGHT, -motion.y * 0.002)
		if left_selected:
			left_pose.basis = (turn * left_pose.basis).orthonormalized()
		if right_selected:
			right_pose.basis = (turn * right_pose.basis).orthonormalized()
	else:
		var movement: Vector3 = view_basis.x * motion.x * 0.002 - view_basis.y * motion.y * 0.002
		if left_selected:
			left_pose.origin += movement
		if right_selected:
			right_pose.origin += movement


func _update_poses() -> void:
	left_tracker.set_pose("grip", left_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	right_tracker.set_pose("grip", right_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	left_tracker.set_pose("aim", left_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	right_tracker.set_pose("aim", right_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)

func _set_trigger(
	tracker: XRControllerTracker,
	pressed: bool
) -> void:
	tracker.set_input("trigger", 1.0 if pressed else 0.0)
	tracker.set_input("trigger_click", pressed)

func _clear_buttons() -> void:
	left_selected = false
	right_selected = false
	for tracker in [left_tracker, right_tracker]:
		if tracker == null:
			continue
		tracker.set_input("grip", 0.0)
		_set_trigger(tracker, false)
		tracker.set_input("primary", Vector2.ZERO)
		tracker.set_input("by_button", false)


func _notification(what: int) -> void:
	if enabled and what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_buttons()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if not enabled:
		return
	_clear_buttons()
	for tracker in [left_tracker, right_tracker]:
		if tracker != null and XRServer.get_tracker(tracker.name) == tracker:
			XRServer.remove_tracker(tracker)
	left_tracker = null
	right_tracker = null
	enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func reset_view() -> void:
	if not enabled:
		return
	var change: float = eye_height - head_position.y
	head_position.y = eye_height
	head_rotation = Vector3.ZERO
	left_pose.origin.y += change
	right_pose.origin.y += change
	_refresh_devices()
	_update_poses()
