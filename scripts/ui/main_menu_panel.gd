extends Node3D
## Меню паузы: управление панелью, игроком и загрузкой дня.

const Menu = preload("res://scripts/ui/main_menu.gd")
const Player = preload("res://scripts/player/player.gd")

@export var menu_button_action: StringName = &"menu_button"
@export_range(0.8, 2.0, 0.05) var menu_distance: float = 1.15

@onready var _screen: XRToolsViewport2DIn3D = $Screen
@onready var _save_manager: Node = get_node("/root/SaveManager")

var _menu: Menu
var _player: Player
var _movement_was_enabled: bool = true
var _request_pending: bool = false


func setup(player: Player) -> void:
	_player = player
	_menu = _screen.get_scene_instance() as Menu
	_menu.new_game_requested.connect(_on_new_game_requested)
	_menu.continue_requested.connect(_on_continue_requested)
	_menu.exit_requested.connect(_on_exit_requested)
	_menu.resume_requested.connect(_on_resume_requested)
	_player.left_hand.button_pressed.connect(_on_controller_button_pressed)
	_save_manager.connect("new_game_started", _on_game_started)
	_save_manager.connect("game_loaded", _on_game_started)
	_save_manager.connect("game_load_failed", _on_game_load_failed)
	_screen.enabled = false
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_M and event.pressed and not event.echo:
		toggle_menu()
		get_viewport().set_input_as_handled()


func _on_controller_button_pressed(action: StringName) -> void:
	if action == menu_button_action:
		toggle_menu()


func toggle_menu() -> void:
	if _request_pending or _save_manager.is_loading() or SceneManager.is_transitioning():
		return
	if visible:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	_movement_was_enabled = _player.is_movement_enabled()
	_player.set_movement_enabled(false)
	TimeManager.set_time_suspended(true)
	_menu.configure(FileAccess.file_exists(_save_manager.SAVE_PATH))
	# Панель остаётся в мире, но при каждом открытии появляется перед головой.
	var camera: XRCamera3D = _player.camera
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -_player.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	global_position = camera.global_position + forward * menu_distance
	global_basis = Basis.looking_at(forward, Vector3.UP)
	show()
	_screen.enabled = true


func _close_menu() -> void:
	_screen.enabled = false
	hide()
	TimeManager.set_time_suspended(false)
	_player.set_movement_enabled(_movement_was_enabled)


func _on_resume_requested() -> void:
	if not _request_pending:
		_close_menu()


func _on_new_game_requested() -> void:
	_start_game(false)


func _on_continue_requested() -> void:
	_start_game(true)


func _start_game(from_save: bool) -> void:
	if _request_pending:
		return
	_request_pending = true
	_menu.set_busy(true)
	var accepted: bool
	if from_save:
		accepted = _save_manager.load_game()
	else:
		accepted = _save_manager.start_new_game()
	if not accepted:
		_request_pending = false
		if from_save:
			_menu.show_error("Не удалось загрузить сохранение. Можно начать новую игру.")
		else:
			_menu.show_error("Не удалось начать новую игру.")


func _on_game_started() -> void:
	_request_pending = false
	if visible:
		_close_menu()


func _on_game_load_failed(reason: String) -> void:
	if not _request_pending:
		return
	_request_pending = false
	_menu.show_error("Не удалось начать игру: %s" % reason)


func _on_exit_requested() -> void:
	get_tree().quit()


func _exit_tree() -> void:
	if is_instance_valid(_player) and visible:
		TimeManager.set_time_suspended(false)
		_player.set_movement_enabled(_movement_was_enabled)
