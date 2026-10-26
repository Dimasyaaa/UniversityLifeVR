extends InteractableBase

## Микроволновка (Модуль 1, цепочка завтрака, шаг 2):
## готовит завтрак → +30 Сытости, выполнение квеста «breakfast».

@export var cook_seconds: float = 3.0
@export var satiety_gain: float = 30.0
@export var cook_time_minutes: int = 10

var _is_cooking: bool = false

func _on_interact(_source: Node = null) -> void:
	if _is_cooking:
		HintSystem.show_hint("Микроволновка ещё работает…", 2.0)
		return
	if GameStateManager.get_flag("breakfast_made"):
		HintSystem.show_hint("Завтрак уже готов. Приятного аппетита!", 3.0)
		return
	if not GameStateManager.get_flag("has_breakfast_products"):
		HintSystem.show_hint("Сначала возьмите продукты в холодильнике", 3.0)
		return
	_start_cooking()

func _start_cooking() -> void:
	_is_cooking = true
	HintSystem.show_hint("Микроволновка греет завтрак…", cook_seconds)
	await get_tree().create_timer(cook_seconds).timeout
	if not is_inside_tree():
		return
	_is_cooking = false
	GameStateManager.set_flag("breakfast_made", true)
	GameStateManager.change_stat("satiety", satiety_gain)
	GameStateManager.add_time(cook_time_minutes)
	QuestManager.complete_quest("breakfast")
	HintSystem.show_hint("Завтрак готов! +%d к Сытости" % int(satiety_gain), 4.0)
