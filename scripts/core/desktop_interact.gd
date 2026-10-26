extends Node

## Десктоп-режим (тесты без VR-гарнитуры): клавиша E (действие «interact»)
## взаимодействует с объектом, на который смотрит камера.
## Ставится дочерним узлом к корню префаба игрока (player.tscn).

## Дальность взаимодействия, метры.
@export var interact_distance: float = 4.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * interact_distance
	# Слой 2 (Interactable) — по ARCHITECTURE.md §3.
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var world := get_viewport().find_world_3d()
	if world == null:
		return
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider = hit["collider"]
	if collider is InteractableBase:
		collider.interact(self)
