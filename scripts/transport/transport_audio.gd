extends Node
## Локальный звук транспорта. Источники заранее размещены в сценах.

const Transport = preload("res://scripts/transport/transport_controller.gd")

@export_group("Volume")
@export_range(-40.0, 0.0, 1.0) var outdoor_volume_db: float = -22.0
@export_range(-40.0, 0.0, 1.0) var engine_volume_db: float = -17.0
@export_range(-40.0, 0.0, 1.0) var road_volume_db: float = -18.0
@export_range(-40.0, 0.0, 1.0) var door_volume_db: float = -4.0
@export_range(-40.0, 0.0, 1.0) var brake_volume_db: float = -8.0

@export_group("Mix")
## Фон снаружи приглушается в салоне; часы и движение не изменяются.
@export_range(0.0, 1.0, 0.05) var outdoor_gain_in_cabin: float = 0.28
@export_range(0.1, 2.0, 0.05) var fade_seconds: float = 0.35
## Скорость в метрах в секунду, при которой достигается полный шум движения.
@export_range(1.0, 15.0, 0.5) var reference_speed: float = 6.0

@onready var _transport: Transport = get_parent() as Transport
@onready var _bus: Node3D = $"../Bus"
@onready var _cabin_shape: CollisionShape3D = $"../Bus/CabinArea/CollisionShape3D"
@onready var _outdoor: AudioStreamPlayer = $Outdoor
@onready var _engine: AudioStreamPlayer3D = $"../Bus/Audio/Engine"
@onready var _road: AudioStreamPlayer3D = $"../Bus/Audio/Road"
@onready var _door_open: AudioStreamPlayer3D = $"../Bus/Audio/DoorOpen"
@onready var _door_close: AudioStreamPlayer3D = $"../Bus/Audio/DoorClose"
@onready var _door_latch: AudioStreamPlayer3D = $"../Bus/Audio/DoorLatch"
@onready var _brakes: AudioStreamPlayer3D = $"../Bus/Audio/Brakes"

var _previous_state: int = -1
var _previous_bus_position: Vector3
var _has_bus_pose: bool = false
var _speed_amount: float = 0.0
var _engine_gain: float = 0.0
var _outdoor_gain: float = 0.0
var _road_gain: float = 0.0
var _suspended: bool = false


func _ready() -> void:
	# Подписки принадлежат экземпляру локации и удаляются вместе с ним.
	_transport.bus_arrived.connect(_on_bus_stopped)
	_transport.ride_finished.connect(_on_bus_stopped)
	_transport.ride_started.connect(_on_doors_closed)


func _physics_process(delta: float) -> void:
	var active: bool = _is_context_active()
	_set_suspended(not active)
	if not active:
		# После паузы/размещения не принимаем перенос автобуса за его скорость.
		_has_bus_pose = false
		return
	var state: int = _transport.state
	if state != _previous_state:
		_update_door_sound(state)
		_previous_state = state
	var speed: float = _speed_amount * reference_speed
	if _has_bus_pose:
		speed = _bus.global_position.distance_to(_previous_bus_position) / maxf(delta, 0.0001)
	_previous_bus_position = _bus.global_position
	_has_bus_pose = true
	var blend: float = 1.0 - exp(-delta / maxf(fade_seconds, 0.01))
	_speed_amount = lerpf(_speed_amount, clampf(speed / reference_speed, 0.0, 1.0), blend)
	var in_cabin: bool = _listener_is_in_cabin()
	_outdoor_gain = lerpf(_outdoor_gain, outdoor_gain_in_cabin if in_cabin else 1.0, blend)
	if not _outdoor.playing:
		_outdoor.play()
	_outdoor.volume_db = _gain_to_db(outdoor_volume_db, _outdoor_gain)
	var engine_on: bool = state != Transport.State.BEFORE_WAITING
	_engine_gain = lerpf(_engine_gain, (0.60 if in_cabin else 1.0) if engine_on else 0.0, blend)
	_road_gain = lerpf(_road_gain, _speed_amount if engine_on else 0.0, blend)
	_sync_bus_loop(_engine, engine_on)
	_sync_bus_loop(_road, engine_on)
	_engine.volume_db = _gain_to_db(engine_volume_db + _speed_amount, _engine_gain)
	# Небольшое плавное изменение оборотов сохраняет естественный тембр записи.
	_engine.pitch_scale = lerpf(_engine.pitch_scale, lerpf(1.0, 1.05, _speed_amount), 1.0 - exp(-delta / 1.25))
	_road.volume_db = _gain_to_db(road_volume_db, _road_gain)
	_road.pitch_scale = lerpf(0.85, 1.08, _speed_amount)
	_door_open.volume_db = door_volume_db
	_door_close.volume_db = door_volume_db
	_door_latch.volume_db = door_volume_db
	_brakes.volume_db = brake_volume_db


func _listener_is_in_cabin() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not _bus.visible:
		return false
	var shape: BoxShape3D = _cabin_shape.shape as BoxShape3D
	return AABB(-shape.size * 0.5, shape.size).has_point(_cabin_shape.to_local(camera.global_position))


func _update_door_sound(state: int) -> void:
	_door_open.stop()
	_door_close.stop()
	var progress: float = _transport.get_door_open_progress()
	match state:
		Transport.State.OPENING_DOORS, Transport.State.OPENING_DESTINATION_DOORS:
			_play_door(_door_open, progress)
		Transport.State.CLOSING_DOORS:
			_play_door(_door_close, 1.0 - progress)


func _play_door(player: AudioStreamPlayer3D, progress: float) -> void:
	if progress >= 1.0:
		return
	var duration: float = player.stream.get_length()
	# Звук совпадает с реальной анимацией, в том числе при продолжении сохранения.
	player.pitch_scale = duration / _transport.door_open_duration_seconds
	player.volume_db = door_volume_db
	player.play(clampf(progress, 0.0, 1.0) * duration)


func _on_bus_stopped() -> void:
	# Сохранение восстанавливает позу без этих сигналов: повторного торможения нет.
	# Сигнал может прийти раньше нашего physics-кадра сразу после закрытия меню.
	if not _is_context_active():
		return
	_brakes.volume_db = brake_volume_db
	_brakes.play()


func _on_doors_closed() -> void:
	# ride_started приходит после _apply_door_pose() с полностью закрытыми створками.
	# Щелчок не встроен заранее в запись движения и не может опередить эту позу.
	if not _is_context_active():
		return
	_door_latch.volume_db = door_volume_db
	_door_latch.play()


func _is_context_active() -> bool:
	return (
		SceneManager.get_current_location() == _transport
		and not SceneManager.is_transitioning()
		and not SaveManager.is_loading()
		and not TimeManager.is_time_paused()
	)


func _sync_bus_loop(player: AudioStreamPlayer3D, enabled: bool) -> void:
	if enabled and not player.playing:
		player.play()
	elif not enabled and player.playing:
		player.stop()


func _set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	_outdoor.stream_paused = suspended
	for player: AudioStreamPlayer3D in [_engine, _road, _door_open, _door_close, _door_latch, _brakes]:
		player.stream_paused = suspended


func _gain_to_db(volume_db: float, gain: float) -> float:
	return maxf(-80.0, volume_db + linear_to_db(maxf(gain, 0.0001)))
