extends Node3D
## Смартфон в правой руке: показ экрана по Tab или кнопке A.

const Player = preload("res://scripts/player/player.gd")

@export var phone_button_action: StringName = &"ax_button"

@onready var _save_manager: Node = get_node("/root/SaveManager")
@onready var _screen: XRToolsViewport2DIn3D = $Screen

var _pause_menu: Node3D


func setup(player: Player, pause_menu: Node3D) -> void:
	_pause_menu = pause_menu
	player.right_hand.button_pressed.connect(_on_controller_button_pressed)
	_pause_menu.visibility_changed.connect(_on_pause_menu_visibility_changed)
	hide_phone()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_TAB and event.pressed and not event.echo:
		toggle_phone()
		get_viewport().set_input_as_handled()


func _on_controller_button_pressed(action: StringName) -> void:
	if action == phone_button_action:
		toggle_phone()


func toggle_phone() -> void:
	if _pause_menu.visible or _save_manager.is_loading() or SceneManager.is_transitioning():
		return
	visible = not visible
	_screen.enabled = visible


func hide_phone() -> void:
	hide()
	_screen.enabled = false


func _on_pause_menu_visibility_changed() -> void:
	if _pause_menu.visible:
		hide_phone()
