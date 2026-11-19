extends Button

@export var label_text := "Option"
@export var helper_text := ""

func _ready() -> void:
	$Row/Copy/Label.text = label_text
	$Row/Copy/Helper.text = helper_text
	$Row/Copy/Helper.visible = not helper_text.is_empty()
	toggled.connect(func(_on): _refresh())
	$Row.minimum_size_changed.connect(_refresh)
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_refresh()

func _refresh() -> void:
	custom_minimum_size.y = maxf(maxi(48, get_theme_constant("touch_size", "MobileUI")) + 12, $Row.get_combined_minimum_size().y + 24)
	$Row/State.text = "On" if button_pressed else "Off"
	$Row/State.modulate = Color("8ce3c4") if button_pressed else Color("a9bad0")

func set_checked(checked: bool) -> void:
	set_pressed_no_signal(checked)
	_refresh()
