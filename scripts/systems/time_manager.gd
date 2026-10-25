extends Node
## Общие часы дня. Скорость влияет только на игровое время.

signal time_changed(total_minutes: int)

const SECONDS_PER_MINUTE: float = 60.0
const SECONDS_PER_DAY: float = 86400.0
const TIME_EPSILON: float = 0.000001

@export_group("Clock Settings")
@export_range(0, 23, 1) var initial_hour: int = 8
@export_range(0, 59, 1) var initial_minute: int = 0
## Количество игровых секунд за одну секунду работы игры.
@export_range(0, 60, 1, "or_greater") var game_seconds_per_real_second: float = 20.0
@export var start_paused: bool = false

var _game_seconds: float = 0.0
var _time_paused: bool = false


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


func set_time_paused(paused: bool) -> void:
	# В рамках одного дня часы не переходят за 24:00.
	_time_paused = paused or _game_seconds >= SECONDS_PER_DAY


func is_time_paused() -> bool:
	return _time_paused
