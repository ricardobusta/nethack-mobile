extends Button

func _ready() -> void:
	_resize()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_resize()

func _resize() -> void:
	custom_minimum_size.y = maxi(48, get_theme_constant("touch_size", "MobileUI"))
