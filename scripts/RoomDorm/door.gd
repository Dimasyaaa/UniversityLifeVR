extends Node3D

## Дверь (Модуль 1). Открывается/закрывается по взаимодействию:
## дочерний InteractableArea (door_interact.gd) вызывает toggle_door().
## Анимация — tween-поворот DoorPivot.

@export var open_angle: float = 90.0
@export var duration: float = 1.5
@export var door_direction: int = 1

var is_open: bool = false
var is_moving: bool = false
var closed_rotation: float = 0.0
var tween: Tween

@onready var door_pivot = get_node_or_null("DoorPivot")
@onready var open_sound = get_node_or_null("OpenSound")
@onready var close_sound = get_node_or_null("CloseSound")

func _ready() -> void:
	if door_pivot:
		closed_rotation = door_pivot.rotation_degrees.y

func toggle_door() -> void:
	if is_moving or not door_pivot:
		return

	is_moving = true
	is_open = !is_open

	var target_rotation = closed_rotation
	if is_open:
		target_rotation = closed_rotation + (open_angle * door_direction)
		if open_sound:
			open_sound.play()
		HintSystem.show_hint("Дверь открывается", 1.5)
	else:
		if close_sound:
			close_sound.play()
		HintSystem.show_hint("Дверь закрывается", 1.5)

	if tween:
		tween.kill()

	tween = create_tween()
	tween.tween_property(door_pivot, "rotation_degrees:y", target_rotation, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	is_moving = false
