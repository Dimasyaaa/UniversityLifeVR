extends Area3D
## Вход игрока в зону запускает переход через общий SceneManager.

const Player = preload("res://scripts/player/player.gd")

@export var target_location: StringName = &""
@export var target_spawn: StringName = &"Spawn_Default"


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not SceneManager.is_transitioning():
		SceneManager.change_location(target_location, target_spawn)
