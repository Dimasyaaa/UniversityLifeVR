extends Node3D
## Сообщения о квестах, достижениях и событиях дня. Показываются по очереди.

const Player = preload("res://scripts/player/player.gd")

@export_range(1.0, 10.0, 0.5) var display_seconds: float = 4.0
@export var view_offset: Vector3 = Vector3(0.0, 0.55, -1.25)

@onready var _quests: Node = get_node("/root/QuestManager")
@onready var _achievements: Node = get_node("/root/AchievementManager")
@onready var _events: Node = get_node("/root/RandomEventManager")
@onready var _saves: Node = get_node("/root/SaveManager")
@onready var _heading: Label3D = $Heading
@onready var _title: Label3D = $Title
@onready var _timer: Timer = $DisplayTimer
@onready var _sound: AudioStreamPlayer = $NotificationSound

var _camera: XRCamera3D
var _pause_menu: Node3D
var _messages: Array[Dictionary] = []


func _ready() -> void:
	set_process(false)
	_timer.timeout.connect(_show_next)


func setup(player: Player, pause_menu: Node3D) -> void:
	_camera = player.camera
	_pause_menu = pause_menu
	_quests.connect("quest_started", _on_quest_started)
	_quests.connect("quest_completed", _on_quest_completed)
	_achievements.connect("achievement_unlocked", _on_achievement_unlocked)
	_events.connect("event_started", _on_event_started)
	_saves.connect("game_loaded", _clear_messages)
	_saves.connect("new_game_started", _on_new_game_started)
	set_process(true)
	_on_new_game_started()


func _process(_delta: float) -> void:
	if not _timer.is_stopped():
		_update_panel()


func _update_panel() -> void:
	global_transform = _camera.global_transform * Transform3D(Basis.IDENTITY, view_offset)
	visible = not _pause_menu.visible
	_timer.paused = _pause_menu.visible
	_sound.stream_paused = _pause_menu.visible


func _enqueue(heading: String, title: String) -> void:
	# Выдача начальных квестов при новой игре происходит до завершения загрузки.
	if _saves.is_loading():
		return
	_messages.append({"heading": heading, "title": title})
	if _timer.is_stopped():
		_show_next()


func _show_next() -> void:
	if _messages.is_empty():
		hide()
		return
	var message: Dictionary = _messages.pop_front()
	_heading.text = message["heading"]
	_title.text = message["title"]
	_timer.start(display_seconds)
	_sound.play()
	_update_panel()


func _on_quest_started(quest_id: StringName) -> void:
	var definition: QuestDefinition = _quests.get_quest_definition(quest_id)
	_enqueue("Получено задание", definition.title)


func _on_quest_completed(quest_id: StringName) -> void:
	var definition: QuestDefinition = _quests.get_quest_definition(quest_id)
	_enqueue("Квест выполнен", definition.title)


func _on_achievement_unlocked(achievement_id: StringName) -> void:
	var definition: AchievementDefinition = _achievements.get_achievement_definition(achievement_id)
	_enqueue("Получено достижение", definition.title)


func _on_event_started(event_id: StringName) -> void:
	var definition: RandomEventDefinition = _events.get_event_definition(event_id)
	_enqueue("Событие дня", definition.description)


func _clear_messages() -> void:
	_messages.clear()
	_timer.stop()
	_timer.paused = false
	_sound.stop()
	_sound.stream_paused = false
	hide()


func _on_new_game_started() -> void:
	_clear_messages()
	for quest_id: StringName in _quests.get_active_quest_ids():
		_on_quest_started(quest_id)
