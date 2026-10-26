extends InteractableBase

## Будильник на столе (Модуль 1, «Пробуждение по будильнику»).
## Первое взаимодействие = подъём: +Энергия, старт часов дня,
## достижение «Ранняя пташка» при пробуждении до 07:00.

@export var wake_energy_bonus: float = 25.0

@onready var _time_label: Label3D = get_node_or_null("TimeLabel")

func _ready() -> void:
	super._ready()
	if get_node_or_null("/root/GameStateManager") == null:
		push_warning("alarm_clock: GameStateManager не найден")
		return
	GameStateManager.time_changed.connect(_on_time_changed)
	_on_time_changed(GameStateManager.get_hours(), GameStateManager.get_minutes())

func _on_time_changed(hours: int, minutes: int) -> void:
	if _time_label:
		_time_label.text = "%02d:%02d" % [hours, minutes]

func _on_interact(_source: Node = null) -> void:
	if GameStateManager.is_awake():
		HintSystem.show_hint("Будильник выключен. Сейчас %s" % GameStateManager.get_time_string(), 3.0)
		return

	GameStateManager.set_awake(true)
	GameStateManager.change_stat("energy", wake_energy_bonus)

	if GameStateManager.game_minutes < 7 * 60:
		QuestManager.unlock_achievement("early_bird")

	HintSystem.show_hint(
		"Подъём! %s  +%d к Энергии\nГлавный квест: сдать экзамен в 16:00" % [
			GameStateManager.get_time_string(),
			int(wake_energy_bonus),
		],
		6.0)
