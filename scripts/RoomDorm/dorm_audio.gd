extends Node3D
## Только звуки комнаты: игровые данные и управление остаются у общих систем.

const Player = preload("res://scripts/player/player.gd")
const STEP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/RoomDorm/footstep_1.wav"),
	preload("res://assets/audio/RoomDorm/footstep_2.wav"),
	preload("res://assets/audio/RoomDorm/footstep_3.wav"),
]

@export_range(0.3, 1.5, 0.05) var step_distance: float = 0.85

@onready var _room: Node3D = get_parent()
@onready var _fridge = $"../Room/Fridge"
@onready var _microwave = $"../Room/Microwave"
@onready var _pizza = $"../BreakfastPizza"
@onready var _wakeup = $"../Wakeup"
@onready var _bed = $"../Room/Bed"
@onready var _window = $"../WindowTime"
@onready var _city: AudioStreamPlayer3D = $City
@onready var _birds: AudioStreamPlayer3D = $Birds
@onready var _hum: AudioStreamPlayer3D = $MicrowaveHum
@onready var _steps: AudioStreamPlayer3D = $Footsteps

var _player: Player
var _menu: Node3D
var _players: Array[AudioStreamPlayer3D] = []
var _blocked: bool = true
var _previous_micro_open: bool = true
var _previous_micro_moving: bool = false
var _food_was_held: bool = false
var _pending_place: bool = false
var _last_step_position: Vector3
var _distance_walked: float = 0.0
var _step_index: int = 0
var _ambience_tween: Tween


func _ready() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer3D:
			_players.append(child)
			child.stream_paused = true
	_fridge.door_motion_started.connect(_on_fridge_started)
	_fridge.door_state_changed.connect(_on_fridge_finished)
	_microwave.state_changed.connect(_on_microwave_changed)
	_microwave.get_node("StartButton").pressed.connect(_on_microwave_pressed)
	_pizza.picked_up.connect(_on_food_picked_up)
	_pizza.released.connect(_on_food_released)
	_pizza.eaten.connect(_on_food_eaten)
	_pizza.body_entered.connect(_on_food_contact)
	$"../ClothesRack".outfit_changed.connect(_on_outfit_changed)
	_wakeup.get_node("Screen").get_scene_instance().get_node("Panel/Margin/Content/Stand").pressed.connect(_on_stand_pressed)
	_bed.rested.connect(_on_rest_confirmed)
	_bed.cancelled.connect(_on_rest_cancelled)
	_window.waited.connect(_on_wait_confirmed)
	_window.cancelled.connect(_on_wait_cancelled)
	TimeManager.time_changed.connect(_on_time_changed)
	SaveManager.game_loaded.connect(_on_state_restored)
	SaveManager.new_game_started.connect(_on_state_restored)
	SceneManager.transition_started.connect(_on_transition_started)
	_hum.global_position = _microwave.get_node("Chamber/CollisionShape3D").global_position
	_snapshot()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null and camera.get_parent().get_parent() is Player:
			_player = camera.get_parent().get_parent()
			_menu = _player.get_parent().get_node_or_null("MainMenuPanel") as Node3D
			_last_step_position = _player.global_position
	var blocked: bool = _is_blocked()
	if blocked != _blocked:
		_set_blocked(blocked)
	if blocked:
		return
	_update_footsteps()


func _is_blocked() -> bool:
	return not is_instance_valid(_player) or SaveManager.is_loading() or SceneManager.is_transitioning() or SceneManager.get_current_location() != _room or get_tree().paused or (_menu != null and _menu.visible)


func _set_blocked(blocked: bool) -> void:
	_blocked = blocked
	for sound: AudioStreamPlayer3D in _players:
		sound.stream_paused = blocked
	_distance_walked = 0.0
	_pending_place = false
	_food_was_held = false
	if blocked:
		_stop_shots()
	else:
		_snapshot()
		_food_was_held = is_instance_valid(_pizza.hold_target) or _pizza.has_meta("grabbed_by")
		_last_step_position = _player.global_position
		_sync_ambience(true)
		_sync_hum()


func _snapshot() -> void:
	_previous_micro_open = _microwave.is_open
	_previous_micro_moving = _microwave.is_moving


func _play_at(sound: AudioStreamPlayer3D, point: Vector3) -> void:
	if _is_blocked():
		return
	sound.global_position = point
	sound.play()


func _on_fridge_started(opened: bool) -> void:
	if opened:
		_play_at($FridgeOpen, _fridge.global_position + Vector3(0, 1.0, 0))


func _on_fridge_finished(opened: bool) -> void:
	if not opened:
		_play_at($FridgeClose, _fridge.global_position + Vector3(0, 1.0, 0))


func _on_microwave_pressed() -> void:
	_play_at($MicrowaveButton, _microwave.get_node("StartButton").global_position)


func _on_microwave_changed() -> void:
	if not _is_blocked():
		if _microwave.is_moving and not _previous_micro_moving and _microwave.is_open:
			_play_at($MicrowaveOpen, _microwave.global_position)
		elif _previous_micro_moving and not _microwave.is_moving and not _microwave.is_open:
			_play_at($MicrowaveClose, _microwave.global_position)
	_snapshot()
	_sync_hum()


func _sync_hum() -> void:
	if _is_blocked():
		return
	if _microwave.is_heating:
		if not _hum.playing:
			_hum.play()
	else:
		_hum.stop()


func _on_food_picked_up(_first_time: bool) -> void:
	_food_was_held = not _is_blocked()
	_pending_place = false
	_play_at($PlatePickup, _pizza.global_position)


func _on_food_released() -> void:
	_pending_place = _food_was_held and not _is_blocked()
	_food_was_held = false
	# Если тарелка уже касается полки, нового body_entered после отпускания не будет.
	if _pending_place and not _pizza.get_colliding_bodies().is_empty():
		_on_food_contact(null)


func _on_food_contact(_body: Node) -> void:
	if not _pending_place or is_instance_valid(_pizza.hold_target) or _pizza.has_meta("grabbed_by"):
		return
	_pending_place = false
	_play_at($PlatePlace, _pizza.global_position)


func _on_food_eaten() -> void:
	_play_at($Bite, _pizza.global_position)


func _on_outfit_changed(_item_id: StringName) -> void:
	_play_at($Fabric, $"../ClothesRack".global_position + Vector3(0, 1.5, 0))


func _on_stand_pressed() -> void:
	if _wakeup.is_rising():
		_play_at($BedRustle, _wakeup.get_node("LyingHead").global_position)


func _on_rest_confirmed() -> void:
	_play_at($UiTap, $"../BedRestScreen".global_position)


func _on_rest_cancelled() -> void:
	_play_at($UiTap, $"../BedRestScreen".global_position)


func _on_wait_confirmed() -> void:
	_play_at($UiTap, _window.get_node("Screen").global_position)


func _on_wait_cancelled() -> void:
	_play_at($UiTap, _window.get_node("Screen").global_position)


func _update_footsteps() -> void:
	var position_now: Vector3 = _player.global_position
	var moved: Vector3 = position_now - _last_step_position
	_last_step_position = position_now
	moved.y = 0.0
	if _wakeup.is_lying() or _wakeup.is_rising() or not _player.is_physics_processing() or not _player.is_movement_enabled() or not _player.is_on_floor() or moved.length() > 0.3:
		_distance_walked = 0.0
		return
	_distance_walked += moved.length()
	if _distance_walked >= step_distance:
		_distance_walked = fmod(_distance_walked, step_distance)
		_steps.stream = STEP_SOUNDS[_step_index % STEP_SOUNDS.size()]
		_steps.pitch_scale = 0.97 + (_step_index % 3) * 0.03
		_step_index += 1
		_play_at(_steps, position_now + Vector3(0, 0.1, 0))


func _on_time_changed(_minutes: int) -> void:
	if not _is_blocked():
		_sync_ambience(false)


func _sync_ambience(instant: bool) -> void:
	if _ambience_tween != null:
		_ambience_tween.kill()
	var minute: float = TimeManager.get_total_seconds() / 60.0
	var day: float = minf(clampf((minute-300.0)/180.0,0.0,1.0),clampf((1320.0-minute)/240.0,0.0,1.0))
	var birds: float = minf(clampf((minute-300.0)/180.0,0.0,1.0),clampf((1080.0-minute)/360.0,0.0,1.0))
	var city_db: float = lerpf(-34.0,-28.0,day)
	var birds_db: float = lerpf(-60.0,-34.0,birds)
	if not _city.playing:
		_city.volume_db = city_db
		_city.play()
	if birds > 0.01 and not _birds.playing:
		_birds.volume_db = birds_db if instant else -60.0
		_birds.play()
	if instant:
		_city.volume_db = city_db
		_birds.volume_db = birds_db
		if birds <= 0.01:
			_birds.stop()
	else:
		_ambience_tween = create_tween().set_parallel(true)
		_ambience_tween.tween_property(_city,"volume_db",city_db,0.45)
		_ambience_tween.tween_property(_birds,"volume_db",birds_db,0.45)
		if birds <= 0.01:
			_ambience_tween.chain().tween_callback(_birds.stop)


func _stop_shots() -> void:
	for sound: AudioStreamPlayer3D in _players:
		if sound not in [_city, _birds, _hum]:
			sound.stop()


func _on_state_restored() -> void:
	_stop_shots()
	_snapshot()
	_set_blocked(_is_blocked())


func _on_transition_started(_location_id: StringName) -> void:
	_set_blocked(true)


func _exit_tree() -> void:
	if _ambience_tween != null:
		_ambience_tween.kill()
	for sound: AudioStreamPlayer3D in _players:
		sound.stop()
