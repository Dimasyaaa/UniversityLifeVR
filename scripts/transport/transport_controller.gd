extends Node3D
## Подъезд, посадка и поездка используют общего игрока, часы и сохранение.

signal waiting_started
signal waiting_finished
signal bus_arrived
signal doors_opened
signal player_boarded
signal seat_selected(seat_name: StringName)
signal ride_started
signal ride_finished
signal destination_doors_opened
signal player_stood_up
signal player_alighted

const Player = preload("res://scripts/player/player.gd")
const PassengerSeat = preload("res://scripts/transport/passenger_seat.gd")

enum State { BEFORE_WAITING, APPROACHING, OPENING_DOORS, BOARDING_READY, IN_BUS, SEATED, CLOSING_DOORS, RIDING, RIDE_FINISHED, OPENING_DESTINATION_DOORS, ALIGHTING_READY, LEAVING_BUS, OUTSIDE }
enum Placement { NONE, SITTING, STANDING }

const BRAKING_PART: float = 0.35
const WHEEL_RADIUS: float = 0.5
const RIDE_RAMP_PART: float = 0.2
const SAVE_VERSION: int = 1
const SAVED_PHASES: Array[String] = ["before_waiting", "approaching", "opening_doors", "boarding_ready"]

@export_group("Bus Arrival")
## Реальные секунды без времени, проведённого в меню паузы.
@export_range(1.0, 30.0, 0.5) var approach_duration_seconds: float = 20.0
@export_range(0.2, 5.0, 0.1) var door_open_duration_seconds: float = 1.5
@export_range(60.0, 90.0, 1.0) var door_open_angle_degrees: float = 82.0

@export_group("Bus Ride")
## Задержка после завершения размещения в кресле; реальные секунды.
@export_range(0.0, 10.0, 0.5) var departure_delay_seconds: float = 2.0
## Длительность движения. Игровые минуты проходят только через TimeManager.
@export_range(5.0, 120.0, 0.5) var ride_duration_seconds: float = 55.0

@export_group("Bus Alighting")
@export_range(0.45, 0.8, 0.05) var stand_prompt_distance: float = 0.65

@onready var _waiting_area: Area3D = $BusStop/WaitingArea
@onready var _arrival_value: Label3D = $BusStop/Information/ArrivalValue
@onready var _bus: Node3D = $Bus
@onready var _approach_path: Path3D = $BusApproachPath
@onready var _stop_point: Marker3D = $BusStop/BusStopPoint
@onready var _ride_path: Path3D = $BusRidePath
@onready var _ride_end: Marker3D = $BusRideEnd
@onready var _front_door: Node3D = $Bus/Doors/FrontLeafPivot
@onready var _rear_door: Node3D = $Bus/Doors/RearLeafPivot
@onready var _wheels: Node3D = $Bus/Wheels
@onready var _cabin_area: Area3D = $Bus/CabinArea
@onready var _cabin_shape: CollisionShape3D = $Bus/CabinArea/CollisionShape3D
@onready var _walk_ramp: CollisionShape3D = $Bus/Body/EntranceRamp
@onready var _alighting_threshold: Marker3D = $DestinationStop/AlightingThreshold
@onready var _destination_exit: Area3D = $DestinationStop/TransitionTo_TestRoom
@onready var _stand_screen: XRToolsViewport2DIn3D = $Bus/Interior/StandPrompt

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
var _placement_success: bool = false
var _ramp_open: bool = false
var _departure_elapsed: float = 0.0
var _ride_elapsed: float = 0.0
var _ride_distance: float = 0.0
var _stand_action: Button
var _stand_prompt_requested: bool = false


func _ready() -> void:
	_stand_action = _stand_screen.get_scene_instance().get_node("Panel/Margin/Stand") as Button
	_stand_action.pressed.connect(_on_stand_button_pressed)
	for node: Node in $Bus/Interior/Seats.get_children():
		var seat: PassengerSeat = node as PassengerSeat
		if seat != null:
			_seats.append(seat)
			seat.seat_requested.connect(_on_seat_requested)
	_apply_restored_pose()
	_waiting_area.body_entered.connect(_on_waiting_area_body_entered)
	_cabin_area.body_exited.connect(_on_cabin_area_exited)


func _process(_delta: float) -> void:
	_refresh_stand_prompt()


func _physics_process(delta: float) -> void:
	if not _can_update_transport():
		return
	if _return_game_seconds >= 0.0:
		# Учитываем также время затемнения при обычном возвращении в локацию.
		_catch_up_return_time()
		_return_game_seconds = -1.0
	if _placement != Placement.NONE:
		_complete_placement.call_deferred()
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
			for body: Node3D in _cabin_area.get_overlapping_bodies():
				if body is Player:
					_record_boarding(body)
					break
		State.SEATED:
			_departure_elapsed = minf(departure_delay_seconds, _departure_elapsed + delta)
			if _departure_elapsed >= departure_delay_seconds:
				state = State.CLOSING_DOORS
		State.CLOSING_DOORS:
			_update_closing_doors(delta)
		State.RIDING:
			_update_ride(delta)
		State.RIDE_FINISHED:
			state = State.OPENING_DESTINATION_DOORS
		State.OPENING_DESTINATION_DOORS:
			_update_destination_doors(delta)
		State.LEAVING_BUS:
			_record_alighting()


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
	if state >= State.IN_BUS:
		saved_state = State.BOARDING_READY
	return {
		"version": SAVE_VERSION,
		"phase": SAVED_PHASES[saved_state],
		"approach_progress": _approach_elapsed / approach_duration_seconds,
		"door_progress": 1.0 if saved_state == State.BOARDING_READY else _door_elapsed / door_open_duration_seconds,
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
	_set_stand_prompt(false)
	_set_destination_exit(false)
	_update_walk_ramp()


func _on_cabin_area_exited(body: Node3D) -> void:
	if body == _passenger and state == State.IN_BUS and _placement == Placement.NONE:
		state = State.BOARDING_READY
		_passenger = null
		_set_seat_selection(false)


func _record_boarding(player: Player) -> void:
	if state != State.BOARDING_READY or _placement != Placement.NONE:
		return
	if not _can_update_transport() or not is_instance_valid(player) or not player.is_movement_enabled() or player.is_passenger_mode():
		return
	if not _is_player_inside_cabin(player):
		return
	# Игрок уже поднялся по пандусу: фиксируем вход, не меняя его позу.
	_passenger = player
	state = State.IN_BUS
	_set_seat_selection(true)
	player_boarded.emit()
	_save_transport_checkpoint.call_deferred()


func _is_player_inside_cabin(player: Player) -> bool:
	if not _cabin_area.overlaps_body(player):
		return false
	# Проверяем также текущую позицию, поскольку список Area3D обновляется по кадрам.
	var box: BoxShape3D = _cabin_shape.shape as BoxShape3D
	var capsule: CapsuleShape3D = player.body_collision.shape as CapsuleShape3D
	var bounds := AABB(-box.size * 0.5, box.size)
	bounds.position += Vector3(capsule.radius, 0, capsule.radius)
	bounds.size -= Vector3(capsule.radius * 2, 0, capsule.radius * 2)
	var floor_y: float = $Bus/Interior/AisleEntry.global_position.y
	return bounds.has_point(_cabin_shape.to_local(player.camera.global_position)) and absf(player.global_position.y - floor_y) < 0.10


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


func _on_stand_requested(seat: Node3D) -> void:
	if state != State.ALIGHTING_READY or _placement != Placement.NONE or not _can_update_transport():
		return
	if seat != _selected_seat or not is_instance_valid(_passenger) or not _passenger.is_passenger_mode():
		return
	if not _passenger.is_movement_enabled():
		return
	if _passenger.camera.global_position.distance_to(_stand_screen.global_position) > 1.5:
		return
	_begin_placement(Placement.STANDING)


func _on_stand_button_pressed() -> void:
	_on_stand_requested(_selected_seat)


func _record_alighting() -> void:
	if state != State.LEAVING_BUS or _placement != Placement.NONE or not _can_update_transport():
		return
	var player: Player = _passenger
	if not is_instance_valid(player) or not player.is_movement_enabled() or player.is_passenger_mode():
		return
	var head: Vector3 = _bus.to_local(player.camera.global_position)
	var threshold: Vector3 = _bus.to_local(_alighting_threshold.global_position)
	if head.x < threshold.x or not player.is_on_floor() or player.global_position.y > _alighting_threshold.global_position.y + 0.10:
		return
	# На тротуар игрок выходит обычной ходьбой; здесь только завершается сценарий.
	state = State.OUTSIDE
	_set_destination_exit(true)
	player_alighted.emit()
	_save_transport_checkpoint.call_deferred()


func _begin_placement(kind: Placement) -> void:
	_placement = kind
	_placement_success = false
	_set_seat_selection(false)
	_set_stand_prompt(false)
	# Переносим вне обработки физических сигналов, без затемнения и задержки.
	_complete_placement.call_deferred()


func _complete_placement() -> void:
	if _placement == Placement.NONE or not _can_update_transport():
		return
	_place_passenger()
	_finish_placement()


func _place_passenger() -> void:
	if not is_instance_valid(_passenger):
		return
	if _placement == Placement.SITTING and is_instance_valid(_selected_seat):
		if _passenger.enter_passenger_mode(_selected_seat.passenger_anchor, _selected_seat.passenger_eye_target):
			state = State.SEATED
			_placement_success = true
	elif _placement == Placement.STANDING:
		if is_instance_valid(_selected_seat) and _passenger.place_at_spawn(_selected_seat.standing_point):
			state = State.LEAVING_BUS
			_placement_success = true


func _finish_placement() -> void:
	var completed: Placement = _placement
	_placement = Placement.NONE
	_set_seat_selection(state == State.IN_BUS)
	_set_stand_prompt(state == State.ALIGHTING_READY)
	_update_walk_ramp()
	if not _placement_success:
		return
	if completed == Placement.SITTING:
		_departure_elapsed = 0.0
		seat_selected.emit(StringName(_selected_seat.name))
	elif completed == Placement.STANDING:
		player_stood_up.emit()
	_save_transport_checkpoint.call_deferred()


func _update_walk_ramp() -> void:
	var opened: bool = state in [State.BOARDING_READY, State.IN_BUS, State.ALIGHTING_READY, State.LEAVING_BUS, State.OUTSIDE]
	if opened != _ramp_open:
		_ramp_open = opened
		_walk_ramp.set_deferred("disabled", not opened)


func _set_seat_selection(enabled: bool) -> void:
	for seat: PassengerSeat in _seats:
		seat.set_selection_enabled(enabled)


func _set_stand_prompt(enabled: bool) -> void:
	_stand_prompt_requested = enabled and is_instance_valid(_selected_seat)
	if _stand_prompt_requested:
		# Одна панель следует системе координат кресла, не меняя XR-позу головы.
		_stand_screen.global_transform = _selected_seat.passenger_eye_target.global_transform
		_stand_screen.global_position -= _stand_screen.global_basis.z * stand_prompt_distance
	_refresh_stand_prompt()


func _refresh_stand_prompt() -> void:
	var available: bool = _stand_prompt_requested and _can_update_transport()
	if is_instance_valid(_passenger):
		available = available and _passenger.is_movement_enabled()
	if _stand_screen.visible != available:
		_stand_screen.visible = available
	if _stand_screen.enabled != available:
		_stand_screen.enabled = available
	_stand_action.disabled = not available


func _set_destination_exit(enabled: bool) -> void:
	_destination_exit.visible = enabled
	_destination_exit.set_deferred("monitoring", enabled)


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
		_update_walk_ramp()
		doors_opened.emit()
		_save_transport_checkpoint.call_deferred()


func _update_closing_doors(delta: float) -> void:
	_door_elapsed = maxf(0.0, _door_elapsed - delta)
	_apply_door_pose()
	if _door_elapsed > 0.0:
		return
	# Только эта смена состояния запускает поездку; повторный выбор кресла закрыт.
	state = State.RIDING
	_ride_elapsed = 0.0
	_ride_distance = 0.0
	_update_arrival_text()
	ride_started.emit()
	_save_transport_checkpoint.call_deferred()


func _update_destination_doors(delta: float) -> void:
	_door_elapsed = minf(door_open_duration_seconds, _door_elapsed + delta)
	_apply_door_pose()
	if _door_elapsed >= door_open_duration_seconds:
		state = State.ALIGHTING_READY
		_update_walk_ramp()
		_set_stand_prompt(true)
		destination_doors_opened.emit()
		_save_transport_checkpoint.call_deferred()


func _update_ride(delta: float) -> void:
	_ride_elapsed = minf(ride_duration_seconds, _ride_elapsed + delta)
	var progress: float = _ride_elapsed / ride_duration_seconds
	var distance: float = _ride_path.curve.get_baked_length() * _ride_progress(progress)
	var travelled: float = distance - _ride_distance
	_ride_distance = distance
	_bus.global_transform = _ride_path.global_transform * _ride_path.curve.sample_baked_with_rotation(distance, true, false)
	_wheel_angle = wrapf(_wheel_angle - travelled / WHEEL_RADIUS, -PI, PI)
	for wheel: Node3D in _wheels.get_children():
		wheel.rotation.x = _wheel_angle
	if progress >= 1.0:
		_bus.global_transform = _ride_end.global_transform
		state = State.RIDE_FINISHED
		ride_finished.emit()
		_save_transport_checkpoint.call_deferred()


func _ride_progress(progress: float) -> float:
	# Интеграл плавного разгона/торможения: скорость и ускорение без скачков.
	var ramp: float = minf(progress, 1.0 - progress) / RIDE_RAMP_PART
	var normalizer: float = 1.0 - RIDE_RAMP_PART
	if progress < RIDE_RAMP_PART or progress > 1.0 - RIDE_RAMP_PART:
		var ramp_distance: float = RIDE_RAMP_PART * (ramp * ramp * ramp - 0.5 * ramp * ramp * ramp * ramp) / normalizer
		return ramp_distance if progress < RIDE_RAMP_PART else 1.0 - ramp_distance
	return (progress - RIDE_RAMP_PART * 0.5) / normalizer


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
		State.CLOSING_DOORS, State.RIDING, State.RIDE_FINISHED, State.OPENING_DESTINATION_DOORS, State.ALIGHTING_READY, State.LEAVING_BUS, State.OUTSIDE:
			_arrival_value.text = "Уехал"
