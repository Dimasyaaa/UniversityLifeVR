extends Control
## Показывает условия и состояние достижений из AchievementManager.

@onready var _achievements: Node = get_node("/root/AchievementManager")
@onready var _saves: Node = get_node("/root/SaveManager")
@onready var _counter: Label = $Margin/Content/Heading/Counter
@onready var _summary: Label = $Margin/Content/Summary
@onready var _status: Label = $Margin/Content/Card/Margin/Details/Status
@onready var _title: Label = $Margin/Content/Card/Margin/Details/Title
@onready var _description: Label = $Margin/Content/Card/Margin/Details/Description
@onready var _previous: Button = $Margin/Content/Pager/Previous
@onready var _next: Button = $Margin/Content/Pager/Next

var _selected_index: int = 0


func _ready() -> void:
	_previous.pressed.connect(_on_page_pressed.bind(-1))
	_next.pressed.connect(_on_page_pressed.bind(1))
	_achievements.connect("achievement_unlocked", _on_achievement_unlocked)
	_saves.connect("game_loaded", _on_day_started)
	_saves.connect("new_game_started", _on_day_started)
	_refresh()


func _refresh() -> void:
	var count: int = _achievements.achievement_definitions.size()
	var unlocked_count: int = _achievements.get_unlocked_achievement_ids().size()
	_summary.text = "Получено: %d из %d" % [unlocked_count, count]
	_counter.text = "%d / %d" % [_selected_index + 1, count]
	_previous.disabled = _selected_index == 0
	_next.disabled = _selected_index == count - 1
	var definition: AchievementDefinition = _achievements.achievement_definitions[_selected_index]
	var unlocked: bool = _achievements.is_achievement_unlocked(definition.achievement_id)
	_status.text = "Получено" if unlocked else "Не получено"
	_status.add_theme_color_override("font_color", Color(0.2, 0.4, 0.31) if unlocked else Color(0.43, 0.14, 0.19))
	_title.text = definition.title
	_description.text = definition.description


func _on_page_pressed(direction: int) -> void:
	_selected_index += direction
	_refresh()


func _on_achievement_unlocked(_achievement_id: StringName) -> void:
	_refresh()


func _on_day_started() -> void:
	_selected_index = 0
	_refresh()
