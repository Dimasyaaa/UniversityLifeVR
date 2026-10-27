extends "res://scripts/ui/main_menu_panel.gd"
## Поясняет несовместимость сохранения из технической TestRoom.
## Остальные действия меню выполняет общая реализация модуля 7.


func _on_continue_requested() -> void:
	var data: Dictionary = SaveManager.read_save_data()
	var saved_location: Dictionary = data.get("location", {})
	if saved_location.get("location_id", &"") == &"test_room" and not SceneManager.has_location(&"test_room"):
		var menu: Control = $Screen.get_scene_instance()
		menu.call("show_error", "Это сохранение из TestRoom.\nНачните новую игру в общежитии.")
		return
	super._on_continue_requested()
