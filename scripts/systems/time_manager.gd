extends Node
## Общие часы дня. Скорость влияет только на игровое время.

signal time_changed(total_minutes: int)
signal time_event_reached(event_id: StringName, scheduled_minutes: int)

const SECONDS_PER_MINUTE: float = 60.0
const MINUTES_PER_DAY: int = 24 * 60
const SECONDS_PER_DAY: float = MINUTES_PER_DAY * SECONDS_PER_MINUTE
const TIME_EPSILON: float = 0.000001

@export_group("Clock Settings")
@export_range(0, 23, 1) var initial_hour: int = 8
@export_range(0, 59, 1) var initial_minute: int = 0
## Количество игровых секунд за одну секунду работы игры.
@export_range(0, 60, 1, "or_greater") var game_seconds_per_real_second: float = 20.0
@export var start_paused: bool = false

var _game_seconds: float = 0.0
var _time_paused: bool = false
var _time_events: Dictionary[StringName, int] = {}
var _triggered_events: Array[StringName] = []
var _checking_time_events: bool = false


func _ready() -> void:
	var hour: int = clampi(initial_hour, 0, 23)
	var minute: int = clampi(initial_minute, 0, 59)
	_game_seconds = (hour * 60 + minute) * SECONDS_PER_MINUTE
	_time_paused = start_paused


func _process(delta: float) -> void:
	if _time_paused:
		return
	var previous_minutes: int = get_total_minutes()
	var speed: float = maxf(0.0, game_seconds_per_real_second)
	_game_seconds = minf(SECONDS_PER_DAY, _game_seconds + maxf(0.0, delta) * speed)
	if _game_seconds >= SECONDS_PER_DAY - TIME_EPSILON:
		_game_seconds = SECONDS_PER_DAY
		_time_paused = true
	var current_minutes: int = get_total_minutes()
	if current_minutes != previous_minutes:
		time_changed.emit(current_minutes)
		_check_time_events()


## Точное игровое время в секундах с начала суток.
func get_total_seconds() -> float:
	return _game_seconds


func get_total_minutes() -> int:
	# Компенсируем погрешность дробного delta на границе минуты.
	return floori((_game_seconds + TIME_EPSILON) / SECONDS_PER_MINUTE)


func get_time_text() -> String:
	var minutes: int = get_total_minutes()
	var hour: int = floori(minutes / 60.0)
	return "%02d:%02d" % [hour, minutes % 60]


func advance_minutes(minutes: int) -> void:
	if minutes < 0:
		push_warning("Перемотка времени назад не поддерживается.")
		return
	if minutes == 0 or _game_seconds >= SECONDS_PER_DAY:
		return
	var previous_minutes: int = get_total_minutes()
	# Явная перемотка доступна на паузе и не зависит от скорости часов.
	_game_seconds = minf(SECONDS_PER_DAY, _game_seconds + minutes * SECONDS_PER_MINUTE)
	if _game_seconds >= SECONDS_PER_DAY - TIME_EPSILON:
		_game_seconds = SECONDS_PER_DAY
		_time_paused = true
	var current_minutes: int = get_total_minutes()
	if current_minutes != previous_minutes:
		time_changed.emit(current_minutes)
		_check_time_events()


func register_time_event(event_id: StringName, scheduled_minutes: int) -> bool:
	if event_id == &"":
		push_warning("У события времени должен быть идентификатор.")
		return false
	if _time_events.has(event_id):
		push_warning("Событие времени уже зарегистрировано: %s" % event_id)
		return false
	if scheduled_minutes < 0 or scheduled_minutes > MINUTES_PER_DAY:
		push_warning("Время события должно быть в пределах от 0 до 1440 минут.")
		return false
	if scheduled_minutes <= get_total_minutes():
		push_warning("Событие времени можно зарегистрировать только на будущее.")
		return false
	_time_events[event_id] = scheduled_minutes
	return true


func set_time_paused(paused: bool) -> void:
	# В рамках одного дня часы не переходят за 24:00.
	_time_paused = paused or _game_seconds >= SECONDS_PER_DAY


func is_time_paused() -> bool:
	return _time_paused


func _check_time_events() -> void:
	# Обработчик события может перемотать часы: продолжаем проверку в этом же цикле.
	if _checking_time_events:
		return
	_checking_time_events = true
	while true:
		var next_event_id: StringName = &""
		var next_event_minutes: int = MINUTES_PER_DAY + 1
		var current_minutes: int = get_total_minutes()
		# Dictionary сохраняет порядок регистрации событий с одинаковым временем.
		for event_id: StringName in _time_events:
			var scheduled_minutes: int = _time_events[event_id]
			if event_id in _triggered_events or scheduled_minutes > current_minutes:
				continue
			if scheduled_minutes < next_event_minutes:
				next_event_id = event_id
				next_event_minutes = scheduled_minutes
		if next_event_id == &"":
			break
		# Отмечаем до сигнала, чтобы повторная перемотка не вызвала событие ещё раз.
		_triggered_events.append(next_event_id)
		time_event_reached.emit(next_event_id, next_event_minutes)
	_checking_time_events = false
