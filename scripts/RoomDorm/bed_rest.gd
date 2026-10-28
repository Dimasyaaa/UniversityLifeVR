extends Node3D
## Подтверждённый сон на кровати игрока; время и Энергия принадлежат общим системам.

signal rested()
signal cancelled()

const DormWakeup = preload("res://scripts/RoomDorm/dorm_wakeup.gd")
const Player = preload("res://scripts/player/player.gd")

@export_range(1, 100, 1) var energy_gain: int = 15
@export_range(1, 120, 1) var sleep_minutes: int = 30

var _wakeup: DormWakeup
var _screen: XRToolsViewport2DIn3D
var _confirm: Button
var _menu: Node3D
var _prompt_open: bool = false


func _ready() -> void:
	set_process(false)
	# Используем существующие коллизии кровати, без дополнительной сплошной формы.
	for body: Node in find_children("*", "StaticBody3D", true, false):
		body.add_to_group(&"interactable")


func setup(wakeup: DormWakeup, screen: XRToolsViewport2DIn3D) -> void:
	_wakeup = wakeup
	_screen = screen
	var panel: Node = _screen.get_scene_instance()
	_confirm = panel.get_node("Panel/Margin/Buttons/Confirm")
	_confirm.pressed.connect(_confirm_rest)
	panel.get_node("Panel/Margin/Buttons/Cancel").pressed.connect(_cancel_prompt)
	SceneManager.transition_started.connect(_on_transition_started)
	_close_prompt()


func interact() -> void:
	if _prompt_open or not _can_interact():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not camera.get_parent().get_parent() is Player:
		return
	var player: Player = camera.get_parent().get_parent()
	_menu = player.get_parent().get_node_or_null("MainMenuPanel") as Node3D
	if _menu != null:
		if _menu.visible:
			return
		if not _menu.visibility_changed.is_connected(_on_menu_visibility_changed):
			_menu.visibility_changed.connect(_on_menu_visibility_changed)
	_screen.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.08, -0.95))
	_prompt_open = true
	_screen.show()
	_screen.enabled = true
	_update_button()
	set_process(true)


func _can_interact() -> bool:
	return is_instance_valid(_screen) and is_instance_valid(_wakeup) and not _wakeup.is_lying() and not _wakeup.is_rising() and not SaveManager.is_loading() and not SceneManager.is_transitioning() and not get_tree().paused


func _has_time_for_rest() -> bool:
	return TimeManager.get_total_seconds() + sleep_minutes * 60.0 <= TimeManager.SECONDS_PER_DAY + 0.000001


func _process(_delta: float) -> void:
	if not _can_interact() or (_menu != null and _menu.visible):
		_close_prompt()
		return
	_update_button()


func _update_button() -> void:
	_confirm.disabled = not _has_time_for_rest()
	_confirm.text = "Поспать %d минут" % sleep_minutes if not _confirm.disabled else "До конца дня меньше %d минут" % sleep_minutes


func _confirm_rest() -> void:
	if not _prompt_open or not _can_interact() or (_menu != null and _menu.visible):
		return
	if not _has_time_for_rest():
		_update_button()
		return
	# Закрываем и сбрасываем флаг до сигналов общих менеджеров: один клик — один сон.
	_close_prompt()
	GameStateManager.change_stat(&"energy", energy_gain)
	TimeManager.advance_minutes(sleep_minutes)
	rested.emit()


func _cancel_prompt() -> void:
	if not _prompt_open:
		return
	_close_prompt()
	cancelled.emit()


func _close_prompt() -> void:
	_prompt_open = false
	set_process(false)
	if is_instance_valid(_screen):
		_screen.enabled = false
		_screen.hide()


func _on_menu_visibility_changed() -> void:
	if _menu != null and _menu.visible:
		_close_prompt()


func _on_transition_started(_location_id: StringName) -> void:
	_close_prompt()


func _exit_tree() -> void:
	_close_prompt()
