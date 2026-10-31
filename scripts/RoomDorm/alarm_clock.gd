extends RigidBody3D
## Настольный будильник: общие часы и близкое взаимодействие общей рукой.

signal switched_off()

@onready var _time_label: Label3D = $TimeLabel
@onready var _status_label: Label3D = $StatusLabel
@onready var _sound: AudioStreamPlayer3D = $AlarmSound
@onready var _indicator: MeshInstance3D = $Indicator

var _ringing: bool = false


func _ready() -> void:
	TimeManager.time_changed.connect(_on_time_changed)
	_on_time_changed(TimeManager.get_total_minutes())
	set_ringing(false)


func _on_time_changed(_total_minutes: int) -> void:
	_time_label.text = TimeManager.get_time_text()


func is_ringing() -> bool:
	return _ringing


func set_ringing(ringing: bool) -> void:
	_ringing = ringing
	_status_label.text = "ПОДЪЁМ" if ringing else "ВЫКЛ."
	_indicator.visible = ringing
	if ringing and not _sound.playing:
		_sound.play()
	elif not ringing:
		_sound.stop()


func interact() -> void:
	if not _ringing or SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	set_ringing(false)
	switched_off.emit()
