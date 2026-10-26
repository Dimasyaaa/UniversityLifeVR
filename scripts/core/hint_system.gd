extends Node

## Визуальные подсказки игрока (Модуль 7).
## Рисует текст через Label3D перед камерой — работает и в VR, и на десктопе.
## API: HintSystem.show_hint(text, duration), HintSystem.show_prompt(text),
## HintSystem.hide_prompt()

signal hint_shown(text: String, duration: float)
signal prompt_shown(text: String)

const HINT_OFFSET := Vector3(0.0, -0.30, -1.5)
const PROMPT_OFFSET := Vector3(0.0, -0.18, -1.5)

var _hint_label: Label3D
var _prompt_label: Label3D
var _hint_tween: Tween

func show_hint(text: String, duration: float = 2.5) -> void:
	print("[Hint] ", text)
	hint_shown.emit(text, duration)
	_ensure_labels()
	if _hint_label == null:
		return
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_label.text = text
	_hint_label.modulate = Color.WHITE
	_hint_label.visible = true
	_hint_tween = create_tween()
	_hint_tween.tween_interval(duration)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.5)
	_hint_tween.tween_callback(func() -> void:
		if _hint_label:
			_hint_label.visible = false)

func show_prompt(text: String) -> void:
	_ensure_labels()
	if _prompt_label == null:
		return
	if _prompt_label.text != text:
		prompt_shown.emit(text)
	_prompt_label.text = text
	_prompt_label.modulate = Color.WHITE
	_prompt_label.visible = true

func hide_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = false

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_transform := camera.global_transform
	if _hint_label and _hint_label.visible:
		_hint_label.global_position = cam_transform * HINT_OFFSET
	if _prompt_label and _prompt_label.visible:
		_prompt_label.global_position = cam_transform * PROMPT_OFFSET

func _ensure_labels() -> void:
	if _hint_label != null and is_instance_valid(_hint_label):
		return
	_hint_label = _make_label(48)
	_hint_label.position = HINT_OFFSET
	_prompt_label = _make_label(40)
	_prompt_label.position = PROMPT_OFFSET
	_prompt_label.modulate = Color(1.0, 0.92, 0.4, 1.0)

func _make_label(font_size: int) -> Label3D:
	var label := Label3D.new()
	label.pixel_size = 0.002
	label.font_size = font_size
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visible = false
	add_child(label)
	return label
