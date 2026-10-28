extends "res://scripts/objects/grabbable.gd"
## Одна порция пиццы на тарелке; движение при захвате выполняет общий grabbable.

signal picked_up(first_time: bool)
signal released()
signal eaten()

@export var item_id: StringName = &"dorm_pizza"

@onready var _use_hint: Label3D = $UseHint
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _was_picked_up: bool = false
var _initial_transform: Transform3D
var is_heated: bool = false
var is_eaten: bool = false
var _hint_tween: Tween


func _ready() -> void:
	_initial_transform = transform
	_apply_eaten_state()


func begin_hold(target: Node3D) -> void:
	super.begin_hold(target)
	var first_time: bool = not _was_picked_up
	_was_picked_up = true
	picked_up.emit(first_time)


func end_hold() -> void:
	super.end_hold()
	_hide_hint()
	released.emit()


func try_use(_camera: Camera3D) -> bool:
	if SaveManager.is_loading() or SceneManager.is_transitioning() or not is_instance_valid(hold_target):
		return false
	if is_eaten:
		_show_hint("Тарелка пуста")
		return false
	if not is_heated:
		_show_hint("Сначала разогрейте пиццу")
		return false
	# Сначала меняем состояние: сигнал квеста может запросить сохранение.
	is_eaten = true
	_hide_hint()
	_apply_eaten_state()
	eaten.emit()
	return true


func _apply_eaten_state() -> void:
	for child: Node in get_children():
		if child is MeshInstance3D and child.name != &"Plate":
			child.visible = not is_eaten
	var cylinder: CylinderShape3D = _collision.shape
	cylinder.height = 0.006 if is_eaten else 0.034
	_collision.position.y = cylinder.height * 0.5


func _show_hint(message: String) -> void:
	_hide_hint()
	_use_hint.text = message
	_use_hint.show()
	# Только время показа подписи; игровое время по-прежнему принадлежит TimeManager.
	_hint_tween = create_tween()
	_hint_tween.tween_interval(2.4)
	_hint_tween.tween_callback(_hide_hint)


func _hide_hint() -> void:
	if _hint_tween != null:
		_hint_tween.kill()
		_hint_tween = null
	_use_hint.hide()


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
		"heated": is_heated,
		"eaten": is_eaten,
	}


func restore_save_data(data: Dictionary) -> void:
	var saved_pose: Variant = data.get("transform", _initial_transform)
	var pose: Transform3D = _initial_transform
	if saved_pose is Transform3D and saved_pose.is_finite() and absf(saved_pose.basis.determinant()) > 0.0001:
		pose = Transform3D(saved_pose.basis.orthonormalized(), saved_pose.origin)
	var picked: Variant = data.get("picked_up", false)
	var frozen: Variant = data.get("frozen", true)
	var heated: Variant = data.get("heated", false)
	var consumed: Variant = data.get("eaten", false)
	_hide_hint()
	freeze = true
	transform = pose
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hold_target = null
	can_sleep = true
	_was_picked_up = picked is bool and picked
	is_eaten = consumed is bool and consumed
	is_heated = is_eaten or (heated is bool and heated)
	_apply_eaten_state()
	freeze = frozen if frozen is bool else true
	reset_physics_interpolation()


func mark_heated() -> void:
	if not is_eaten:
		is_heated = true
