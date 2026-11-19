extends VBoxContainer

signal value_changed(value: int)
@export var label_text := "Quantity"
@export var helper_text := "0 means the whole stack"
@export var minimum := 0
@export var maximum := 1000000
@export var step := 1
@export var suffix := ""
var current := 0
var value: int:
	get: return current
	set(next): set_value(next)
var input: LineEdit:
	get: return $Stepper/Input

func _ready() -> void:
	current = clampi(current, minimum, maximum)
	$Label.text = label_text
	$Helper.text = helper_text
	$Helper.visible = not helper_text.is_empty()
	$Stepper/Suffix.text = suffix
	$Stepper/Suffix.visible = not suffix.is_empty()
	$Stepper/Minus.pressed.connect(func():
		_commit()
		set_value(value - step))
	$Stepper/Plus.pressed.connect(func():
		_commit()
		set_value(value + step))
	input.text_changed.connect(_edit)
	input.text_submitted.connect(func(_text): _commit())
	input.focus_exited.connect(_commit)
	_resize()
	_sync()

func set_value(next: int) -> void:
	var clamped := clampi(next, minimum, maximum)
	var changed := clamped != current
	current = clamped
	_sync()
	if changed:
		value_changed.emit(current)

func _edit(text: String) -> void:
	if text.is_empty():
		return # Allow replacing the value without fighting the native keyboard.
	if not text.is_valid_int() or text.begins_with("-"):
		_sync()
		return
	var next := text.to_int()
	if next < minimum or next > maximum:
		return # Partial input may be out of range while replacing a value.
	if next != current:
		current = next
		_update_buttons()
		value_changed.emit(current)

func _commit() -> void:
	set_value(input.text.to_int() if input.text.is_valid_int() else current)

func _sync() -> void:
	input.text = str(current)
	_update_buttons()

func _update_buttons() -> void:
	$Stepper/Minus.disabled = current <= minimum
	$Stepper/Plus.disabled = current >= maximum

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_resize()

func _resize() -> void:
	var target := maxi(48, get_theme_constant("touch_size", "MobileUI"))
	input.custom_minimum_size.y = target
	for button in [$Stepper/Minus, $Stepper/Plus]:
		button.custom_minimum_size = Vector2(target, target)
