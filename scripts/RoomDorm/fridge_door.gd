extends InteractableBase

## Дверца холодильника (Модуль 1). Открывается/закрывается по взаимодействию.
## При открытии — выдаём продукты (флаг has_breakfast_products).

@export var open_angle: float = 90.0
@export var duration: float = 1.0
@export var door_direction: int = -1

var is_open: bool = false
var is_moving: bool = false
var closed_rotation: float = 0.0
var tween: Tween

@onready var _door_mesh: MeshInstance3D = get_node_or_null("DoorMesh")

var _closed_transform: Transform3D

func _ready() -> void:
	super._ready()
	if _door_mesh:
		_closed_transform = _door_mesh.transform

func _on_interact(_source: Node = null) -> void:
	if is_moving or not _door_mesh:
		return
	is_moving = true
	is_open = !is_open

	# Выдаём продукты при первом открытии
	if is_open and not GameStateManager.get_flag("has_breakfast_products"):
		GameStateManager.set_flag("has_breakfast_products", true)
		HintSystem.show_hint("Холодильник открыт. Вы взяли продукты.\nРазогрейте завтрак в микроволновке", 5.0)
	elif is_open:
		HintSystem.show_hint("Холодильник открыт", 3.0)
	else:
		HintSystem.show_hint("Холодильник закрыт", 3.0)

	if tween:
		tween.kill()

	var target_transform = _closed_transform
	if is_open:
		target_transform = _closed_transform.rotated(Vector3.UP, deg_to_rad(open_angle * door_direction))

	tween = create_tween()
	tween.tween_property(_door_mesh, "transform", target_transform, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	is_moving = false
