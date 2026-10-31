extends Node3D
## Только локальный считыватель: контакт общего телефона, индикация и звук.
## Деньги, доступ к креслам и сохранение платежа принадлежат контроллеру транспорта.

const Player = preload("res://scripts/player/player.gd")
const Transport = preload("res://scripts/transport/transport_controller.gd")

@export var transport_path: NodePath = NodePath("../../..")
@export_range(0.08, 0.25, 0.01) var tap_distance: float = 0.16
@export_range(0.18, 0.4, 0.01) var release_distance: float = 0.23

@onready var _transport: Transport = get_node(transport_path) as Transport
@onready var _tap_point: Marker3D = $TapPoint
@onready var _price: Label3D = $Price
@onready var _status: Label3D = $Status
@onready var _indicator: StandardMaterial3D = $Indicator.material_override as StandardMaterial3D
@onready var _success: AudioStreamPlayer3D = $PaymentSuccess
@onready var _failure: AudioStreamPlayer3D = $PaymentFailure

var _touching: bool = false
var _denied: bool = false
var _display_state: int = -1
var _suspended: bool = false


func _ready() -> void:
	_transport.fare_paid.connect(_on_fare_paid)
	_price.text = "%d ₽" % _transport.get_fare_price()
	_refresh_display()


func _physics_process(_delta: float) -> void:
	var active: bool = (
		SceneManager.get_current_location() == _transport
		and not SceneManager.is_transitioning()
		and not SaveManager.is_loading()
		and not TimeManager.is_time_paused()
	)
	var suspended: bool = not active
	if _suspended != suspended:
		_suspended = suspended
		_success.stream_paused = _suspended
		_failure.stream_paused = _suspended
	if not active:
		_touching = false
		return
	var player: Player = _get_player()
	if not _transport.can_pay_fare(player):
		_touching = false
		_denied = false
		_refresh_display()
		return
	var distance: float = _phone_distance(player)
	if distance > maxf(release_distance, tap_distance + 0.03):
		_touching = false
		_denied = false
	elif distance <= tap_distance and not _touching:
		# Новая попытка только после отвода телефона; звук ошибки не повторяется по кадрам.
		_touching = true
		if not _transport.try_pay_fare(player):
			if _transport.can_pay_fare(player) and GameStateManager.get_stat(&"money") < _transport.get_fare_price():
				_denied = true
				_failure.play()
	_refresh_display()


func is_phone_present(player: Player) -> bool:
	return _phone_distance(player) <= tap_distance


func _phone_distance(player: Player) -> float:
	if not is_instance_valid(player):
		return INF
	# Это существующий смартфон постоянного Player Prefab, а не отдельный платёжный объект.
	var phone: Node3D = player.right_hand.get_node("Phone") as Node3D
	var screen: XRToolsViewport2DIn3D = phone.get_node("Screen") as XRToolsViewport2DIn3D
	if not phone.is_visible_in_tree() or not screen.enabled:
		return INF
	return screen.global_position.distance_to(_tap_point.global_position)


func _get_player() -> Player:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	return camera.get_parent().get_parent() as Player


func _on_fare_paid() -> void:
	_denied = false
	_failure.stop()
	_success.play()
	_refresh_display()


func _refresh_display() -> void:
	var next: int = 1 if _transport.is_fare_paid() else (2 if _denied else 0)
	if next == _display_state:
		return
	_display_state = next
	match next:
		0:
			_status.text = "ПРИЛОЖИТЕ\nТЕЛЕФОН"
			_indicator.albedo_color = Color(0.90, 0.60, 0.16)
		1:
			_status.text = "ОПЛАЧЕНО"
			_indicator.albedo_color = Color(0.20, 0.78, 0.34)
		2:
			_status.text = "НЕДОСТАТОЧНО\nСРЕДСТВ"
			_indicator.albedo_color = Color(0.90, 0.24, 0.18)
