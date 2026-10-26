extends InteractableBase

## Лампа с кнопкой выключателя (Модуль 1). Включает/выключает свет.

@export var light_path: NodePath = ".."
@export var on_color: Color = Color(1.0, 0.95, 0.8, 1.0)
@export var off_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var on_energy: float = 1.0
@export var off_energy: float = 0.0

var is_on: bool = true

@onready var _light: Node3D = get_node_or_null(light_path)

func _ready() -> void:
	super._ready()
	_set_light(is_on)

func _on_interact(_source: Node = null) -> void:
	is_on = !is_on
	_set_light(is_on)
	if is_on:
		HintSystem.show_hint("Свет включён", 2.0)
	else:
		HintSystem.show_hint("Свет выключён", 2.0)

func _set_light(on: bool) -> void:
	if not _light:
		return
	# Пробуем найти источник света в указанном узле
	var light := _light
	if light is Light3D:
		light.enabled = on
		light.color = on_color if on else off_color
		light.energy = on_energy if on else off_energy
	else:
		# Ищем Light3D среди детей
		var lights := _light.get_children()
		for child in lights:
			if child is Light3D:
				child.enabled = on
				child.color = on_color if on else off_color
				child.energy = on_energy if on else off_energy
