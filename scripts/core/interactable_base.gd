class_name InteractableBase
extends Area3D

## Базовый класс интерактивного объекта (ARCHITECTURE.md §5).
## Ставьте на Area3D с CollisionShape3D. Слой коллизий принудительно = 2
## (Interactable), группа «interactable» добавляется автоматически.
## События VR-указки доставляет godot-xr-tools (метод pointer_event),
## десктоп-режим вызывает interact() напрямую (клавиша E).
##
## В наследниках переопределяйте _on_interact(source) — или interact(),
## если нужен полностью свой вход.

signal interacted(source: Node)

@export var prompt: String = "Взаимодействовать"
@export var enabled: bool = true

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 2

## Приём событий указки от godot-xr-tools (XRToolsPointerEvent).
func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			if enabled:
				HintSystem.show_prompt(prompt)
		XRToolsPointerEvent.Type.EXITED:
			HintSystem.hide_prompt()
		XRToolsPointerEvent.Type.PRESSED:
			interact(event.pointer)

## Вызывается игроком для взаимодействия.
func interact(source: Node = null) -> void:
	if not enabled:
		return
	HintSystem.hide_prompt()
	_on_interact(source)
	interacted.emit(source)

## Переопределите в наследниках.
func _on_interact(_source: Node = null) -> void:
	pass
