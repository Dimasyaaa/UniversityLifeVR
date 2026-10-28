extends StaticBody3D
## Одна футболка на плечиках; выбор передаётся локальной вешалке.

signal chosen(item_id: StringName)

@export var item_id: StringName = &"shirt_red"
@export var display_name: String = "Красная футболка"

@onready var _garment: MeshInstance3D = $Garment
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _selected: bool = false


func interact() -> void:
	if _selected or SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	chosen.emit(item_id)


func set_selected(selected: bool) -> void:
	_selected = selected
	_garment.visible = not selected
	_collision.set_deferred("disabled", selected)
	if selected:
		remove_from_group(&"interactable")
	elif not is_in_group(&"interactable"):
		add_to_group(&"interactable")
