extends StaticBody3D
## Корпус остаётся неподвижным, исходная дверца следует за отдельным DoorPivot.

signal door_state_changed(opened: bool)

@export_range(1.0, 90.0, 1.0) var open_angle: float = 90.0
@export_range(0.1, 2.0, 0.05) var duration: float = 0.6

@onready var _pivot: AnimatableBody3D = $DoorPivot
@onready var _door_mesh: MeshInstance3D = $Model/RootNode/Environment_Fridge_Door

var is_open: bool = false
var is_moving: bool = false
var _closed_pivot: Transform3D
var _visual_offset: Transform3D
var _tween: Tween
var _initialized: bool = false


func _enter_tree() -> void:
	if _initialized:
		is_moving = true
		_restore_after_reentry.call_deferred()


func _ready() -> void:
	_closed_pivot = _pivot.transform
	# Меш сохраняет исходного владельца GLB и материалы; форма имеет единичный масштаб.
	_visual_offset = _closed_pivot.affine_inverse() * global_transform.affine_inverse() * _door_mesh.global_transform
	_set_angle(0.0)
	_initialized = true


func interact() -> void:
	if is_moving or SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	is_moving = true
	is_open = not is_open
	var start: float = 0.0 if is_open else open_angle
	var finish: float = open_angle if is_open else 0.0
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_angle, start, finish, duration)
	_tween.tween_callback(_finish_movement)


func _set_angle(degrees: float) -> void:
	var pose: Transform3D = _closed_pivot * Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO)
	_pivot.transform = pose
	_door_mesh.global_transform = global_transform * pose * _visual_offset


func _finish_movement() -> void:
	_tween = null
	is_moving = false
	door_state_changed.emit(is_open)


func get_save_data() -> Dictionary:
	# При сохранении в середине анимации запоминается целевое состояние дверцы.
	return {"door_open": is_open}


func restore_save_data(data: Dictionary) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	var opened: Variant = data.get("door_open", false)
	is_open = opened is bool and opened
	is_moving = false
	_set_angle(open_angle if is_open else 0.0)


func _exit_tree() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	is_moving = false


func _restore_after_reentry() -> void:
	# SceneManager может вернуть тот же экземпляр комнаты при ошибке перехода.
	if is_inside_tree():
		restore_save_data({"door_open": is_open})
