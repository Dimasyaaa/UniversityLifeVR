extends InteractableBase

## Триггер двери (Модуль 1): взаимодействие открывает/закрывает дверь,
## анимацию которой ведёт door.gd на узле-родителе.

@export var door_path: NodePath = ".."

func _on_interact(_source: Node = null) -> void:
	var door := get_node_or_null(door_path)
	if door != null and door.has_method("toggle_door"):
		door.toggle_door()
	else:
		HintSystem.show_hint("Дверь не открывается", 2.0)
