extends Node3D

@export var interaction_group: StringName = &"interactable"

@onready var controller: XRController3D = (
	get_parent() as XRController3D
)
@onready var xr_origin: XROrigin3D = (
	controller.get_parent() as XROrigin3D
)
@onready var grab_area: Area3D = $GrabArea
@onready var hold_point: Marker3D = $HoldPoint

@onready var player_body: PhysicsBody3D = (
	xr_origin.get_parent() as PhysicsBody3D
)

var player_exception_added: bool = false
var held_object: RigidBody3D = null
var grip_down: bool = false
var trigger_down: bool = false


func _physics_process(delta: float) -> void:
	if not xr_origin.current:
		_drop()
		grip_down = false
		trigger_down = false
		return

	var trigger_value: float = controller.get_float("trigger")
	if not trigger_down and trigger_value >= 0.65:
		trigger_down = true
		_try_interact()
	elif trigger_down and trigger_value <= 0.35:
		trigger_down = false

	var grip_value: float = controller.get_float("grip")

	if not grip_down and grip_value >= 0.65:
		grip_down = true
		_try_grab()

	elif grip_down and grip_value <= 0.35:
		grip_down = false
		_drop()

	if is_instance_valid(held_object):
		if held_object.global_position.distance_to(
			hold_point.global_position
		) > 0.75:
			_drop()
			return
		if held_object.has_method("update_hold"):
			var camera: XRCamera3D = (
				xr_origin.get_node_or_null("XRCamera3D") as XRCamera3D
			)
			var used: bool = bool(held_object.call(
				"update_hold", camera, trigger_value >= 0.65, delta
			))
			if used:
				controller.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.08, 0.0)

func _try_interact() -> void:
	if is_instance_valid(held_object):
		if held_object.has_method("try_use"):
			var camera: XRCamera3D = (
				xr_origin.get_node_or_null("XRCamera3D")
				as XRCamera3D
			)

			if camera != null:
				var used: bool = bool(
					held_object.call("try_use", camera)
				)

				if used:
					controller.trigger_haptic_pulse(
						"haptic", 0.0, 0.3, 0.08, 0.0
					)
					return

	var nearest: Node = null
	var nearest_distance: float = INF
	for body in grab_area.get_overlapping_bodies():
		if not body.is_in_group(interaction_group):
			continue
		var target: Node = body
		while target != null and not target.has_method("interact"):
			target = target.get_parent()
		if target == null:
			continue
		var distance: float = global_position.distance_squared_to(body.global_position)
		if distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	if nearest != null:
		nearest.interact()
		controller.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.08, 0.0)


func _try_grab() -> void:
	if is_instance_valid(held_object):
		return

	var nearest: RigidBody3D = null
	var nearest_distance: float = INF

	for body in grab_area.get_overlapping_bodies():
		if not body is RigidBody3D:
			continue

		var object: RigidBody3D = body as RigidBody3D

		if not object.is_in_group("grabbable"):
			continue
		if object.has_meta("grabbed_by"):
			continue

		if not object.is_visible_in_tree():
			continue

		var distance: float = global_position.distance_squared_to(
			object.global_position
		)

		if distance < nearest_distance:
			nearest = object
			nearest_distance = distance

	if nearest == null:
		return

	grab_object(nearest)


func grab_object(object: RigidBody3D) -> bool:
	if not xr_origin.current or not is_instance_valid(object):
		return false

	if is_instance_valid(held_object) or object.has_meta("grabbed_by"):
		return false

	if not object.is_in_group("grabbable"):
		return false
	if not object.is_visible_in_tree():
		return false

	if not object.has_method("begin_hold"):
		return false
	if not object.has_method("end_hold"):
		return false

	held_object = object
	object.set_meta("grabbed_by", self)
	player_exception_added = false

	if player_body != null:
		if not object.get_collision_exceptions().has(player_body):
			object.add_collision_exception_with(player_body)
			player_exception_added = true

	var world: Node = get_tree().current_scene
	if world == null:
		world = player_body.get_parent()
	if object.get_parent() != world:
		object.reparent(world, true)

	object.call("begin_hold", hold_point)
	return true

func _drop() -> void:
	if not is_instance_valid(held_object):
		held_object = null
		player_exception_added = false
		return

	var object: RigidBody3D = held_object
	held_object = null

	object.remove_meta("grabbed_by")
	object.call("end_hold")

	if player_exception_added and is_instance_valid(player_body):
		object.remove_collision_exception_with(player_body)

	player_exception_added = false
	object.sleeping = false
	
func _exit_tree() -> void:
	_drop()
