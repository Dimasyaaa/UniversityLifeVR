extends InteractableBase

## Холодильник (Модуль 1, цепочка завтрака, шаг 1):
## достаём продукты → флаг «has_breakfast_products».

func _on_interact(_source: Node = null) -> void:
	if GameStateManager.get_flag("has_breakfast_products"):
		HintSystem.show_hint("В холодильнике больше нет продуктов", 3.0)
		return
	GameStateManager.set_flag("has_breakfast_products", true)
	HintSystem.show_hint(
		"Вы взяли продукты: яйца, сыр, хлеб.\nРазогрейте завтрак в микроволновке",
		5.0)
