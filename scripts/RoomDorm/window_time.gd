extends Node3D
## Окно использует общие часы; освещение выводится из текущего времени.

signal waited()
signal cancelled()

const DormWakeup = preload("res://scripts/RoomDorm/dorm_wakeup.gd")
const Player = preload("res://scripts/player/player.gd")
const PERIODS: Array[Dictionary] = [
	{"minute": 720, "label": "Дождаться дня — 12:00"},
	{"minute": 1080, "label": "Дождаться вечера — 18:00"},
	{"minute": 1320, "label": "Дождаться ночи — 22:00"},
]
## Минуты, цвет неба, окружающего света, солнца и яркости.
const LIGHT_KEYS: Array[Dictionary] = [
	{"minute": 0, "sky": Color(0.025,0.045,0.09), "ambient": Color(0.48,0.58,0.8), "sun": Color(0.48,0.64,1.0), "ambient_energy": 0.26, "sun_energy": 0.12, "glow": 0.07, "street_energy": 0.25, "windows": 0.85, "angle": 0.28, "length": 1.0, "room_energy": 0.68},
	{"minute": 300, "sky": Color(0.26,0.29,0.42), "ambient": Color(0.7,0.72,0.87), "sun": Color(1.0,0.65,0.47), "ambient_energy": 0.33, "sun_energy": 0.45, "glow": 0.16, "street_energy": 0.65, "windows": 0.45, "angle": 0.2, "length": 1.1, "room_energy": 0.52},
	{"minute": 480, "sky": Color(0.57,0.76,0.88), "ambient": Color(1.0,0.85,0.68), "sun": Color(1.0,0.77,0.47), "ambient_energy": 0.40, "sun_energy": 0.65, "glow": 0.13, "street_energy": 1.0, "windows": 0.0, "angle": -0.28, "length": 1.1, "room_energy": 0.38},
	{"minute": 720, "sky": Color(0.42,0.69,0.88), "ambient": Color(0.87,0.95,1.0), "sun": Color(0.96,0.98,1.0), "ambient_energy": 0.60, "sun_energy": 0.85, "glow": 0.12, "street_energy": 1.15, "windows": 0.0, "angle": 0.0, "length": 0.7, "room_energy": 0.22},
	{"minute": 1080, "sky": Color(0.72,0.39,0.32), "ambient": Color(1.0,0.78,0.66), "sun": Color(1.0,0.53,0.27), "ambient_energy": 0.36, "sun_energy": 0.65, "glow": 0.20, "street_energy": 0.8, "windows": 0.4, "angle": 0.35, "length": 1.2, "room_energy": 0.48},
	{"minute": 1320, "sky": Color(0.025,0.045,0.09), "ambient": Color(0.48,0.58,0.8), "sun": Color(0.48,0.64,1.0), "ambient_energy": 0.26, "sun_energy": 0.12, "glow": 0.07, "street_energy": 0.25, "windows": 0.85, "angle": 0.28, "length": 1.0, "room_energy": 0.68},
	{"minute": 1440, "sky": Color(0.025,0.045,0.09), "ambient": Color(0.48,0.58,0.8), "sun": Color(0.48,0.64,1.0), "ambient_energy": 0.26, "sun_energy": 0.12, "glow": 0.07, "street_energy": 0.25, "windows": 0.85, "angle": 0.28, "length": 1.0, "room_energy": 0.68},
]

@onready var _sun: SpotLight3D = $Sunlight
@onready var _patch: MeshInstance3D = $FloorLight
@onready var _screen: XRToolsViewport2DIn3D = $Screen
@onready var _bed_screen: Node3D = $"../BedRestScreen"
@onready var _room_light: OmniLight3D = $"../RoomLight"

var _environment: Environment
var _street_light: DirectionalLight3D
var _lit_windows: StandardMaterial3D
var _wakeup: DormWakeup
var _confirm: Button
var _menu: Node3D
var _prompt_open: bool = false
var _target_minute: int = -1
var _hover_latched: Dictionary[int, bool] = {}


func _ready() -> void:
	set_process(false)
	var panel: Node = _screen.get_scene_instance()
	_confirm = panel.get_node("Panel/Margin/Buttons/Confirm")
	_confirm.pressed.connect(_confirm_wait)
	panel.get_node("Panel/Margin/Buttons/Cancel").pressed.connect(_cancel_prompt)
	_screen.pointer_event.connect(_on_window_pointer_seen)
	TimeManager.time_changed.connect(_on_time_changed)
	SceneManager.transition_started.connect(_on_transition_started)
	SaveManager.game_loaded.connect(_sync_lighting)
	SaveManager.new_game_started.connect(_sync_lighting)
	_close_prompt()


func setup(environment: Environment, street: Node3D, wakeup: DormWakeup) -> void:
	_environment = environment
	_street_light = street.get_node("Daylight")
	_lit_windows = street.get_node("LitWindows").material_override as StandardMaterial3D
	_wakeup = wakeup
	_sync_lighting()


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
	# Цель фиксируется: если часы дошли до неё, новое ожидание не подставляется.
	_target_minute = -1
	for period: Dictionary in PERIODS:
		if period["minute"] * 60.0 > TimeManager.get_total_seconds():
			_target_minute = period["minute"]
			_confirm.text = period["label"]
			break
	if _target_minute < 0:
		_confirm.text = "На сегодня ожидание закончено"
	# Панель имеет сохранённое место у нижней части окна, не следует за головой.
	_prompt_open = true
	_screen.show()
	_screen.enabled = true
	_update_button()
	set_process(true)


func _on_window_pointer_seen(event: XRToolsPointerEvent) -> void:
	# Используем события существующего FunctionPointer без нового опроса ввода.
	if not event.pointer.is_connected(&"pointing_event", _on_pointer_event):
		event.pointer.connect(&"pointing_event", _on_pointer_event)
		_on_pointer_event(event)


func _on_pointer_event(event: XRToolsPointerEvent) -> void:
	var in_window: bool = event.target == $InteractionBody or event.target == _screen.get_node("StaticBody3D")
	if not in_window:
		return
	if event.event_type == XRToolsPointerEvent.Type.EXITED:
		# EXITED стекла сразу перед ENTERED кнопок ещё не означает уход от окна.
		_rearm_after_exit.call_deferred(event.pointer)
	elif event.event_type == XRToolsPointerEvent.Type.ENTERED:
		var pointer_id: int = event.pointer.get_instance_id()
		var fresh: bool = not _hover_latched.get(pointer_id, false)
		_hover_latched[pointer_id] = true
		if fresh and event.target == $InteractionBody:
			interact()


func _rearm_after_exit(pointer: Node3D) -> void:
	if not is_instance_valid(pointer):
		return
	var target: Node3D = pointer.get("last_target") as Node3D
	if target != $InteractionBody and target != _screen.get_node("StaticBody3D"):
		_hover_latched.erase(pointer.get_instance_id())


func _can_interact() -> bool:
	return is_instance_valid(_wakeup) and not _wakeup.is_lying() and not _wakeup.is_rising() and not _bed_screen.visible and not SaveManager.is_loading() and not SceneManager.is_transitioning() and not get_tree().paused


func _process(_delta: float) -> void:
	if not _can_interact() or (_menu != null and _menu.visible):
		_close_prompt()
		return
	_update_button()


func _update_button() -> void:
	_confirm.disabled = _target_minute < 0 or TimeManager.get_total_seconds() >= _target_minute * 60.0
	if _target_minute >= 0 and _confirm.disabled:
		_confirm.text = "Это время уже наступило"


func _confirm_wait() -> void:
	if not _prompt_open or not _can_interact() or (_menu != null and _menu.visible):
		return
	_update_button()
	if _confirm.disabled:
		return
	var target: int = _target_minute
	_close_prompt()
	# Общий API принимает целые минуты; сохраняем его дробные секунды.
	# Например, 08:00:12 -> 12:00:12. Внутренние поля часов не меняем.
	TimeManager.advance_minutes(target - TimeManager.get_total_minutes())
	waited.emit()


func _cancel_prompt() -> void:
	if not _prompt_open:
		return
	_close_prompt()
	cancelled.emit()


func _close_prompt() -> void:
	_prompt_open = false
	_target_minute = -1
	set_process(false)
	if is_instance_valid(_screen):
		_screen.enabled = false
		_screen.hide()


func _on_menu_visibility_changed() -> void:
	if _menu != null and _menu.visible:
		_close_prompt()


func _on_transition_started(_location_id: StringName) -> void:
	_close_prompt()


func _on_time_changed(_total_minutes: int) -> void:
	_sync_lighting()


func _sync_lighting() -> void:
	if _environment == null or not is_instance_valid(_street_light):
		return
	var minute: float = TimeManager.get_total_seconds() / 60.0
	var a: Dictionary = LIGHT_KEYS[0]
	var b: Dictionary = LIGHT_KEYS[1]
	for i: int in range(1, LIGHT_KEYS.size()):
		a = LIGHT_KEYS[i-1]
		b = LIGHT_KEYS[i]
		if minute <= float(b["minute"]):
			break
	var t: float = clampf((minute-float(a["minute"]))/float(b["minute"]-a["minute"]),0.0,1.0)
	var sunlight: Color = (a["sun"] as Color).lerp(b["sun"],t)
	_environment.background_color = (a["sky"] as Color).lerp(b["sky"],t)
	_environment.ambient_light_color = (a["ambient"] as Color).lerp(b["ambient"],t)
	_environment.ambient_light_energy = lerpf(a["ambient_energy"],b["ambient_energy"],t)
	_room_light.light_energy = lerpf(a["room_energy"],b["room_energy"],t)
	# Карту отражений не пересчитываем каждую минуту.
	_sun.light_color = sunlight
	_sun.light_energy = lerpf(a["sun_energy"],b["sun_energy"],t)
	_patch.rotation.y = lerpf(a["angle"],b["angle"],t)
	var length: float = lerpf(a["length"],b["length"],t)
	_patch.scale.z = length
	_patch.position.z = -2.6 + 1.35 * length
	var patch_material: ShaderMaterial = _patch.material_override as ShaderMaterial
	patch_material.set_shader_parameter("light_color",sunlight)
	patch_material.set_shader_parameter("strength",lerpf(a["glow"],b["glow"],t))
	_street_light.light_color = sunlight
	_street_light.light_energy = lerpf(a["street_energy"],b["street_energy"],t)
	_lit_windows.emission_energy_multiplier = lerpf(a["windows"],b["windows"],t)


func _exit_tree() -> void:
	_close_prompt()
