extends SceneTree

const MobileTheme = preload("res://ui/mobile_theme.gd")
const NumberField = preload("res://ui/widgets/number_field.tscn")
var app: Control
var original_scale := 1.0

func _initialize() -> void:
	call_deferred("run")

func fail(reason: String) -> void:
	push_error(reason)
	app._change_scale(original_scale - app.ui_scale)
	quit(1)

func settle() -> void:
	for i in range(4):
		await process_frame

func type_text(text: String) -> void:
	for character in text:
		var key := InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.pressed = true
		root.push_input(key, true)

func capture(name: String) -> void:
	if OS.get_cmdline_user_args().has("--screenshot"):
		await create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/widgets-" + name + ".png")

func form_fits() -> bool:
	return app.overlay.get_global_rect().end.y <= root.size.y and app.overlay_box.get_global_rect().end.y <= app.overlay.get_global_rect().end.y

func run() -> void:
	if MobileTheme.logical_size(Vector2i(1080, 2400), 420, true) != Vector2i(411, 914) or MobileTheme.logical_size(Vector2i(2400, 1600), 320, true) != Vector2i(1200, 800):
		push_error("Density scaling did not preserve density-independent UI dimensions")
		quit(1)
		return
	app = load("res://main.tscn").instantiate()
	if not app.has_method("_show_settings"):
		push_error("Main UI failed to compile")
		quit(1)
		return
	root.add_child(app)
	app.status_fields = {18: "HP: 7", 19: "HP max: 23", 11: "Power: 0", 12: "Power max: 0", 17: "Hunger: Hungry", 22: "Blind, Stunned"}
	app._update_resources()
	assert(app.hp_bar.caption.text == "♥ 7/23")
	assert(app.power_bar.caption.text == "✦ 0/0" and app.power_bar.fill.value == 0)
	assert(app.badges.get_child_count() == 3)
	app.status_fields[18] = "HP: 45" # Polymorph uses the engine's active HP fields.
	app.status_fields[19] = "HP max: 62"
	app._update_resources()
	assert(app.hp_bar.caption.text == "♥ 45/62")
	original_scale = app.ui_scale
	app._change_scale(1.0 - app.ui_scale)
	for dimensions in [Vector2i(320, 640), Vector2i(411, 914), Vector2i(914, 411), Vector2i(1200, 800), Vector2i(800, 1200)]:
		root.size = dimensions
		app.overlay.hide()
		app.status.text = "Adventurer the Candidate\nHP 14/14 · Pw 5/5 · AC 4 · XL 1\nSt 16 Dx 17 Co 11 In 10 Wi 10 Ch 11 · Lawful"
		app.message.text = "The dungeon awaits. Choose your next move."
		await settle()
		if app.page.get_global_rect().end.y > dimensions.y or app.map.size.y < 80:
			for child in app.page.get_children():
				print(child.name, " ", child.size, " min ", child.get_combined_minimum_size())
			fail("Game controls escaped the screen at %s: page=%s map=%s" % [dimensions, app.page.get_global_rect(), app.map.size])
			return
		app._show_home()
		await settle()
		if app.overlay.content_panel.size.x > minf(dimensions.x - 30, 642) or app.overlay.size != Vector2(dimensions) or app.name_widget.input.get_theme_font_size("font_size") < 16 or app.name_widget.input.size.y < 48:
			fail("Form width, readable text or touch sizing failed at %s" % dimensions)
			return
		await capture("home-%dx%d" % [dimensions.x, dimensions.y])
		app._show_settings()
		await settle()
		var heading: Control = app.overlay_box.get_child(0)
		if heading.get_global_rect().position.y < app.overlay.get_global_rect().position.y:
			fail("Settings heading escaped the form at %s" % dimensions)
			return
		var footer: Control = app.overlay_box.get_child(app.overlay_box.get_child_count() - 1)
		if footer.get_global_rect().end.y > dimensions.y:
			fail("Settings footer escaped the screen at %s" % dimensions)
			return
		await capture("settings-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(411, 914)
	app._show_home()
	await settle()
	app._start("1invalid")
	if not app.name_widget.invalid:
		fail("Invalid character name did not show a field error")
		return
	app.name_widget.input.clear()
	app.name_widget.input.grab_focus()
	type_text("MobileHero")
	await settle()
	if app.name_widget.input.text != "MobileHero" or app.name_widget.invalid:
		fail("Text entry or clearing the field error failed")
		return
	var number := NumberField.instantiate()
	number.minimum = 5
	app.name_widget.get_parent().add_child(number)
	await settle()
	if number.value != 5:
		fail("A numeric prefab must initialize within its configured bounds")
		return
	number.minimum = 0
	number.input.grab_focus()
	number.input.select_all()
	type_text("12")
	await settle()
	if number.value != 12 or number.get_node("Stepper/Minus").disabled:
		fail("Numeric keyboard input did not update the stepper: text=%s value=%d focus=%s" % [number.input.text, number.value, root.gui_get_focus_owner()])
		return
	root.gui_release_focus()
	await settle()
	for pressed in [true, false]:
		var tap := InputEventScreenTouch.new()
		tap.position = number.input.get_global_rect().get_center()
		tap.pressed = pressed
		root.push_input(tap, true)
	await settle()
	if not number.input.has_selection() or number.input.get_selected_text() != "12":
		fail("Tapping a numeric field must select its value for replacement")
		return
	number.get_node("Stepper/Plus").pressed.emit()
	if number.value != 13:
		fail("Quantity increase failed")
		return
	number.value = -1
	if number.value != 0:
		fail("Quantity lower bound failed")
		return
	number.minimum = 90
	number.maximum = 150
	number.value = 150
	number.input.grab_focus()
	number.input.select_all()
	for digit in "100":
		type_text(digit)
		await settle()
	if number.value != 100 or number.input.text != "100":
		fail("Editing a value with a nonzero minimum rejected partial input")
		return
	app._show_settings()
	await settle()
	app.menus[42] = []
	for i in range(3):
		app.menus[42].append({"text": "Choice %d" % i, "v": PackedInt64Array([42, i, 0, 1, 0, 0, 0, 0])})
	app.active_prompt = {"v": PackedInt64Array([4, 1, 42])}
	app._show_menu()
	if app.search != null:
		fail("Small choice menus should not need a search field")
		return
	app.active_prompt.clear()
	app._show_settings()
	await settle()
	for control in app.overlay.find_children("*", "Button", true, false):
		if control.get_script() == load("res://ui/widgets/toggle_field.gd"):
			var before: bool = app.map.tiled
			control.button_pressed = not before
			if app.map.tiled == before or control.get_node("Row/State").text != ("On" if control.button_pressed else "Off"):
				fail("Reusable toggle did not update its value and visual state")
				return
			control.button_pressed = before
	app._show_home()
	await settle()
	var same_field: Control = app.name_widget
	app._change_scale(0.5)
	await settle()
	if same_field.input.size.y < 80 or same_field.input.get_theme_font_size("font_size") < 26:
		fail("An existing field did not respond to a theme size change")
		return
	for dimensions in [Vector2i(320, 640), Vector2i(914, 411), Vector2i(1200, 800), Vector2i(800, 1200)]:
		root.size = dimensions
		app.overlay.hide()
		app.status_fields[18] = "HP: 250"
		app.status_fields[19] = "HP max: 300"
		app._update_resources()
		await settle()
		var caption: Label = app.hp_bar.caption
		var width := caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
		assert(not caption.clip_text and (width <= caption.size.x or caption.get_line_count() > 1))
		if app.page.get_global_rect().end.y > dimensions.y or app.map.size.y < 80:
			fail("Large-text game controls escaped the screen at %s" % dimensions)
			return
		app._show_directions()
		await settle()
		if not form_fits():
			fail("Large-text direction picker escaped the screen")
			return
		app.active_prompt = {"text": "Choose an action", "v": PackedInt64Array([2, 0, 0]), "extra": "abcdefghijklmnopqrstuvwxyz"}
		app._show_prompt()
		await settle()
		if not form_fits():
			fail("Large-text choice prompt escaped the screen")
			return
		app._show_keyboard()
		await settle()
		if not form_fits():
			fail("Large-text key picker escaped the screen")
			return
		app.active_prompt.clear()
	root.size = Vector2i(411, 914)
	app._show_home()
	await settle()
	if app.name_widget.input.size.y < 80 or app.name_widget.input.get_theme_font_size("font_size") < 26:
		fail("Existing prefabs did not scale with the shared theme")
		return
	await capture("large-text")
	var host := preload("res://ui/modal_host.gd").new()
	host.theme = app.theme
	root.add_child(host)
	var box := VBoxContainer.new()
	host.content_panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var keyboard_field := NumberField.instantiate()
	scroll.add_child(keyboard_field)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.y = 84
	box.add_child(back)
	host.constrain(40, 36, 24, 300) # Cutout plus software-keyboard exclusion.
	await settle()
	assert(host.get_global_rect() == Rect2(Vector2.ZERO, Vector2(root.size)))
	assert(host.get_child(0).size == Vector2(root.size))
	assert(host.content_panel.position.x >= 40 and host.content_panel.position.y >= 36)
	assert(back.get_global_rect().end.y <= root.size.y - 300)
	host.free()
	app._change_scale(original_scale - app.ui_scale)
	print("Mobile widgets passed: density scaling, phone/tablet layouts, text entry, inline errors, quantity controls and shared text scaling.")
	quit(0)
