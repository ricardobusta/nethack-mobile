extends RefCounted

# All UI dimensions are logical, density-independent units. The window scales
# these once for the device; individual screens must not multiply by DPI again.
static func logical_size(pixels: Vector2i, dpi: float, mobile: bool) -> Vector2i:
	var density := clampf(dpi / 160.0, 1.0, 4.0) if mobile else 1.0
	return Vector2i(maxi(240, roundi(pixels.x / density)), maxi(240, roundi(pixels.y / density)))

static func touch_size(scale: float) -> int:
	return maxi(48, roundi(56 * scale))

static func surface(color: String, border: String = "", radius := 12, padding := 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	if not border.is_empty():
		box.border_color = Color(border)
		box.set_border_width_all(1)
	return box

static func create(scale: float) -> Theme:
	var result := Theme.new()
	result.default_font_size = maxi(16, roundi(18 * scale))
	result.set_constant("touch_size", "MobileUI", touch_size(scale))
	for type in ["VBoxContainer", "HBoxContainer", "GridContainer", "HFlowContainer"]:
		for key in ["separation", "h_separation", "v_separation"]:
			result.set_constant(key, type, 8)
	result.set_color("font_color", "Label", Color("eaf0f8"))
	for variant in ["Title", "Heading", "FieldLabel", "Caption", "Muted", "Error"]:
		result.set_type_variation(variant, "Label")
	result.set_font_size("font_size", "Title", roundi(28 * scale))
	result.set_font_size("font_size", "Heading", roundi(24 * scale))
	result.set_font_size("font_size", "FieldLabel", maxi(16, roundi(16 * scale)))
	result.set_font_size("font_size", "Caption", maxi(14, roundi(14 * scale)))
	result.set_color("font_color", "Muted", Color("a9bad0"))
	result.set_color("font_color", "Caption", Color("a9bad0"))
	result.set_color("font_color", "Error", Color("ffb4b4"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color: String = {"normal": "192b40", "hover": "243c56", "pressed": "304e6d", "disabled": "172131"}[state]
		result.set_stylebox(state, "Button", surface(color, "35506e"))
		result.set_color("font_color" if state == "normal" else "font_" + state + "_color", "Button", Color("eaf0f8" if state != "disabled" else "75849a"))
	var focus := surface("00000000", "e7c66b")
	focus.set_border_width_all(2)
	result.set_stylebox("focus", "Button", focus)
	result.set_type_variation("PrimaryButton", "Button")
	for state in ["normal", "hover", "pressed"]:
		result.set_stylebox(state, "PrimaryButton", surface("e7c66b" if state == "normal" else "f5d995"))
		result.set_color("font_color" if state == "normal" else "font_" + state + "_color", "PrimaryButton", Color("132033"))
	result.set_color("font_hover_pressed_color", "PrimaryButton", Color("132033"))
	result.set_color("font_focus_color", "PrimaryButton", Color("132033"))
	result.set_type_variation("QuietButton", "Button")
	result.set_stylebox("normal", "QuietButton", surface("101e30", "35506e", 12, 8))
	result.set_type_variation("ToggleRow", "Button")
	result.set_stylebox("pressed", "ToggleRow", surface("203e4c", "69cdb1"))
	result.set_stylebox("normal", "LineEdit", surface("0d1929", "415872"))
	result.set_stylebox("read_only", "LineEdit", surface("142033", "34475e"))
	result.set_stylebox("focus", "LineEdit", focus)
	result.set_color("font_color", "LineEdit", Color("f5f8fc"))
	result.set_color("font_placeholder_color", "LineEdit", Color("94a7c0"))
	result.set_color("caret_color", "LineEdit", Color("e7c66b"))
	result.set_color("selection_color", "LineEdit", Color("365777"))
	result.set_type_variation("InvalidInput", "LineEdit")
	result.set_stylebox("normal", "InvalidInput", surface("241d2a", "ef929b"))
	result.set_stylebox("panel", "PanelContainer", surface("122236", "2e435e"))
	result.set_stylebox("scroll", "VScrollBar", surface("132033", "", 4, 0))
	result.set_stylebox("grabber", "VScrollBar", surface("637e9b", "", 4, 0))
	return result
