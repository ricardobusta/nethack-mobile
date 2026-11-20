extends Control
## Full-viewport input shield. Callers constrain only content_panel.
var content_panel: PanelContainer

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.025, 0.04, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	content_panel = PanelContainer.new()
	content_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content_panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("101925")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		panel_style.set_content_margin(side, 16)
	content_panel.add_theme_stylebox_override("panel", panel_style)

func constrain(left: float, top: float, right: float, bottom: float, max_width := 640.0) -> void:
	var margin := maxf(0.0, (size.x - left - right - max_width) / 2.0)
	content_panel.offset_left = left + margin
	content_panel.offset_top = top
	content_panel.offset_right = -right - margin
	content_panel.offset_bottom = -bottom
