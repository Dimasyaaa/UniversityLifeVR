extends Control
## Переключение разделов смартфона.

@onready var _pages: Array[Control] = [$Pages/Status, $Pages/Quests, $Pages/Achievements, $Pages/Statistics]


func _ready() -> void:
	for index: int in range(_pages.size()):
		$Navigation.get_child(index).pressed.connect(_show_page.bind(index))


func _show_page(index: int) -> void:
	for page_index: int in range(_pages.size()):
		_pages[page_index].visible = page_index == index
