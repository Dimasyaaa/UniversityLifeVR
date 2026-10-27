extends Control
## Заработок и посещения за день. Данные хранит StatisticsManager.

@export var location_names: Dictionary[StringName, String] = {&"test_room": "Тестовая комната"}

@onready var _statistics: Node = get_node("/root/StatisticsManager")
@onready var _time: Node = get_node("/root/TimeManager")
@onready var _saves: Node = get_node("/root/SaveManager")
@onready var _money: Label = $Margin/Content/Earnings/Margin/Details/Value
@onready var _counter: Label = $Margin/Content/Locations/Counter
@onready var _location_title: Label = $Margin/Content/Card/Margin/Details/Title
@onready var _visits: Label = $Margin/Content/Card/Margin/Details/Visits
@onready var _time_caption: Label = $Margin/Content/Card/Margin/Details/TimeCaption
@onready var _time_value: Label = $Margin/Content/Card/Margin/Details/TimeValue
@onready var _previous: Button = $Margin/Content/Pager/Previous
@onready var _next: Button = $Margin/Content/Pager/Next

var _location_ids: Array[StringName] = []
var _selected_index: int = 0


func _ready() -> void:
	_previous.pressed.connect(_on_page_pressed.bind(-1))
	_next.pressed.connect(_on_page_pressed.bind(1))
	_statistics.connect("money_earned_changed", _on_money_earned_changed)
	_statistics.connect("location_visited", _on_location_visited)
	_time.connect("time_changed", _on_time_changed)
	_saves.connect("game_loaded", _on_day_started)
	_saves.connect("new_game_started", _on_day_started)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _refresh() -> void:
	_money.text = str(_statistics.get_money_earned())
	_location_ids = _statistics.get_visited_location_ids()
	_selected_index = mini(_selected_index, maxi(_location_ids.size() - 1, 0))
	_show_location()


func _show_location() -> void:
	var count: int = _location_ids.size()
	_counter.text = "%d / %d" % [0 if count == 0 else _selected_index + 1, count]
	_previous.disabled = _selected_index == 0
	_next.disabled = _selected_index >= count - 1
	_visits.visible = count > 0
	_time_caption.visible = count > 0
	_time_value.visible = count > 0
	if count == 0:
		_location_title.text = "Пока нет посещённых локаций"
		return
	var location_id: StringName = _location_ids[_selected_index]
	_location_title.text = location_names.get(location_id, "Локация %d" % (_selected_index + 1))
	_visits.text = "Посещений: %d" % _statistics.get_location_visit_count(location_id)
	_update_time()


func _update_time() -> void:
	if _location_ids.is_empty():
		return
	var seconds: float = _statistics.get_location_time_seconds(_location_ids[_selected_index])
	var hours: int = floori(seconds / 3600.0)
	var minutes: int = floori(seconds / 60.0) % 60
	_time_value.text = "%02d ч %02d мин" % [hours, minutes]


func _on_page_pressed(direction: int) -> void:
	_selected_index += direction
	_show_location()


func _on_money_earned_changed(total: int) -> void:
	_money.text = str(total)


func _on_location_visited(_location_id: StringName, _visits_count: int) -> void:
	_refresh()


func _on_time_changed(_total_minutes: int) -> void:
	_update_time()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func _on_day_started() -> void:
	_selected_index = 0
	_refresh()
