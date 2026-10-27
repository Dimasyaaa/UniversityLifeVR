extends Control
## Кнопки и сообщения меню паузы.

signal new_game_requested()
signal continue_requested()
signal exit_requested()
signal resume_requested()

@onready var _resume: Button = $Panel/Margin/Content/Buttons/Resume
@onready var _new_game: Button = $Panel/Margin/Content/Buttons/NewGame
@onready var _continue: Button = $Panel/Margin/Content/Buttons/Continue
@onready var _exit: Button = $Panel/Margin/Content/Buttons/Exit
@onready var _status: Label = $Panel/Margin/Content/Status

var _has_save: bool = false


func configure(has_save: bool) -> void:
	_has_save = has_save
	set_busy(false)
	_status.text = "" if has_save else "Сохранений пока нет."


func set_busy(busy: bool) -> void:
	_resume.disabled = busy
	_new_game.disabled = busy
	_continue.disabled = busy or not _has_save
	_exit.disabled = busy
	if busy:
		_status.text = "Загрузка…"


func show_error(message: String) -> void:
	set_busy(false)
	_status.text = message


func _on_new_game_pressed() -> void:
	new_game_requested.emit()


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()
