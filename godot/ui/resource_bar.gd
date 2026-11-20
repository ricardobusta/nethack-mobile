extends VBoxContainer
## A display, deliberately without a Slider or editable Range input.
var caption: Label
var fill: ProgressBar

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption = Label.new()
	caption.clip_text = false
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption)
	fill = ProgressBar.new()
	fill.show_percentage = false
	fill.custom_minimum_size.y = 8
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

func update_value(icon: String, current: int, maximum: int, color: Color) -> void:
	caption.text = "%s %d/%d" % [icon, current, maximum]
	fill.max_value = maxi(1, maximum)
	fill.value = clampi(current, 0, maxi(0, maximum))
	var style := StyleBoxFlat.new()
	style.bg_color = color
	fill.add_theme_stylebox_override("fill", style)
