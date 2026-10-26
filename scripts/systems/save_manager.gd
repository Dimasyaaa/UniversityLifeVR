extends Node
## Сохранение, загрузка и запуск нового дня через SceneManager.

signal game_loaded()
signal new_game_started()
signal game_load_failed(reason: String)

const SAVE_PATH: String = "user://save.cfg"
const FORMAT_VERSION: int = 1
const SAVE_SECTIONS: Array[String] = [
	"stats", "time", "quests", "achievements", "statistics", "events", "location",
]

var _loading: bool = false
var _starting_new_game: bool = false
var _previous_data: Dictionary = {}
var _tree_was_paused: bool = false
var _autosave_pending: bool = false
var _location_states: Dictionary = {}


func _ready() -> void:
	SceneManager.location_unloading.connect(_on_location_unloading)
	SceneManager.location_loaded.connect(_on_location_loaded)
	SceneManager.location_changed.connect(_on_location_changed)
	SceneManager.transition_failed.connect(_on_transition_failed)
	QuestManager.quest_completed.connect(_on_quest_completed)


func is_loading() -> bool:
	return _loading


func save_game() -> bool:
	if _loading or SceneManager.is_transitioning():
		push_warning("SaveManager: дождитесь окончания перехода между локациями.")
		return false
	var data: Dictionary = _collect_save_data()
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", FORMAT_VERSION)
	for section: String in SAVE_SECTIONS:
		config.set_value(section, "data", data[section])
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		push_warning("SaveManager: не удалось записать сохранение: %s" % error_string(error))
		return false
	return true


func load_game() -> bool:
	# Как у SceneManager: true означает, что запрос принят.
	if _loading or SceneManager.is_transitioning():
		return false
	var data: Dictionary = read_save_data()
	if data.is_empty():
		return false
	if not _is_save_data_valid(data):
		push_warning("SaveManager: сохранение содержит неверные или несовместимые данные.")
		return false
	_prepare_load()
	QuestManager.set_events_enabled(false)
	# Не меняем менеджеры внутри обработчика квеста или события времени.
	_begin_load.call_deferred(data)
	return true


func start_new_game() -> bool:
	if _loading or SceneManager.is_transitioning():
		return false
	var initial_location_id: StringName = SceneManager.get_initial_location_id()
	if not SceneManager.has_location(initial_location_id):
		push_warning("SaveManager: сначала нужно подключить Main с начальной локацией.")
		return false
	_prepare_load()
	_starting_new_game = true
	_begin_new_game.call_deferred(initial_location_id)
	return true


func _prepare_load() -> void:
	_autosave_pending = false
	_previous_data = _collect_save_data()
	_tree_was_paused = get_tree().paused
	_loading = true
	get_tree().paused = true


func _collect_save_data() -> Dictionary:
	_capture_current_location()
	return {
		"stats": GameStateManager.get_stats(),
		"time": TimeManager.get_save_data(),
		"quests": QuestManager.get_save_data(),
		"achievements": AchievementManager.get_save_data(),
		"statistics": StatisticsManager.get_save_data(),
		"events": RandomEventManager.get_save_data(),
		"location": {
			"location_id": SceneManager.get_current_location_id(),
			"states": _location_states.duplicate(true),
		},
	}


func read_save_data() -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(SAVE_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return {}
	if error != OK:
		push_warning("SaveManager: не удалось прочитать сохранение: %s" % error_string(error))
		return {}
	if config.get_value("meta", "version", 0) != FORMAT_VERSION:
		push_warning("SaveManager: неподдерживаемая версия сохранения.")
		return {}
	var data: Dictionary = {}
	for section: String in SAVE_SECTIONS:
		var section_data: Variant = null
		if config.has_section_key(section, "data"):
			section_data = config.get_value(section, "data")
		if not section_data is Dictionary:
			push_warning("SaveManager: отсутствует или повреждён раздел: %s" % section)
			return {}
		data[section] = section_data
	# Старые сохранения версии 1 ещё не содержат состояний локаций.
	if not data["location"].has("states"):
		data["location"]["states"] = {}
	return data


func _begin_load(data: Dictionary) -> void:
	_restore_data(data)
	if not SceneManager.change_location(data["location"]["location_id"]):
		_cancel_load("Не удалось начать переход в сохранённую локацию.")


func _begin_new_game(initial_location_id: StringName) -> void:
	_location_states.clear()
	TimeManager.reset_time()
	GameStateManager.reset_stats(false)
	StatisticsManager.reset_statistics()
	AchievementManager.reset_achievements()
	RandomEventManager.reset_events()
	# Начальные квесты выдаём после сброса остальных данных дня.
	QuestManager.reset_quests()
	if not SceneManager.change_location(initial_location_id):
		_cancel_load("Не удалось начать переход в начальную локацию.")


func _restore_data(data: Dictionary) -> void:
	# Сначала восстанавливаем всё без сигналов о наградах, посещениях и событиях.
	_location_states = data["location"]["states"].duplicate(true)
	TimeManager.restore_save_data(data["time"])
	GameStateManager.restore_save_data(data["stats"])
	QuestManager.restore_save_data(data["quests"])
	StatisticsManager.restore_save_data(data["statistics"])
	AchievementManager.restore_save_data(data["achievements"])
	RandomEventManager.restore_save_data(data["events"])


func _capture_current_location() -> void:
	# При загрузке нельзя затереть прочитанные данные состоянием старой комнаты.
	if _loading:
		return
	var location: Node3D = SceneManager.get_current_location()
	if not is_instance_valid(location) or not location.has_method("get_save_data"):
		return
	var state: Dictionary = location.call("get_save_data")
	_location_states[String(SceneManager.get_current_location_id())] = state.duplicate(true)


func _on_location_unloading(_location_id: StringName) -> void:
	_capture_current_location()


func _on_location_loaded(location_id: StringName) -> void:
	var location: Node3D = SceneManager.get_current_location()
	var key: String = String(location_id)
	if _location_states.has(key) and location.has_method("restore_save_data"):
		location.call("restore_save_data", _location_states[key].duplicate(true))


func _on_location_changed(_location_id: StringName, _spawn_name: StringName) -> void:
	if not _loading:
		_request_autosave()
		return
	var started_new_game: bool = _starting_new_game
	_previous_data.clear()
	_finish_load()
	if started_new_game:
		new_game_started.emit()
	else:
		game_loaded.emit()


func _on_transition_failed(_location_id: StringName, reason: String) -> void:
	if _loading:
		_cancel_load(reason)
	elif _autosave_pending:
		# Квест мог завершиться, пока обычный переход ещё выполнялся.
		_try_autosave.call_deferred()


func _on_quest_completed(_quest_id: StringName) -> void:
	_request_autosave()


func _request_autosave() -> void:
	if _loading or SceneManager.get_current_location_id() == &"":
		return
	_autosave_pending = true
	# Сохраняем после обработки события, когда все награды уже начислены.
	_try_autosave.call_deferred()


func _try_autosave() -> void:
	if not _autosave_pending:
		return
	if _loading or SceneManager.get_current_location_id() == &"":
		_autosave_pending = false
		return
	if SceneManager.is_transitioning():
		return
	_autosave_pending = false
	save_game()


func _cancel_load(reason: String) -> void:
	_restore_data(_previous_data)
	_previous_data.clear()
	_finish_load()
	game_load_failed.emit(reason)


func _finish_load() -> void:
	QuestManager.set_events_enabled(true)
	_loading = false
	_starting_new_game = false
	get_tree().paused = _tree_was_paused
	# Интерфейс обновляется после согласованного восстановления всех менеджеров.
	GameStateManager.notify_stats_changed()
	TimeManager.notify_time_changed()


func _is_save_data_valid(data: Dictionary) -> bool:
	var expected: Dictionary = _collect_save_data()
	# Посещённые комнаты и их поля у разных сохранений могут отличаться.
	expected["location"]["states"] = {}
	if not _matches_fields(data, expected):
		return false
	for state: Variant in data["location"]["states"].values():
		if not state is Dictionary:
			return false
	for stat_name: StringName in GameStateManager.get_stats():
		if not data["stats"].has(stat_name):
			return false
	var location_id: StringName = data["location"]["location_id"]
	if not SceneManager.has_location(location_id) or data["statistics"]["current_location_id"] != location_id:
		return false
	var seconds: float = data["time"]["total_seconds"]
	if not is_finite(seconds) or seconds < 0.0 or seconds > TimeManager.SECONDS_PER_DAY:
		return false
	var quests: Dictionary = data["quests"]
	for quest_id: StringName in quests["active_ids"] + quests["completed_ids"]:
		var definition: QuestDefinition = QuestManager.get_quest_definition(quest_id)
		if definition == null or not quests["progress"].has(quest_id):
			return false
		for event_id: StringName in definition.required_events:
			if not quests["progress"][quest_id].get(event_id) is int:
				return false
	var achievements: Dictionary = data["achievements"]
	for achievement_id: StringName in achievements["unlocked_ids"] + achievements["timed_event_elapsed_ms"].keys():
		if AchievementManager.get_achievement_definition(achievement_id) == null:
			return false
	for elapsed_ms: int in achievements["timed_event_elapsed_ms"].values():
		if elapsed_ms < 0:
			return false
	for event_id: StringName in data["events"]["active_ids"] + data["events"]["finished_ids"]:
		if RandomEventManager.get_event_definition(event_id) == null:
			return false
	return true


func _matches_fields(data: Dictionary, example: Dictionary) -> bool:
	# Проверяем обязательные поля и типы перед изменением текущей игры.
	for key: Variant in example:
		if not data.has(key) or typeof(data[key]) != typeof(example[key]):
			return false
		if example[key] is Dictionary:
			if example[key].is_typed():
				if not data[key].is_same_typed(example[key]):
					return false
			elif not _matches_fields(data[key], example[key]):
				return false
		elif example[key] is Array and not data[key].is_same_typed(example[key]):
			return false
	return true
