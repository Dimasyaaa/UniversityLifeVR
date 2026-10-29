extends AnimatableBody3D
## Выбор кресла через общий VRGrab; обновление по кадрам не требуется.

signal seat_requested(seat: Node3D)

@export var selectable: bool = true

@onready var passenger_anchor: Marker3D = $PassengerAnchor
@onready var passenger_eye_target: Marker3D = $PassengerEyeTarget

var _selection_enabled: bool = false


func set_selection_enabled(enabled: bool) -> void:
	_selection_enabled = enabled and selectable
	if _selection_enabled:
		add_to_group(&"interactable")
	else:
		remove_from_group(&"interactable")


func interact() -> void:
	if _selection_enabled:
		seat_requested.emit(self)
