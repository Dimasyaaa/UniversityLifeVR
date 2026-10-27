@tool
extends Node3D
## Модели и позы: Godot XR Tools, DigitalN8m4r3 / Miodrag Sejic, CC0.
## https://github.com/GodotVR/godot-xr-tools/tree/6fc5361db295c12b5e51ee5b9fee09751a4458e7/addons/godot-xr-tools/hands

@export var open_pose: Animation
@export var closed_pose: Animation

var skeleton: Skeleton3D
var open_rotations: Dictionary = {}
var closed_rotations: Dictionary = {}
var grip_amount: float = 0.0
var trigger_amount: float = 0.0


func _ready() -> void:
	skeleton = $Model.get_node("Armature/Skeleton3D") as Skeleton3D
	open_rotations = _read_pose(open_pose)
	closed_rotations = _read_pose(closed_pose)
	_apply_fingers()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var controller: XRController3D = get_parent() as XRController3D
	if controller == null:
		return
	var weight: float = 1.0 - exp(-18.0 * delta)
	var target_grip: float = clampf(controller.get_float("grip"), 0.0, 1.0)
	var grab: Node = controller.get_node_or_null("VRGrab")
	if grab != null and is_instance_valid(grab.held_object):
		target_grip = maxf(target_grip, 0.8)
	grip_amount = lerpf(grip_amount, target_grip, weight)
	trigger_amount = lerpf(trigger_amount, clampf(controller.get_float("trigger"), 0.0, 1.0), weight)
	_apply_fingers()


func _read_pose(animation: Animation) -> Dictionary:
	var rotations: Dictionary = {}
	if animation == null:
		return rotations
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or animation.track_get_key_count(track) == 0:
			continue
		var path: NodePath = animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone: int = skeleton.find_bone(path.get_subname(0))
		if bone >= 0:
			rotations[bone] = animation.track_get_key_value(track, 0)
	return rotations


func _apply_fingers() -> void:
	for bone: int in open_rotations:
		var opened: Quaternion = open_rotations[bone]
		var closed: Quaternion = closed_rotations.get(bone, opened)
		var amount: float = maxf(grip_amount, trigger_amount) if skeleton.get_bone_name(bone).begins_with("Index_") else grip_amount
		skeleton.set_bone_pose_rotation(bone, opened.slerp(closed, amount))
