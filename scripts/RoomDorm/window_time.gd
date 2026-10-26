extends InteractableBase

## Окно (Модуль 1): «Взаимодействие с окном — смена времени суток».
## Переключает пресеты освещения WorldEnvironment текущей сцены.
## Это визуальная демонстрация: игровое время (GameStateManager) не меняется.

const PRESETS := [
	{
		"name": "Утро",
		"background": Color(0.55, 0.62, 0.75),
		"ambient": Color(1.0, 0.93, 0.82),
		"ambient_energy": 1.2,
	},
	{
		"name": "День",
		"background": Color(0.65, 0.78, 0.95),
		"ambient": Color(1.0, 1.0, 1.0),
		"ambient_energy": 1.6,
	},
	{
		"name": "Вечер",
		"background": Color(0.75, 0.45, 0.3),
		"ambient": Color(1.0, 0.75, 0.55),
		"ambient_energy": 0.8,
	},
	{
		"name": "Ночь",
		"background": Color(0.05, 0.07, 0.15),
		"ambient": Color(0.5, 0.6, 0.9),
		"ambient_energy": 0.25,
	},
]

var _index: int = -1

func _on_interact(_source: Node = null) -> void:
	var environment := _find_environment()
	if environment == null:
		HintSystem.show_hint("Окно: настройки освещения не найдены", 3.0)
		return
	_index = (_index + 1) % PRESETS.size()
	var preset: Dictionary = PRESETS[_index]
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = preset["background"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = preset["ambient"]
	environment.ambient_light_energy = float(preset["ambient_energy"])
	HintSystem.show_hint("Время суток: %s" % preset["name"], 3.0)

func _find_environment() -> Environment:
	# owner — корень сцены, в которую вставлен объект (работает и вне change_scene);
	# current_scene — запасной вариант.
	var scope: Node = owner
	if scope == null:
		scope = get_tree().current_scene
	if scope == null:
		return null
	var worlds := scope.find_children("*", "WorldEnvironment", true, false)
	if worlds.is_empty():
		return null
	return (worlds[0] as WorldEnvironment).environment
