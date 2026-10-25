@tool
extends "res://addons/godot-xr-tools/functions/function_pointer.gd"


func _enter_tree() -> void:
	# В симуляторе направление руки уже соответствует направлению луча.
	hand_offset_mode = XRTools.HandOffsetMode.HAND_OFFSET_AIM

	if not Engine.is_editor_hint():
		var interface: XRInterface = XRServer.find_interface("OpenXR")

		# Для настоящего VR оставляем автоматическую поправку XR Tools.
		if interface != null and interface.is_initialized():
			hand_offset_mode = XRTools.HandOffsetMode.HAND_OFFSET_AUTO

	super._enter_tree()
