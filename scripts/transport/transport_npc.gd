extends StaticBody3D
## Студентка на остановке: диалог, однократная помощь и состояние для общего SaveManager.

const Player = preload("res://scripts/player/player.gd")
const Transport = preload("res://scripts/transport/transport_controller.gd")
const StudentPass = preload("res://scripts/transport/student_pass.gd")
const MONEY_HELP_AMOUNT: int = 40

signal conversation_progress_changed

@export_group("Conversation")
@export_range(1.0, 3.0, 0.1) var conversation_distance: float = 2.4
@export_range(0.7, 1.3, 0.05) var dialogue_distance: float = 0.9
@export var speaker_name: String = "Студентка"
@export_multiline var greeting: String = "Привет! Тоже едешь на занятия?"
@export_multiline var route_answer: String = "Да, маршрут №1 идёт от общежития к университету. Выходи на конечной — вход на территорию рядом с остановкой."

@export_group("Money Help")
@export_multiline var money_refusal: String = "Извини, я сама рассчитывала на эти деньги."
@export_multiline var money_acceptance: String = "Ладно, держи 40 рублей. Удачи на занятиях!"
@export_multiline var money_already_given: String = "Я уже дала тебе 40 рублей."

@export_group("Lost Pass")
@export_multiline var pass_request: String = "Да! Я потеряла пропуск среди деревьев справа от дорожки, по пути от общежития к остановке. Найди его и принеси мне, пожалуйста."
@export_multiline var pass_reminder: String = "Поищи пропуск среди деревьев справа от дорожки, если выйти из общежития. Возьми его в руку, поднеси ко мне и нажми «Вернуть пропуск»."
@export_multiline var pass_thanks: String = "Спасибо! Теперь я точно попаду на занятия. Ты меня очень выручила!"

@onready var _transport: Transport = get_parent() as Transport
@onready var _screen: XRToolsViewport2DIn3D = $Dialogue
@onready var _hint: Label3D = $TalkHint
@onready var _talk_point: Marker3D = $TalkPoint
@onready var _student_pass: StudentPass = $"../StudentPass"

var _message: Label
var _route_button: Button
var _duration_button: Button
var _money_button: Button
var _quest_button: Button
var _close_button: Button
var _open_requested: bool = false
## 0 — не просили, 1 — отказ, 2 — помощь уже получена. Одного поля достаточно для сохранения.
var _money_requests: int = 0
var _last_money_request_frame: int = -1
var _last_quest_action_frame: int = -1


func _ready() -> void:
	var ui: Control = _screen.get_scene_instance() as Control
	var content: Node = ui.get_node("Panel/Margin/Content")
	(content.get_node("Speaker") as Label).text = speaker_name
	_message = content.get_node("Message") as Label
	_route_button = content.get_node("Questions/Route") as Button
	_duration_button = content.get_node("Questions/Duration") as Button
	_money_button = content.get_node("Questions/Money") as Button
	_quest_button = content.get_node("Questions/Quest") as Button
	_close_button = content.get_node("Questions/Close") as Button
	_route_button.pressed.connect(_on_route_pressed)
	_duration_button.pressed.connect(_on_duration_pressed)
	_money_button.pressed.connect(_on_money_pressed)
	_quest_button.pressed.connect(_on_quest_pressed)
	_close_button.pressed.connect(_close_dialogue)
	_close_dialogue()
	_hint.hide()
	_refresh_quest_button()


func _process(_delta: float) -> void:
	var available: bool = _can_talk(_get_player())
	if not available:
		_close_dialogue()
	_hint.visible = available and not _screen.visible and not _open_requested
	if _screen.visible:
		_refresh_quest_button()


func interact() -> void:
	if _screen.visible or _open_requested or not _can_talk(_get_player()):
		return
	# VRGrab вызывает interact() из физического кадра. Коллизию панели включаем позже.
	_open_requested = true
	_open_dialogue.call_deferred()


func _open_dialogue() -> void:
	_open_requested = false
	var player: Player = _get_player()
	if not _can_talk(player):
		return
	var forward: Vector3 = -player.camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -player.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	# Панель остаётся в мире: поворот головы не тащит за собой текст.
	_screen.global_position = player.camera.global_position + forward * dialogue_distance - Vector3.UP * 0.08
	_screen.global_basis = Basis.looking_at(forward, Vector3.UP)
	_message.text = greeting
	_refresh_quest_button()
	_screen.show()
	_screen.enabled = true
	_hint.hide()


func _close_dialogue() -> void:
	if _screen.enabled:
		_screen.enabled = false
	if _screen.visible:
		_screen.hide()


func _on_route_pressed() -> void:
	if _screen.visible and _can_talk(_get_player()):
		_message.text = route_answer


func _on_duration_pressed() -> void:
	if not _screen.visible or not _can_talk(_get_player()):
		return
	# Оценка из уже настроенной поездки и общих часов; время здесь не начисляется.
	var minutes: int = maxi(1, roundi(_transport.ride_duration_seconds * TimeManager.game_seconds_per_real_second / 60.0))
	_message.text = "Примерно %d мин. Можно выбрать место, посмотреть в окно или достать телефон. У университета выходи на конечной." % minutes


func _on_money_pressed() -> void:
	if not _screen.visible or not _can_talk(_get_player()):
		return
	var frame: int = Engine.get_process_frames()
	if _last_money_request_frame == frame:
		# Дубли одного сигнала в том же кадре не считаются второй просьбой.
		return
	_last_money_request_frame = frame
	match _money_requests:
		0:
			_money_requests = 1
			_message.text = money_refusal
			conversation_progress_changed.emit()
		1:
			# Сначала фиксируем получение, затем уведомляем общие системы о деньгах.
			_money_requests = 2
			GameStateManager.change_stat(&"money", MONEY_HELP_AMOUNT)
			_message.text = money_acceptance
			conversation_progress_changed.emit()
		_:
			_message.text = money_already_given


func _refresh_quest_button() -> void:
	var completed: bool = QuestManager.is_quest_completed(StudentPass.QUEST_ID)
	_quest_button.visible = not completed
	_quest_button.disabled = completed
	if completed:
		return
	if QuestManager.is_quest_active(StudentPass.QUEST_ID):
		_quest_button.text = "Вернуть пропуск"
	else:
		_quest_button.text = "Нужна помощь?"


func _on_quest_pressed() -> void:
	var player: Player = _get_player()
	if not _screen.visible or not _quest_button.visible or not _can_talk(player):
		return
	var frame: int = Engine.get_process_frames()
	if _last_quest_action_frame == frame:
		return
	_last_quest_action_frame = frame
	if QuestManager.is_quest_completed(StudentPass.QUEST_ID):
		_refresh_quest_button()
		return
	elif not QuestManager.is_quest_active(StudentPass.QUEST_ID):
		if QuestManager.give_quest(StudentPass.QUEST_ID):
			_message.text = pass_request
			conversation_progress_changed.emit()
	elif _student_pass.try_return(player):
		_message.text = pass_thanks
	else:
		_message.text = pass_reminder
	_refresh_quest_button()


func get_save_data() -> Dictionary:
	return {"money_requests": _money_requests}


func restore_save_data(data: Variant) -> void:
	_close_dialogue()
	_last_money_request_frame = -1
	_last_quest_action_frame = -1
	if data is Dictionary and data.get("money_requests") is int and data["money_requests"] >= 0 and data["money_requests"] <= 2:
		_money_requests = data["money_requests"]
	else:
		# Повреждённый прогресс не должен открывать повторную выдачу денег.
		_money_requests = 2
		push_warning("Студентка: повреждён прогресс помощи; повторная выдача денег отключена.")


func _get_player() -> Player:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	return camera.get_parent().get_parent() as Player


func _can_talk(player: Player) -> bool:
	return (
		is_instance_valid(_transport)
		and is_instance_valid(player)
		and SceneManager.get_current_location() == _transport
		and not SceneManager.is_transitioning()
		and not SaveManager.is_loading()
		and not TimeManager.is_time_paused()
		and player.is_movement_enabled()
		and not player.is_passenger_mode()
		and _transport.state in [Transport.State.BEFORE_WAITING, Transport.State.APPROACHING, Transport.State.OPENING_DOORS, Transport.State.BOARDING_READY]
		and player.camera.global_position.distance_to(_talk_point.global_position) <= conversation_distance
	)
