extends "res://scripts/objects/grabbable.gd"
## Одна порция пиццы на тарелке; движение при захвате выполняет общий grabbable.

signal picked_up(first_time: bool)
signal released()

@export var item_id: StringName = &"dorm_pizza"

var _was_picked_up: bool = false
var _initial_transform: Transform3D


func _ready() -> void:
	_initial_transform = transform


func begin_hold(target: Node3D) -> void:
	super.begin_hold(target)
	var first_time: bool = not _was_picked_up
	_was_picked_up = true
	picked_up.emit(first_time)


func end_hold() -> void:
	super.end_hold()
	released.emit()


func set_pickup_enabled(enabled: bool) -> void:
	if enabled == is_in_group(&"grabbable"):
		return
	if enabled:
		add_to_group(&"grabbable")
	else:
		remove_from_group(&"grabbable")


func get_save_data() -> Dictionary:
	return {
		"transform": transform,
		"picked_up": _was_picked_up,
		"frozen": freeze,
	}


func restore_save_data(data: Dictionary) -> void:
	var saved_pose: Variant = data.get("transform", _initial_transform)
	var pose: Transform3D = _initial_transform
	if saved_pose is Transform3D and saved_pose.is_finite() and absf(saved_pose.basis.determinant()) > 0.0001:
		pose = Transform3D(saved_pose.basis.orthonormalized(), saved_pose.origin)
	var picked: Variant = data.get("picked_up", false)
	var frozen: Variant = data.get("frozen", true)
	freeze = true
	transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hold_target = null
	can_sleep = true
	_was_picked_up = picked is bool and picked
	freeze = frozen if frozen is bool else true
	reset_physics_interpolation()
