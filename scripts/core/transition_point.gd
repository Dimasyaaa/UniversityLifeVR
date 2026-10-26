extends Area3D

## Точка перехода между локациями (Модуль 7, используется в Модуле 1).
## Узел НАЗЫВАЕТСЯ по соглашению: TransitionTo_Transport, TransitionTo_Campus…
## Срабатывает, когда в зону входит игрок (физическое тело, у предка которого
## есть группа «player»). collision_layer = 0: зона НЕ видна лучам указки/мышью,
## чтобы не перехватывать взаимодействие с дверью рядом.

## Путь к сцене-локации (см. ARCHITECTURE.md §2).
@export var target_scene: String = "res://scenes/locations/module_02_road.tscn"
## Имя Marker3D-точки входа в целевой сцене.
@export var target_spawn: String = "SpawnPoint"
## Пауза после срабатывания (защита от спама).
@export var cooldown_seconds: float = 3.0

var _cooldown: float = 0.0

func _ready() -> void:
	collision_layer = 0
	# Биты: 1 (World) + 2 (Interactable) + 3 (Player) — ловим игрока на любом
	# из известных слоёв.
	collision_mask = 7
	add_to_group("exit_point")
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

func _on_body_entered(body: Node3D) -> void:
	if _cooldown > 0.0 or SceneManager.is_transitioning:
		return
	if not _is_player(body):
		return
	_cooldown = cooldown_seconds
	if not ResourceLoader.exists(target_scene):
		_push_back(body)
		HintSystem.show_hint(
			"Выход пока закрыт:\nлокация «%s» ещё не собрана" % target_scene.get_file().get_basename(),
			3.5)
		return
	SceneManager.transition_to(target_scene, target_spawn)

## Отталкивает игрока обратно в комнату, если целевая локация ещё не готова
## (иначе он выйдет в пустоту за стеной).
func _push_back(body: Node3D) -> void:
	var away := body.global_position - global_position
	away.y = 0.0
	if away.length() < 0.05:
		away = -global_transform.basis.z
	body.global_position += away.normalized() * 0.45

## Игрок — тело, у которого хотя бы один предок состоит в группе «player»
## (корень префаба игрока).
func _is_player(body: Node) -> bool:
	var node: Node = body
	while node != null:
		if node.is_in_group("player"):
			return true
		node = node.get_parent()
	return false
