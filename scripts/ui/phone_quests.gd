extends Control
## Просмотр квестов и получение выбранного задания через QuestManager.

enum Category { ACTIVE, AVAILABLE, COMPLETED }

const STAT_NAMES: Dictionary[StringName, String] = {
	&"energy": "Энергия", &"satiety": "Сытость", &"knowledge": "Знания",
	&"money": "Деньги", &"mood": "Настроение", &"health": "Здоровье",
}

@onready var _quests: Node = get_node("/root/QuestManager")
@onready var _saves: Node = get_node("/root/SaveManager")
@onready var _categories: Array[Button] = [$Margin/Content/Categories/Active, $Margin/Content/Categories/Available, $Margin/Content/Categories/Completed]
@onready var _counter: Label = $Margin/Content/Heading/Counter
@onready var _status: Label = $Margin/Content/Card/Margin/Details/Status
@onready var _title: Label = $Margin/Content/Card/Margin/Details/Title
@onready var _description: Label = $Margin/Content/Card/Margin/Details/Description
@onready var _progress: Label = $Margin/Content/Card/Margin/Details/Progress
@onready var _rewards: Label = $Margin/Content/Card/Margin/Details/Rewards
@onready var _accept: Button = $Margin/Content/Card/Margin/Details/Accept
@onready var _previous: Button = $Margin/Content/Pager/Previous
@onready var _next: Button = $Margin/Content/Pager/Next

var _category: Category = Category.ACTIVE
var _quest_ids: Array[StringName] = []
var _selected_index: int = 0


func _ready() -> void:
	for index: int in range(_categories.size()):
		_categories[index].pressed.connect(_on_category_pressed.bind(index))
	_previous.pressed.connect(_on_page_pressed.bind(-1))
	_next.pressed.connect(_on_page_pressed.bind(1))
	_accept.pressed.connect(_on_accept_pressed)
	_quests.connect("quest_started", _on_quest_started)
	_quests.connect("quest_completed", _on_quest_completed)
	_quests.connect("quest_progress_changed", _on_quest_progress_changed)
	_saves.connect("game_loaded", _on_day_started)
	_saves.connect("new_game_started", _on_day_started)
	_refresh()


func _on_category_pressed(index: int) -> void:
	_category = index as Category
	_selected_index = 0
	_refresh()


func _on_page_pressed(direction: int) -> void:
	_selected_index += direction
	_show_card()


func _refresh(preferred_id: StringName = &"") -> void:
	if preferred_id == &"" and not _quest_ids.is_empty():
		preferred_id = _quest_ids[_selected_index]
	match _category:
		Category.ACTIVE:
			_quest_ids = _quests.get_active_quest_ids()
		Category.AVAILABLE:
			_quest_ids = _quests.get_available_quest_ids()
		Category.COMPLETED:
			_quest_ids = _quests.get_completed_quest_ids()
	var found: int = _quest_ids.find(preferred_id)
	_selected_index = found if found >= 0 else 0
	for index: int in range(_categories.size()):
		_categories[index].set_pressed_no_signal(index == _category)
	_show_card()


func _show_card() -> void:
	var count: int = _quest_ids.size()
	_counter.text = "%d / %d" % [0 if count == 0 else _selected_index + 1, count]
	_previous.disabled = _selected_index <= 0
	_next.disabled = _selected_index >= count - 1
	_accept.visible = count > 0 and _category == Category.AVAILABLE
	_progress.visible = count > 0
	_rewards.visible = count > 0
	if count == 0:
		_status.text = ""
		_title.text = "Здесь пока пусто"
		_description.text = ["Полученные задания появятся здесь.", "Доступных заданий пока нет.", "Завершённые задания появятся здесь."][_category]
		return
	var quest_id: StringName = _quest_ids[_selected_index]
	var definition: QuestDefinition = _quests.get_quest_definition(quest_id)
	_status.text = ["В процессе", "Доступен", "Выполнен"][_category]
	_title.text = definition.title
	_description.text = definition.description
	var progress: Dictionary = _quests.get_quest_progress(quest_id)
	var done: int = 0
	var required: int = 0
	for event_id: StringName in definition.required_events:
		required += definition.required_events[event_id]
		done += mini(int(progress.get(event_id, 0)), definition.required_events[event_id])
	_progress.text = "Прогресс: %d / %d" % [done, required]
	var rewards: PackedStringArray = []
	for stat_name: StringName in definition.stat_rewards:
		var amount: int = definition.stat_rewards[stat_name]
		if stat_name == &"health" and amount >= 100:
			rewards.append("Здоровье до 100")
		else:
			rewards.append("%s %s%d" % [STAT_NAMES[stat_name], "+" if amount > 0 else "", amount])
	_rewards.text = "Награда: %s" % (" · ".join(rewards) if not rewards.is_empty() else "—")


func _on_accept_pressed() -> void:
	var quest_id: StringName = _quest_ids[_selected_index]
	if _quests.give_quest(quest_id):
		_category = Category.ACTIVE
		_refresh(quest_id)


func _on_quest_started(_quest_id: StringName) -> void:
	_refresh()


func _on_quest_completed(quest_id: StringName) -> void:
	if not _quest_ids.is_empty() and _quest_ids[_selected_index] == quest_id:
		_category = Category.COMPLETED
		_refresh(quest_id)
	else:
		_refresh()


func _on_quest_progress_changed(_quest_id: StringName) -> void:
	_show_card()


func _on_day_started() -> void:
	_category = Category.ACTIVE
	_quest_ids.clear()
	_selected_index = 0
	_refresh()
