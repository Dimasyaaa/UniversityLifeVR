extends Node3D
## Экран часов получает игровое время из TimeManager.

@onready var time_label: Label3D = $TimeLabel


func _ready() -> void:
	TimeManager.time_changed.connect(_on_time_changed)
	_on_time_changed(TimeManager.get_total_minutes())


func _on_time_changed(_total_minutes: int) -> void:
	time_label.text = TimeManager.get_time_text()
