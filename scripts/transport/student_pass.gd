extends "res://scripts/objects/grabbable.gd"
## Обычный захватываемый предмет; завершение и награда принадлежат QuestManager.

const Player = preload("res://scripts/player/player.gd")
const QUEST_ID: StringName = &"transport_lost_pass"
const RETURN_EVENT: StringName = &"transport_pass_returned"

@export_range(0.5, 2.0, 0.1) var return_distance: float = 1.5
@export var return_point_path: NodePath = NodePath("../StopStudent/TalkPoint")
@export_range(20.0, 150.0, 5.0) var recovery_distance: float = 80.0

@onready var _location: Node3D = get_parent() as Node3D
@onready var _return_point: Node3D = get_node(return_point_path) as Node3D
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _home_transform: Transform3D
var _returned: bool = false


func _ready() -> void:
	_home_transform = transform
	QuestManager.quest_completed.connect(_on_quest_completed)
	# Менеджеры восстановлены до добавления загружаемой локации в дерево.
	if QuestManager.is_quest_completed(QUEST_ID):
		_hide_returned()


func _physics_process(_delta: float) -> void:
	if _returned or is_instance_valid(hold_target) or not _is_context_active():
		return
	# До остановки можно донести или уронить пропуск без сброса к месту поиска.
	if position.y < -2.0 or position.distance_to(_home_transform.origin) > recovery_distance:
		_reset_at_home()


func is_held_by(player: Player) -> bool:
	if _returned or not is_instance_valid(player):
		return false
	for hand: XRController3D in [player.left_hand, player.right_hand]:
		if hand.get_node("VRGrab").get("held_object") == self:
			return true
	return false


func try_return(player: Player) -> bool:
	if _returned or not _is_context_active() or not is_held_by(player):
		return false
	if not QuestManager.is_quest_active(QUEST_ID) or QuestManager.is_quest_completed(QUEST_ID):
		return false
	if global_position.distance_to(_return_point.global_position) > return_distance:
		return false
	# Сначала исключаем повторную сдачу, затем освобождаем общий захват.
	_returned = true
	player.release_held_objects()
	QuestManager.notify_event(RETURN_EVENT)
	if not QuestManager.is_quest_completed(QUEST_ID):
		_returned = false
		_reset_at_home()
		return false
	_hide_returned()
	return true


func _on_quest_completed(quest_id: StringName) -> void:
	if quest_id == QUEST_ID:
		_hide_returned()


func _hide_returned() -> void:
	_returned = true
	hide()
	remove_from_group(&"grabbable")
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	_collision.set_deferred("disabled", true)
	set_physics_process(false)


func _reset_at_home() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	transform = _home_transform
	set_deferred("freeze", true)
	reset_physics_interpolation()


func _is_context_active() -> bool:
	return (
		SceneManager.get_current_location() == _location
		and not SceneManager.is_transitioning()
		and not SaveManager.is_loading()
		and not TimeManager.is_time_paused()
	)
