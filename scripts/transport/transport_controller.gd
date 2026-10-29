extends Node3D
## Локальный транспорт: подъезд и отсчёт до прибытия запускаются вместе.

signal waiting_started
signal waiting_finished
signal bus_arrived
signal doors_opened
signal player_boarded
signal seat_selected(seat_name: StringName)

const Player = preload("res://scripts/player/player.gd")
const PassengerSeat = preload("res://scripts/transport/passenger_seat.gd")

enum State { BEFORE_WAITING, APPROACHING, OPENING_DOORS, BOARDING_READY, IN_BUS, SEATED }
enum Placement { NONE, ENTERING, SITTING }
enum FadePhase { OUT, BLACK, IN }

const BRAKING_PART: float = 0.35
const WHEEL_RADIUS: float = 0.5
const SAVE_VERSION: int = 1
const SAVED_PHASES: Array[String] = ["before_waiting", "approaching", "opening_doors", "boarding_ready"]

@export_group("Bus Arrival")
## Реальные секунды без времени, проведённого в меню паузы.
@export_range(1.0, 30.0, 0.5) var approach_duration_seconds: float = 20.0
@export_range(0.2, 5.0, 0.1) var door_open_duration_seconds: float = 1.5
@export_range(60.0, 90.0, 1.0) var door_open_angle_degrees: float = 82.0

@export_group("Bus Boarding")
@export_range(0.1, 0.5, 0.05) var boarding_fade_seconds: float = 0.15

@onready var _waiting_area: Area3D = $BusStop/WaitingArea
@onready var _arrival_value: Label3D = $BusStop/Information/ArrivalValue
@onready var _bus: Node3D = $Bus
@onready var _approach_path: Path3D = $BusApproachPath
@onready var _stop_point: Marker3D = $BusStop/BusStopPoint
@onready var _front_door: Node3D = $Bus/Doors/FrontLeafPivot
@onready var _rear_door: Node3D = $Bus/Doors/RearLeafPivot
@onready var _wheels: Node3D = $Bus/Wheels
@onready var _boarding_area: Area3D = $Bus/BoardingArea
@onready var _boarding_shape: CollisionShape3D = $Bus/BoardingArea/CollisionShape3D
@onready var _cabin_area: Area3D = $Bus/CabinArea

var state: State = State.BEFORE_WAITING
var _approach_elapsed: float = 0.0
var _door_elapsed: float = 0.0
var _path_distance: float = 0.0
var _wheel_angle: float = 0.0
var _return_game_seconds: float = -1.0
var _return_clock_speed: float = 0.0
var _seats: Array[PassengerSeat] = []
var _passenger: Player
var _selected_seat: PassengerSeat
var _placement: Placement = Placement.NONE
var _fade_phase: FadePhase = FadePhase.OUT
var _fade_elapsed: float = 0.0
var _black_frames: int = 0
var _placement_success: bool = false
var _boarding_armed: bool = true


func _ready() -> void:
	for node: Node in $Bus/Interior/Seats.get_children():
		var seat: PassengerSeat = node as PassengerSeat
		if seat != null:
			_seats.append(seat)
			seat.seat_requested.connect(_on_seat_requested)
	_apply_restored_pose()
	_waiting_area.body_entered.connect(_on_waiting_area_body_entered)
	_boarding_area.body_entered.connect(_on_boarding_area_entered)
	_boarding_area.body_exited.connect(_on_boarding_area_exited)
	_cabin_area.body_exited.connect(_on_cabin_area_exited)


func _process(_delta: float) -> void:
	if _placement != Placement.NONE and _fade_phase == FadePhase.BLACK and _can_update_transport():
		_black_frames += 1


func _exit_tree() -> void:
	# Убираем только своё затемнение, не затрагивая запрос SceneManager.
	XRToolsFade.set_fade(self, Color(0, 0, 0, 0))


func _physics_process(delta: float) -> void:
	if not _can_update_transport():
		return
	if _return_game_seconds >= 0.0:
		# Учитываем также время затемнения при обычном возвращении в локацию.
		_catch_up_return_time()
		_return_game_seconds = -1.0
	if _placement != Placement.NONE:
		_update_placement(delta)
		return
	match state:
		State.BEFORE_WAITING:
			# Игрок мог оказаться в зоне во время затемнения или паузы меню.
			for body: Node3D in _waiting_area.get_overlapping_bodies():
				if body is Player:
					_start_approach()
					break
		State.APPROACHING:
			_update_approach(delta)
		State.OPENING_DOORS:
			_update_doors(delta)
		State.BOARDING_READY:
			if _boarding_armed:
				for body: Node3D in _boarding_area.get_overlapping_bodies():
					if body is Player:
						_request_boarding(body)
						break


func get_remaining_wait_seconds() -> float:
	if state != State.APPROACHING:
		return 0.0
	# Табло получает остаток той же анимации в единицах общих игровых часов.
	# Отдельного отсчёта и дополнительного начисления времени нет.
	var remaining_real_seconds: float = maxf(0.0, approach_duration_seconds - _approach_elapsed)
	return remaining_real_seconds * maxf(0.0, TimeManager.game_seconds_per_real_second)


func is_boarding_available() -> bool:
	return state == State.BOARDING_READY


## SaveManager хранит этот словарь в общем разделе состояний локаций.
func get_save_data() -> Dictionary:
	if _return_game_seconds >= 0.0:
		_catch_up_return_time()
	# Сохраняется готовый автобус; позиция игрока по договорённости — у общежития.
	var saved_state: State = state
	if state == State.IN_BUS or state == State.SEATED:
		saved_state = State.BOARDING_READY
	return {
		"version": SAVE_VERSION,
		"phase": SAVED_PHASES[saved_state],
		"approach_progress": _approach_elapsed / approach_duration_seconds,
		"door_progress": _door_elapsed / door_open_duration_seconds,
		"game_seconds": TimeManager.get_total_seconds(),
		"clock_speed": maxf(0.0, TimeManager.game_seconds_per_real_second),
	}


func restore_save_data(data: Dictionary) -> void:
	if not _is_transport_save_valid(data):
		push_warning("Транспорт: состояние сохранения несовместимо или повреждено; восстановлено начало ожидания.")
		state = State.BEFORE_WAITING
		_approach_elapsed = 0.0
		_door_elapsed = 0.0
		_return_game_seconds = -1.0
		_apply_restored_pose()
		return
	match data["phase"]:
		"before_waiting":
			state = State.BEFORE_WAITING
		"approaching":
			state = State.APPROACHING
		"opening_doors":
			state = State.OPENING_DOORS
		"boarding_ready":
			state = State.BOARDING_READY
	_approach_elapsed = float(data["approach_progress"]) * approach_duration_seconds
	_door_elapsed = float(data["door_progress"]) * door_open_duration_seconds
	_return_game_seconds = float(data["game_seconds"])
	_return_clock_speed = float(data["clock_speed"])
	# При загрузке общие часы уже восстановлены: прошедшее время равно нулю.
	# При возвращении сюда из другой локации часы позволяют догнать подъезд.
	_catch_up_return_time()


func _is_transport_save_valid(data: Dictionary) -> bool:
	if not data.get("version") is int or data.get("version") != SAVE_VERSION or not data.get("phase") is String:
		return false
	if data["phase"] not in SAVED_PHASES:
		return false
	for field: String in ["approach_progress", "door_progress", "game_seconds", "clock_speed"]:
		var value: Variant = data.get(field)
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	if not (
		float(data["approach_progress"]) >= 0.0 and float(data["approach_progress"]) <= 1.0
		and float(data["door_progress"]) >= 0.0 and float(data["door_progress"]) <= 1.0
		and float(data["game_seconds"]) >= 0.0 and float(data["game_seconds"]) <= TimeManager.SECONDS_PER_DAY
		and float(data["clock_speed"]) >= 0.0
	):
		return false
	# Фаза не должна разрешать посадку при закрытых дверях или незаконченном пути.
	match data["phase"]:
		"before_waiting":
			return float(data["approach_progress"]) == 0.0 and float(data["door_progress"]) == 0.0
		"approaching":
			return float(data["door_progress"]) == 0.0
		"opening_doors":
			return float(data["approach_progress"]) == 1.0
		"boarding_ready":
			return float(data["approach_progress"]) == 1.0 and float(data["door_progress"]) == 1.0
	return false


func _catch_up_return_time() -> void:
	var now: float = TimeManager.get_total_seconds()
	if _return_clock_speed > 0.0:
		# Скорость на момент выхода переводит прошедшие игровые секунды в прогресс.
		var elapsed: float = maxf(0.0, now - _return_game_seconds) / _return_clock_speed
		_advance_restored_progress(elapsed)
	_return_game_seconds = now
	_apply_restored_pose()


func _advance_restored_progress(elapsed: float) -> void:
	if state == State.APPROACHING:
		var step: float = minf(elapsed, approach_duration_seconds - _approach_elapsed)
		_approach_elapsed += step
		elapsed -= step
		if _approach_elapsed >= approach_duration_seconds:
			state = State.OPENING_DOORS
			_door_elapsed = 0.0
	if state == State.OPENING_DOORS:
		_door_elapsed = minf(door_open_duration_seconds, _door_elapsed + elapsed)
		if _door_elapsed >= door_open_duration_seconds:
			state = State.BOARDING_READY


func _apply_restored_pose() -> void:
	# Восстанавливаем вид и физику напрямую, без повторных игровых сигналов.
	_path_distance = _approach_path.curve.get_baked_length() * _braking_progress(_approach_elapsed / approach_duration_seconds)
	if state == State.BEFORE_WAITING:
		_bus.hide()
		_bus.process_mode = Node.PROCESS_MODE_DISABLED
		_apply_bus_pose(0.0)
	else:
		if state == State.APPROACHING:
			_apply_bus_pose(_path_distance)
		else:
			_bus.global_transform = _stop_point.global_transform
		_bus.process_mode = Node.PROCESS_MODE_INHERIT
		_bus.show()
	_wheel_angle = wrapf(-_path_distance / WHEEL_RADIUS, -PI, PI)
	for wheel: Node3D in _wheels.get_children():
		wheel.rotation.x = _wheel_angle
	_apply_door_pose()
	_update_arrival_text()
	_set_seat_selection(false)


func _on_boarding_area_entered(body: Node3D) -> void:
	if body is Player:
		_request_boarding.call_deferred(body)


func _on_boarding_area_exited(body: Node3D) -> void:
	if body is Player:
		_boarding_armed = true


func _on_cabin_area_exited(body: Node3D) -> void:
	if body == _passenger and state == State.IN_BUS and _placement == Placement.NONE:
		state = State.BOARDING_READY
		_boarding_armed = false
		_passenger = null
		_set_seat_selection(false)


func _request_boarding(player: Player) -> void:
	if state != State.BOARDING_READY or _placement != Placement.NONE or not _boarding_armed:
		return
	if not _can_update_transport() or not is_instance_valid(player) or not player.is_movement_enabled() or player.is_passenger_mode():
		return
	if not _is_player_at_door(player):
		return
	_passenger = player
	_boarding_armed = false
	_begin_placement(Placement.ENTERING)


func _is_player_at_door(player: Player) -> bool:
	if not _boarding_area.overlaps_body(player):
		return false
	# Список Area3D обновляется на физическом кадре и может отставать после загрузки.
	# Дополнительно сверяем текущую позицию головы с простым объёмом входа.
	var box: BoxShape3D = _boarding_shape.shape as BoxShape3D
	var capsule: CapsuleShape3D = player.body_collision.shape as CapsuleShape3D
	var bounds := AABB(-box.size * 0.5, box.size).grow(capsule.radius)
	return bounds.has_point(_boarding_shape.to_local(player.camera.global_position))


func _on_seat_requested(seat: Node3D) -> void:
	if state != State.IN_BUS or _placement != Placement.NONE or not _can_update_transport():
		return
	if seat not in _seats or not is_instance_valid(_passenger) or not _cabin_area.overlaps_body(_passenger):
		return
	var selected: PassengerSeat = seat as PassengerSeat
	if _passenger.camera.global_position.distance_to(selected.passenger_eye_target.global_position) > 2.0:
		return
	_selected_seat = selected
	_begin_placement(Placement.SITTING)


func _begin_placement(kind: Placement) -> void:
	_placement = kind
	_fade_phase = FadePhase.OUT
	_fade_elapsed = 0.0
	_black_frames = 0
	_placement_success = false
	_set_seat_selection(false)


func _update_placement(delta: float) -> void:
	match _fade_phase:
		FadePhase.OUT:
			_fade_elapsed = minf(boarding_fade_seconds, _fade_elapsed + delta)
			XRToolsFade.set_fade(self, Color(0, 0, 0, _fade_elapsed / boarding_fade_seconds))
			if _fade_elapsed >= boarding_fade_seconds:
				_fade_phase = FadePhase.BLACK
				_black_frames = 0
		FadePhase.BLACK:
			if _black_frames >= 2:
				_place_passenger_under_black()
				_fade_phase = FadePhase.IN
				_fade_elapsed = 0.0
		FadePhase.IN:
			_fade_elapsed = minf(boarding_fade_seconds, _fade_elapsed + delta)
			XRToolsFade.set_fade(self, Color(0, 0, 0, 1.0 - _fade_elapsed / boarding_fade_seconds))
			if _fade_elapsed >= boarding_fade_seconds:
				_finish_placement()


func _place_passenger_under_black() -> void:
	if not is_instance_valid(_passenger):
		return
	if _placement == Placement.ENTERING:
		if _passenger.place_at_spawn($Bus/Interior/AisleEntry):
			state = State.IN_BUS
			_placement_success = true
	elif _placement == Placement.SITTING and is_instance_valid(_selected_seat):
		if _passenger.enter_passenger_mode(_selected_seat.passenger_anchor, _selected_seat.passenger_eye_target):
			state = State.SEATED
			_placement_success = true


func _finish_placement() -> void:
	var completed: Placement = _placement
	_placement = Placement.NONE
	XRToolsFade.set_fade(self, Color(0, 0, 0, 0))
	_set_seat_selection(state == State.IN_BUS)
	if not _placement_success:
		return
	if completed == Placement.ENTERING:
		player_boarded.emit()
	elif completed == Placement.SITTING:
		seat_selected.emit(StringName(_selected_seat.name))
	_save_transport_checkpoint.call_deferred()


func _set_seat_selection(enabled: bool) -> void:
	for seat: PassengerSeat in _seats:
		seat.set_selection_enabled(enabled)


func _can_update_transport() -> bool:
	return (
		SceneManager.get_current_location() == self
		and not SceneManager.is_transitioning()
		and not SaveManager.is_loading()
		and not TimeManager.is_time_paused()
	)


func _on_waiting_area_body_entered(body: Node3D) -> void:
	if body is Player and _can_update_transport():
		# Включаем физические тела автобуса после обработки сигнала Area3D.
		_start_approach.call_deferred()


func _start_approach() -> void:
	if state != State.BEFORE_WAITING or not _can_update_transport():
		return
	# Состояние меняется до сигнала; второй запуск невозможен.
	state = State.APPROACHING
	_approach_elapsed = 0.0
	_path_distance = 0.0
	_apply_bus_pose(0.0)
	_bus.process_mode = Node.PROCESS_MODE_INHERIT
	_bus.show()
	_update_arrival_text()
	waiting_started.emit()
	_save_transport_checkpoint.call_deferred()


func _update_approach(delta: float) -> void:
	_approach_elapsed = minf(approach_duration_seconds, _approach_elapsed + delta)
	var progress: float = _approach_elapsed / approach_duration_seconds
	var distance: float = _approach_path.curve.get_baked_length() * _braking_progress(progress)
	var travelled: float = distance - _path_distance
	_path_distance = distance
	_apply_bus_pose(distance)
	_wheel_angle = wrapf(_wheel_angle - travelled / WHEEL_RADIUS, -PI, PI)
	for wheel: Node3D in _wheels.get_children():
		wheel.rotation.x = _wheel_angle
	_update_arrival_text()
	if progress >= 1.0:
		# Точная финальная поза совпадает с маркером посадки, без накопления ошибки.
		_bus.global_transform = _stop_point.global_transform
		state = State.OPENING_DOORS
		_door_elapsed = 0.0
		_update_arrival_text()
		waiting_finished.emit()
		bus_arrived.emit()
		_save_transport_checkpoint.call_deferred()


func _apply_bus_pose(distance: float) -> void:
	# Curve3D ориентирует модель по -Z, как и передняя часть нашего автобуса.
	_bus.global_transform = _approach_path.global_transform * _approach_path.curve.sample_baked_with_rotation(distance, true)


func _braking_progress(progress: float) -> float:
	# Равномерное движение и плавное снижение скорости до нуля в конце пути.
	var braking_start: float = 1.0 - BRAKING_PART
	var normalizer: float = 1.0 - BRAKING_PART * 0.5
	if progress <= braking_start:
		return progress / normalizer
	var braking_time: float = progress - braking_start
	return (braking_start + braking_time - braking_time * braking_time / (2.0 * BRAKING_PART)) / normalizer


func _update_doors(delta: float) -> void:
	_door_elapsed = minf(door_open_duration_seconds, _door_elapsed + delta)
	_apply_door_pose()
	if _door_elapsed >= door_open_duration_seconds:
		state = State.BOARDING_READY
		doors_opened.emit()
		_save_transport_checkpoint.call_deferred()


func _save_transport_checkpoint() -> void:
	# Переход и загрузка сами управляют общим сохранением; не вмешиваемся в них.
	if SceneManager.get_current_location() != self or SceneManager.is_transitioning() or SaveManager.is_loading():
		return
	SaveManager.save_game()


func _apply_door_pose() -> void:
	var progress: float = _door_elapsed / door_open_duration_seconds
	var angle: float = deg_to_rad(door_open_angle_degrees) * smoothstep(0.0, 1.0, progress)
	_front_door.rotation.y = -angle
	_rear_door.rotation.y = angle


func _update_arrival_text() -> void:
	match state:
		State.BEFORE_WAITING:
			_arrival_value.text = "—"
		State.APPROACHING:
			if TimeManager.game_seconds_per_real_second <= 0.0:
				_arrival_value.text = "Подъезжает"
				return
			# Округление вверх не показывает 00:00 до завершения ожидания.
			var seconds: int = ceili(get_remaining_wait_seconds())
			_arrival_value.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
		State.OPENING_DOORS, State.BOARDING_READY, State.IN_BUS, State.SEATED:
			_arrival_value.text = "Прибыл"
