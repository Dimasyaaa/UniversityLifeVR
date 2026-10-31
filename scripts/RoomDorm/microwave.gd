extends Node3D
## Локальная микроволновка; отсчёт берётся из общих игровых часов.

signal state_changed()

const BreakfastFood = preload("res://scripts/RoomDorm/breakfast_food.gd")
const OPEN_DOOR_ANGLE: float = -90.0

@export_range(0.1, 10.0, 0.1) var heat_minutes: float = 2.0
@export_range(0.1, 2.0, 0.05) var door_duration: float = 0.45

@onready var _pivot: AnimatableBody3D = $DoorPivot
@onready var _door: MeshInstance3D = $doorMicrowave
@onready var _chamber: CollisionShape3D = $Chamber/CollisionShape3D
@onready var _status: Label3D = $Status
@onready var _sound: AudioStreamPlayer3D = $DoneSound

var is_open: bool = true
var is_moving: bool = false
var is_heating: bool = false
var _remaining: float = 0.0
var _food: BreakfastFood
var _last_clock: float = 0.0
var _tween: Tween
var _initialized: bool = false


func _enter_tree() -> void:
	if _initialized:
		_restore_after_reentry.call_deferred()


func _ready() -> void:
	_last_clock = TimeManager.get_total_seconds()
	_set_door_angle(OPEN_DOOR_ANGLE)
	_update_status()
	_initialized = true


func setup_food(food: BreakfastFood) -> void:
	_food = food
	_update_status()


func _physics_process(_delta: float) -> void:
	_update_heating()


func interact() -> void:
	if is_moving or SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	_update_heating()
	if is_open and _food_overlaps_chamber() and (not is_food_inside() or _food_is_held()):
		_status.text = "Положите тарелку внутрь"
		return
	# Открытие приостанавливает работу. Для продолжения нужны закрытие и «Старт».
	is_heating = false
	is_moving = true
	var start: float = OPEN_DOOR_ANGLE if is_open else 0.0
	is_open = not is_open
	var finish: float = OPEN_DOOR_ANGLE if is_open else 0.0
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_door_angle, start, finish, door_duration)
	_tween.tween_callback(_finish_door)
	_update_status()
	state_changed.emit()


func start_heating() -> void:
	if SaveManager.is_loading() or SceneManager.is_transitioning() or is_moving or is_heating:
		return
	if is_open:
		_status.text = "Закройте дверцу"
		return
	if not is_food_inside() or _food_is_held():
		_status.text = "Нет тарелки внутри"
		return
	if _food.is_eaten:
		_status.text = "Тарелка пуста"
		return
	if _food.is_heated:
		_status.text = "Готово"
		return
	if _remaining <= 0.0:
		_remaining = heat_minutes * 60.0
	is_heating = true
	_last_clock = TimeManager.get_total_seconds()
	_update_status()
	state_changed.emit()


func _food_is_held() -> bool:
	return is_instance_valid(_food) and (_food.has_meta("grabbed_by") or is_instance_valid(_food.hold_target))


func _food_bounds() -> AABB:
	var collision: CollisionShape3D = _food.get_node("CollisionShape3D")
	var cylinder: CylinderShape3D = collision.shape
	var radius: float = cylinder.radius
	var size: Vector3 = Vector3(radius * 2.0, cylinder.height, radius * 2.0)
	var local_pose: Transform3D = global_transform.affine_inverse() * collision.global_transform
	return local_pose * AABB(-size * 0.5, size)


func _chamber_bounds() -> AABB:
	var box: BoxShape3D = _chamber.shape
	return _chamber.transform * AABB(-box.size * 0.5, box.size)


func is_food_inside() -> bool:
	if not is_instance_valid(_food):
		return false
	# Достаточно поместить центр тарелки внутрь: не требуем точной укладки краёв.
	var collision: CollisionShape3D = _food.get_node("CollisionShape3D")
	return _chamber_bounds().has_point(to_local(collision.global_position))


func _food_overlaps_chamber() -> bool:
	return is_instance_valid(_food) and _chamber_bounds().intersects(_food_bounds())


func can_pick_up_food() -> bool:
	return not _food_overlaps_chamber() or (is_open and not is_moving and not is_heating)


func _update_heating() -> void:
	var now: float = TimeManager.get_total_seconds()
	var elapsed: float = maxf(0.0, now - _last_clock)
	_last_clock = now
	if SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	if not is_heating:
		# Вынутая пицца не получает оставшееся время предыдущего размещения.
		if _remaining > 0.0 and not _food_overlaps_chamber():
			_remaining = 0.0
			_update_status()
			state_changed.emit()
		return
	if is_open or is_moving or not is_food_inside() or _food_is_held():
		is_heating = false
		_update_status()
		state_changed.emit()
		return
	_remaining = maxf(0.0, _remaining - elapsed)
	if _remaining <= 0.0001:
		_remaining = 0.0
		is_heating = false
		_food.mark_heated()
		_sound.play()
		state_changed.emit()
	_update_status()


func _set_door_angle(degrees: float) -> void:
	_pivot.rotation.y = deg_to_rad(degrees)
	_door.transform = _pivot.transform * Transform3D(Basis.IDENTITY, -_pivot.position)


func _finish_door() -> void:
	_tween = null
	is_moving = false
	_update_status()
	state_changed.emit()


func _update_status() -> void:
	if is_moving:
		_status.text = "Дверца..."
	elif is_instance_valid(_food) and _food.is_eaten and is_food_inside():
		_status.text = "Тарелка пуста"
	elif is_instance_valid(_food) and _food.is_heated and is_food_inside():
		_status.text = "Готово"
	elif _remaining > 0.0:
		var seconds: int = ceili(_remaining)
		_status.text = ("" if is_heating else "Пауза ") + "%02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]
	else:
		_status.text = "Открыто" if is_open else "Старт"


func get_save_data() -> Dictionary:
	_update_heating()
	return {"door_open": is_open, "heating": is_heating, "remaining_seconds": _remaining}


func restore_save_data(data: Dictionary) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_sound.stop()
	var opened: Variant = data.get("door_open", true)
	var heating: Variant = data.get("heating", false)
	var remaining: Variant = data.get("remaining_seconds", 0.0)
	is_open = opened if opened is bool else true
	is_moving = false
	_remaining = clampf(float(remaining), 0.0, heat_minutes * 60.0) if (remaining is float or remaining is int) and is_finite(float(remaining)) else 0.0
	is_heating = heating is bool and heating and not is_open and _remaining > 0.0 and is_food_inside() and not _food.is_heated
	_last_clock = TimeManager.get_total_seconds()
	_set_door_angle(OPEN_DOOR_ANGLE if is_open else 0.0)
	_update_status()


func _exit_tree() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	is_moving = false


func _restore_after_reentry() -> void:
	if is_inside_tree():
		_last_clock = TimeManager.get_total_seconds()
		_set_door_angle(OPEN_DOOR_ANGLE if is_open else 0.0)
		_update_status()
