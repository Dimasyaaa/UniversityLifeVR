@warning_ignore("missing_tool")
extends XRToolsFunctionPointer

## Указатель для VR-взаимодействия.
## Исключает коллизии контроллеров из луча, чтобы указатель одной руки
## не перехватывался UI-элементами другой руки.
func _ready() -> void:
	var origin := XRHelpers.get_xr_origin(self)
	if origin:
		# Находим все контроллеры в сцене игрока
		for controller in origin.find_children("*", "XRController3D", true, false):
			# Исключаем все коллизии контроллеров из луча указателя
			for collider in controller.find_children("*", "CollisionObject3D", true, false):
				$RayCast.add_exception(collider)
