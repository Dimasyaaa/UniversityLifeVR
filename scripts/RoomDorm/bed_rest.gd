extends InteractableBase

## Кровать (Модуль 1): «Поспать» — восстановление Энергии
## и продвижение игрового времени.

@export var energy_gain: float = 15.0
@export var sleep_minutes: int = 30

func _on_interact(_source: Node = null) -> void:
	if not GameStateManager.is_awake():
		HintSystem.show_hint("Сначала выключите будильник на столе", 3.0)
		return
	GameStateManager.change_stat("energy", energy_gain)
	GameStateManager.add_time(sleep_minutes)
	HintSystem.show_hint(
		"Вы отдохнули: +%d к Энергии, +%d мин (сейчас %s)" % [
			int(energy_gain),
			sleep_minutes,
			GameStateManager.get_time_string(),
		],
		4.0)
