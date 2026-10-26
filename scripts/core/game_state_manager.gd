extends Node

## Единый менеджер состояния игры (Модуль 7, ядро проекта).
## Показатели игрока, игровые часы и флаги квестов.
## API описан в ARCHITECTURE.md (§ GameStateManager).

signal player_stat_changed(stat_name: String, new_value: float)
signal time_changed(hours: int, minutes: int)
signal clock_toggled(running: bool)
signal flag_changed(flag_name: String, value: bool)
signal player_woke_up(total_minutes: int)

const SAVE_PATH := "user://game_state.cfg"

## Диапазоны показателей (min, max).
const STAT_LIMITS := {
	"energy": [0.0, 100.0],
	"satiety": [0.0, 100.0],
	"knowledge": [0.0, 100.0],
	"mood": [0.0, 100.0],
	"health": [0.0, 100.0],
	"money": [0.0, 99999.0],
}

## Стартовые значения нового дня.
const DEFAULT_STATS := {
	"energy": 35.0,
	"satiety": 25.0,
	"knowledge": 30.0,
	"mood": 60.0,
	"health": 100.0,
	"money": 150.0,
}

## Реальных секунд на одну игровую минуту (1.0 = очень быстро).
@export var seconds_per_game_minute: float = 2.0

var stats: Dictionary = {}
var flags: Dictionary = {}

## Игровое время в минутах от 00:00. Новый день начинается в 06:50 —
## так достижение «Ранняя пташка» (встал до 07:00) остаётся достижимым.
var game_minutes: int = 6 * 60 + 50

## Часы идут только после пробуждения (см. set_awake(true)).
var clock_running: bool = false

var _tick_accum: float = 0.0

func _ready() -> void:
	reset_day()

func _process(delta: float) -> void:
	if not clock_running:
		return
	_tick_accum += delta
	while _tick_accum >= seconds_per_game_minute:
		_tick_accum -= seconds_per_game_minute
		add_time(1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()

## Сброс к началу дня (06:50, показатели по умолчанию).
func reset_day() -> void:
	stats = DEFAULT_STATS.duplicate()
	flags = {}
	game_minutes = 6 * 60 + 50
	clock_running = false
	_tick_accum = 0.0
	for stat_name in stats:
		player_stat_changed.emit(stat_name, float(stats[stat_name]))
	time_changed.emit(get_hours(), get_minutes())

# --- Показатели -----------------------------------------------------------

func get_stat(stat_name: String) -> float:
	return float(stats.get(stat_name, 0.0))

func set_stat(stat_name: String, value: float) -> void:
	if not stats.has(stat_name):
		push_warning("GameStateManager: неизвестный показатель '%s'" % stat_name)
		return
	var limits: Array = STAT_LIMITS.get(stat_name, [0.0, 99999.0])
	var new_value: float = clampf(value, float(limits[0]), float(limits[1]))
	if is_equal_approx(new_value, float(stats[stat_name])):
		return
	stats[stat_name] = new_value
	player_stat_changed.emit(stat_name, new_value)
	save_game()

## Изменить показатель на дельту (например, +30 к Сытости).
func change_stat(stat_name: String, delta: float) -> void:
	set_stat(stat_name, get_stat(stat_name) + delta)

func has_stat(stat_name: String) -> bool:
	return stats.has(stat_name)

# --- Время ----------------------------------------------------------------

func get_hours() -> int:
	return game_minutes / 60

func get_minutes() -> int:
	return game_minutes % 60

func get_time_string() -> String:
	return "%02d:%02d" % [get_hours(), get_minutes()]

func add_time(minutes: int) -> void:
	game_minutes = clampi(game_minutes + minutes, 0, 24 * 60 - 1)
	time_changed.emit(get_hours(), get_minutes())

func start_clock() -> void:
	if clock_running:
		return
	clock_running = true
	clock_toggled.emit(true)

func stop_clock() -> void:
	if not clock_running:
		return
	clock_running = false
	clock_toggled.emit(false)

# --- Пробуждение и флаги --------------------------------------------------

func is_awake() -> bool:
	return bool(flags.get("awake", false))

func set_awake(value: bool) -> void:
	if value == is_awake():
		return
	flags["awake"] = value
	flag_changed.emit("awake", value)
	if value:
		start_clock()
		player_woke_up.emit(game_minutes)
	save_game()

func get_flag(flag_name: String) -> bool:
	return bool(flags.get(flag_name, false))

func set_flag(flag_name: String, value: bool) -> void:
	if get_flag(flag_name) == value:
		return
	flags[flag_name] = value
	flag_changed.emit(flag_name, value)
	save_game()

# --- Сохранение -----------------------------------------------------------

func save_game() -> void:
	var cf := ConfigFile.new()
	cf.set_value("day", "game_minutes", game_minutes)
	for stat_name in stats:
		cf.set_value("stats", stat_name, stats[stat_name])
	for flag_name in flags:
		cf.set_value("flags", flag_name, flags[flag_name])
	cf.save(SAVE_PATH)

func load_game() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return false
	game_minutes = int(cf.get_value("day", "game_minutes", game_minutes))
	for stat_name in cf.get_section_keys("stats"):
		if stats.has(stat_name):
			stats[stat_name] = cf.get_value("stats", stat_name, stats[stat_name])
			player_stat_changed.emit(stat_name, float(stats[stat_name]))
	flags = {}
	for flag_name in cf.get_section_keys("flags"):
		flags[flag_name] = cf.get_value("flags", flag_name, false)
	time_changed.emit(get_hours(), get_minutes())
	return true
