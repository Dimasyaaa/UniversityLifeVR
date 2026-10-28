extends StaticBody3D
signal pressed()
## Общая рука вызывает interact() у кнопки; поведение принадлежит микроволновке.


func interact() -> void:
	if SaveManager.is_loading() or SceneManager.is_transitioning():
		return
	pressed.emit()
	get_parent().start_heating()
