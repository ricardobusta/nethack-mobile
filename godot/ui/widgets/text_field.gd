extends VBoxContainer

signal text_changed(text: String)
signal text_submitted(text: String)

@export var label_text := "Text"
@export var placeholder := ""
@export var helper_text := ""
@export var keyboard_type: LineEdit.VirtualKeyboardType = LineEdit.KEYBOARD_TYPE_DEFAULT
var input: LineEdit:
	get: return $Editor/Input
var invalid := false

func _ready() -> void:
	$Label.text = label_text
	input.placeholder_text = placeholder
	input.virtual_keyboard_type = keyboard_type
	$Helper.text = helper_text
	$Helper.visible = not helper_text.is_empty()
	$Editor/Clear.pressed.connect(func():
		input.clear()
		input.grab_focus())
	input.text_changed.connect(func(text):
		if invalid:
			show_error("")
		text_changed.emit(text))
	input.text_submitted.connect(func(text): text_submitted.emit(text))
	_resize()

func show_error(error: String) -> void:
	invalid = not error.is_empty()
	input.theme_type_variation = "InvalidInput" if invalid else ""
	$Helper.theme_type_variation = "Error" if invalid else "Caption"
	$Helper.text = error if invalid else helper_text
	$Helper.visible = not $Helper.text.is_empty()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_resize()

func _resize() -> void:
	var target := maxi(48, get_theme_constant("touch_size", "MobileUI"))
	input.custom_minimum_size.y = target
	$Editor/Clear.custom_minimum_size = Vector2(target, target)
