extends Node3D
## Локальный выбор футболки; сохраняется корнем комнаты через общий SaveManager.

signal outfit_changed(item_id: StringName)

const ClothingItem = preload("res://scripts/RoomDorm/clothing_item.gd")

@onready var _items: Array[ClothingItem] = [$Shirt1, $Shirt2, $Shirt3]
@onready var _caption: Label3D = $SelectionLabel

var _selected_outfit: StringName = &""


func _ready() -> void:
	for item: ClothingItem in _items:
		item.chosen.connect(select_outfit)
	_apply_selection()


func select_outfit(item_id: StringName) -> void:
	if SaveManager.is_loading() or SceneManager.is_transitioning() or _find_item(item_id) == null:
		return
	if _selected_outfit == item_id:
		return
	_selected_outfit = item_id
	_apply_selection()
	outfit_changed.emit(item_id)


func _find_item(item_id: StringName) -> ClothingItem:
	for item: ClothingItem in _items:
		if item.item_id == item_id:
			return item
	return null


func _apply_selection() -> void:
	for item: ClothingItem in _items:
		item.set_selected(item.item_id == _selected_outfit)
	var selected: ClothingItem = _find_item(_selected_outfit)
	_caption.text = "Выбрана: %s" % selected.display_name if selected != null else "Выберите футболку"


func get_save_data() -> Dictionary:
	return {"selected_outfit": String(_selected_outfit)}


func restore_save_data(data: Dictionary) -> void:
	_selected_outfit = &""
	var saved: Variant = data.get("selected_outfit", "")
	if saved is String or saved is StringName:
		var item_id: StringName = StringName(saved)
		if _find_item(item_id) != null:
			_selected_outfit = item_id
	_apply_selection()
