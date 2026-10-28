extends StaticBody3D
## Общая рука вызывает interact() у кнопки; поведение принадлежит микроволновке.


func interact() -> void:
	get_parent().start_heating()
