extends InteractableBase

## Вешалка с одеждой (Модуль 1): «Одевание — выбор предмета одежды».
## Каждое взаимодействие надевает следующий комплект: выбранный предмет
## «исчезает» с вешалки, остальные висят. Первый раз — +5 к Настроению.

const OUTFITS := [
	"Спортивный костюм",
	"Джинсы и футболка",
	"Свитер и кардиган",
]

@export var mood_gain: float = 5.0

## Индекс надетой одежды; -1 — пока ничего не выбирали.
var _index: int = -1

func _on_interact(_source: Node = null) -> void:
	_index = (_index + 1) % OUTFITS.size()
	_apply_visual()
	if not GameStateManager.get_flag("dressed"):
		GameStateManager.set_flag("dressed", true)
		GameStateManager.change_stat("mood", mood_gain)
		HintSystem.show_hint(
			"Вы оделись: %s\n+%d к Настроению" % [OUTFITS[_index], int(mood_gain)],
			4.0)
	else:
		HintSystem.show_hint("Вы переоделись: %s" % OUTFITS[_index], 3.0)

func _apply_visual() -> void:
	var rack := get_parent()
	if rack == null:
		return
	for i in OUTFITS.size():
		var shirt := rack.get_node_or_null("Shirt%d" % (i + 1)) as MeshInstance3D
		if shirt:
			shirt.visible = i != _index
