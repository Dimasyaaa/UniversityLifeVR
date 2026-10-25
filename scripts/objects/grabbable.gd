extends RigidBody3D

@export var follow_strength: float = 25.0
@export var max_follow_speed: float = 3.5
@export var rotation_strength: float = 20.0
@export var max_rotation_speed: float = 12.0

var hold_target: Node3D = null
var saved_can_sleep: bool = true


func begin_hold(target: Node3D) -> void:
	hold_target = target
	saved_can_sleep = can_sleep
	freeze = false
	can_sleep = false
	sleeping = false


func end_hold() -> void:
	hold_target = null
	can_sleep = saved_can_sleep


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_instance_valid(hold_target):
		return

	var offset: Vector3 = (
		hold_target.global_position - state.transform.origin
	)
	state.linear_velocity = (
		offset * follow_strength
	).limit_length(max_follow_speed)

	var current_rotation: Quaternion = (
		state.transform.basis.orthonormalized()
		.get_rotation_quaternion()
	)
	var target_rotation: Quaternion = (
		_get_hold_basis().orthonormalized()
		.get_rotation_quaternion()
	)

	var difference: Quaternion = (
		target_rotation * current_rotation.inverse()
	).normalized()

	if difference.w < 0.0:
		difference = -difference

	var angle: float = difference.get_angle()
	if angle > 0.0001:
		state.angular_velocity = (
			difference.get_axis() * angle * rotation_strength
		).limit_length(max_rotation_speed)
	else:
		state.angular_velocity = Vector3.ZERO


func _get_hold_basis() -> Basis:
	return hold_target.global_basis
