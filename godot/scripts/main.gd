extends Control

const MessageLog = preload("res://ui/message_log.gd")
const ResourceBar = preload("res://ui/resource_bar.gd")
const ModalHost = preload("res://ui/modal_host.gd")
const EndReport = preload("res://scripts/end_report.gd")
const MapView = preload("res://scripts/map_view.gd")
const MobileScroll = preload("res://scripts/mobile_scroll.gd")
const MobileTheme = preload("res://ui/mobile_theme.gd")
const ActionButton = preload("res://ui/widgets/action_button.tscn")
const TextField = preload("res://ui/widgets/text_field.tscn")
const NumberField = preload("res://ui/widgets/number_field.tscn")
const ToggleField = preload("res://ui/widgets/toggle_field.tscn")
const SOURCE_URL := "https://github.com/ricardobusta/nethack-mobile"
var current_turn := 0
var session_phase := 0
var end_report: Dictionary = {}
var report_visible := false
var report_scroll: ScrollContainer
var report_page := 0
var engine_version := "5.0.0"
var save_namespace := "5.0.0-0-mobile1"
var asset_revision := "unversioned"
const ACTIONS := {"Inventory": "i", "Search": "s", "Wait": ".", "Pick up": ",", "Down": ">", "Up": "<", "Open": "o", "Kick": "\u0004", "Eat": "e", "Drink": "q", "Read": "r", "Apply": "a", "Cast": "Z", "Fire": "f", "Throw": "t", "Zap": "z", "Look": ":", "Look far": ";", "Save": "S"}
var session: RefCounted
var map: Control
var page: VBoxContainer
var header_spacer: Control
var header: HBoxContainer
var body: BoxContainer
var info_column: VBoxContainer
var info_scroll: ScrollContainer
var status: Label
var message: RichTextLabel
var hint: Label
var portrait_actions: HBoxContainer
var action_bar: BoxContainer
var action_strip: ScrollContainer
var navigation_strip: ScrollContainer
var overlay: Control
var overlay_box: VBoxContainer
var overlay_notice: Label
var menu_list: VBoxContainer
var search: LineEdit
var root_margin: MarginContainer
var active_prompt: Dictionary = {}
var windows: Dictionary = {}
var window_types: Dictionary = {}
var menus: Dictionary = {}
var titles: Dictionary = {}
var commands: Array[Dictionary] = []
var status_fields: Dictionary = {}
var history: Array[String] = []
var character_snapshot := ""
var equipment: Array[Dictionary] = []
var menu_context: Dictionary = {}
var item_metadata: Dictionary = {}
var return_to_inventory := false
var selected: Dictionary = {}
var current_name := ""
var settings := ConfigFile.new()
var actions: Array = ["Inventory", "Search", "Wait", "Pick up", "Down"]
var ui_scale := 1.0
var auto_resume := false
var application_paused := false
var background_resume := false
var resume_ready := false
var quiet_resume := false
var keyboard_ctrl := false
var keyboard_alt := false
var key_entry: LineEdit
var menu_how := 0
var dirty_ui := false
var resources: HBoxContainer
var hp_bar: VBoxContainer
var power_bar: VBoxContainer
var avatar: Button
var badges: HFlowContainer
var side_actions: ScrollContainer
var side_actions_box: VBoxContainer
var navigation: BoxContainer
var name_widget: VBoxContainer

func _ready() -> void:
	var build_info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
	if build_info is Dictionary:
		engine_version = String(build_info.get("engine_version", engine_version))
		save_namespace = String(build_info.get("save_namespace", save_namespace))
		asset_revision = String(build_info.get("assets_sha256", build_info.get("source_revision", asset_revision)))
	settings.load("user://settings.cfg")
	actions = settings.get_value("ui", "actions", actions)
	ui_scale = clampf(float(settings.get_value("ui", "scale", 1.0)), 0.9, 1.5)
	theme = MobileTheme.create(ui_scale)
	_configure_display()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	if ClassDB.class_exists("NetHackSession"):
		session = ClassDB.instantiate("NetHackSession")
	end_report = EndReport.read_report()
	if not end_report.is_empty() and not end_report.get("dismissed", false):
		_show_end_report(int(end_report.get("last_page", 0)))
	else:
		_show_home()
	_layout()

func _button(text: String, callback: Callable, parent: Node, compact := false) -> Button:
	var b := ActionButton.instantiate() as Button
	b.custom_minimum_size.x = 48 if compact else 80
	if compact:
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
	if text in ["Start / resume character", "Submit", "Confirm", "Continue"]:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(callback)
	parent.add_child(b)
	b.text = text # Shape after inheriting the screen's font and density theme.
	return b

func _touch_size() -> float:
	return MobileTheme.touch_size(ui_scale)

func _configure_display() -> void:
	var window := get_window()
	var logical := MobileTheme.logical_size(window.size, DisplayServer.screen_get_dpi(), OS.has_feature("mobile"))
	if window.content_scale_size != logical:
		window.content_scale_size = logical

func _field(parent: Node, title: String, placeholder := "", helper := "") -> VBoxContainer:
	var field := TextField.instantiate() as VBoxContainer
	field.label_text = title
	field.placeholder = placeholder
	field.helper_text = helper
	parent.add_child(field)
	return field

func _toggle(parent: Node, title: String, checked: bool, helper := "") -> Button:
	var field := ToggleField.instantiate() as Button
	field.label_text = title
	field.helper_text = helper
	parent.add_child(field)
	field.set_checked(checked)
	return field

func _build_ui() -> void:
	root_margin = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_margin)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	root_margin.add_child(page)
	header = HBoxContainer.new()
	page.add_child(header)
	avatar = _button("@", _show_character, header, true)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	avatar.tooltip_text = "Character"
	avatar.expand_icon = true
	avatar.add_theme_constant_override("icon_max_width", 40)
	resources = HBoxContainer.new()
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(resources)
	hp_bar = ResourceBar.new()
	resources.add_child(hp_bar)
	power_bar = ResourceBar.new()
	resources.add_child(power_bar)
	badges = HFlowContainer.new()
	page.add_child(badges)
	header_spacer = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var mode_button := _button("ASCII", _toggle_mode, header, true)
	mode_button.name = "Mode"
	mode_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button("☰", _show_settings, header, true).size_flags_horizontal = Control.SIZE_SHRINK_END
	body = BoxContainer.new()
	body.vertical = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	page.add_child(body)
	info_scroll = MobileScroll.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.follow_focus = true
	body.add_child(info_scroll)
	info_column = VBoxContainer.new()
	info_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(info_column)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "NetHack %s · Offline · NGPL" % engine_version
	# Retained as a hidden compatibility summary; gameplay uses resource widgets.
	status.hide()
	info_column.add_child(status)
	message = MessageLog.new()
	message.scroll_host = info_scroll
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 86
	info_column.add_child(message)
	map = MapView.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size.y = 160
	map.tiled = bool(settings.get_value("ui", "tiles", true))
	(header.get_node("Mode") as Button).text = "Tiles" if map.tiled else "ASCII"
	map.tile_pressed.connect(_tile_pressed)
	body.add_child(map)
	hint = Label.new()
	hint.text = "Tap a destination · Pinch to zoom · Drag to explore"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 2
	hint.add_theme_color_override("font_color", Color("99a9bf"))
	page.add_child(hint)
	action_strip = _horizontal_strip(page)
	portrait_actions = HBoxContainer.new()
	action_strip.add_child(portrait_actions)
	action_bar = BoxContainer.new()
	action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_actions.add_child(action_bar)
	_refresh_actions()
	navigation_strip = _horizontal_strip(page)
	navigation = BoxContainer.new()
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_strip.add_child(navigation)
	_button("Commands", _open_commands, navigation)
	_button("Direction", _show_directions, navigation)
	_button("Keys", _show_keyboard, navigation)
	_button("Stop", func(): _send_key(27), navigation, true)
	_button("Center", func(): map.recenter(), navigation, true)
	for button in navigation.get_children():
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
	side_actions = MobileScroll.new()
	side_actions.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(side_actions)
	side_actions_box = VBoxContainer.new()
	side_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_actions.add_child(side_actions_box)
	overlay = ModalHost.new()
	add_child(overlay)
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 12)
	overlay.content_panel.add_child(overlay_box)
	overlay.visibility_changed.connect(func(): page.visible = not overlay.visible)
	overlay.hide()

func _horizontal_strip(parent: Node) -> ScrollContainer:
	var strip := MobileScroll.new()
	strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.follow_focus = true
	parent.add_child(strip)
	return strip

func _layout() -> void:
	_configure_display()
	var viewport := get_viewport_rect().size
	var landscape := viewport.x > viewport.y
	if resources.get_parent() != (header if landscape else page):
		resources.reparent(header if landscape else page)
		(header if landscape else page).move_child(resources, 1)
	body.vertical = not landscape
	header_spacer.visible = not landscape
	var compact_portrait := not landscape and (viewport.y < 760 or ui_scale > 1.2)
	side_actions.visible = landscape
	action_strip.visible = not landscape
	navigation_strip.visible = not landscape and not compact_portrait
	action_bar.vertical = landscape
	navigation.vertical = landscape
	var action_parent: Node = side_actions_box if landscape else portrait_actions
	var nav_parent: Node = side_actions_box if landscape else portrait_actions if compact_portrait else navigation_strip
	if action_bar.get_parent() != action_parent:
		action_bar.reparent(action_parent)
	if navigation.get_parent() != nav_parent:
		navigation.reparent(nav_parent)
	side_actions.custom_minimum_size.x = clampf(viewport.x * 0.16, 120 * ui_scale, 200) if landscape else 0
	for box in [action_bar, navigation]:
		for button in box.get_children():
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if landscape else TextServer.AUTOWRAP_OFF

	var compact := landscape or viewport.y < 760 or ui_scale > 1.2
	if compact and hint.get_parent() != info_column:
		hint.reparent(info_column)
	elif not compact and hint.get_parent() != page:
		hint.reparent(page)
		page.move_child(hint, page.get_child_count() - 3)
	for strip in [action_strip, navigation_strip]:
		strip.custom_minimum_size.y = _touch_size()
	map.custom_minimum_size.y = 80 if viewport.y < 700 or ui_scale > 1.2 else 160
	info_scroll.custom_minimum_size.x = clampf(viewport.x * 0.20, 130 * ui_scale, 280) if landscape else 0
	info_scroll.size_flags_horizontal = Control.SIZE_FILL if landscape else Control.SIZE_EXPAND_FILL
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL if landscape else Control.SIZE_FILL
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var left := 16.0
	var top := 12.0
	var right := 16.0
	var bottom := 12.0
	if OS.has_feature("mobile") and screen.x > 0:
		left += safe.position.x * viewport.x / screen.x
		top += safe.position.y * viewport.y / screen.y
		right += (screen.x - safe.end.x) * viewport.x / screen.x
		bottom += (screen.y - safe.end.y) * viewport.y / screen.y
	var keyboard_height := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	if keyboard_height > 0 and screen.y > 0:
		bottom = maxf(bottom, keyboard_height * viewport.y / screen.y)
	for container in [root_margin]:
		container.add_theme_constant_override("margin_left", int(left))
		container.add_theme_constant_override("margin_top", int(top))
		container.add_theme_constant_override("margin_right", int(right))
		container.add_theme_constant_override("margin_bottom", int(bottom))
	overlay.constrain(left, top + 6, right, bottom + 6)
	message.custom_minimum_size.y = 44 if landscape else 64
	info_scroll.custom_minimum_size.y = 0 if landscape else minf(info_column.get_combined_minimum_size().y, minf(80 if compact_portrait else 180, viewport.y * 0.2))

func _refresh_actions() -> void:
	for child in action_bar.get_children():
		child.queue_free()
	for action in actions:
		if ACTIONS.has(action):
			var button := _button(action, func(): _send_key(String(ACTIONS[action]).unicode_at(0)), action_bar)
			button.autowrap_mode = TextServer.AUTOWRAP_OFF

func _clear_overlay(title: String) -> void:
	overlay.set_meta("engine_input", false)
	_dismiss_keyboard()
	for child in overlay_box.get_children():
		overlay_box.remove_child(child)
		child.queue_free()
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = "Heading"
	overlay_box.add_child(label)
	label.text = title
	overlay_notice = Label.new()
	overlay_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_notice.add_theme_color_override("font_color", Color("ffb0a8"))
	overlay_box.add_child(overlay_notice)
	overlay_notice.hide()
	overlay.show()

func _show_error(text: String) -> void:
	message.text = text
	if overlay.visible and is_instance_valid(overlay_notice):
		overlay_notice.text = text
		overlay_notice.show()

func _scroll_list() -> VBoxContainer:
	var scroll := MobileScroll.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_box.add_child(scroll)
	if session_phase == 3 and not end_report.is_empty() and not end_report.pages.is_empty():
		var captured_index := int(end_report.last_page)
		scroll.get_v_scroll_bar().value_changed.connect(func(value):
			end_report.pages[captured_index].scroll = int(value)
			EndReport.write_report(end_report))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)
	return list

func _show_home() -> void:
	report_visible = false
	_clear_overlay("NetHack Mobile")
	var content := _scroll_list()
	var intro := Label.new()
	intro.text = "The dungeon awaits.\n\nContinue your adventure, or choose a name for a new character."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)
	name_widget = _field(content, "Character name", "Your adventurer's name", "1–24 letters, digits or underscores. Start with a letter.")
	var name_field: LineEdit = name_widget.input
	name_field.text = settings.get_value("game", "last_name", "Adventurer")
	name_field.max_length = 24
	name_widget.text_submitted.connect(func(_text): _start(name_field.text))
	var start_button := _button("Start / resume character", func(): _start(name_field.text), content)
	start_button.disabled = session == null
	if session == null:
		intro.text += "\n\nNative engine unavailable. Run python3 scripts/build.py host before opening this project."
	if not end_report.is_empty():
		_button("Last run", func(): _show_end_report(int(end_report.get("last_page", 0))), content)
	_button("Help & licenses", _show_about, content)

func _prepare_game(name_text: String) -> String:
	var base := "user://games/%s/%s" % [save_namespace, name_text]
	var directory := base
	var run := 1
	while FileAccess.file_exists(directory.path_join(".mobile-ended")):
		directory = base + "-run-%d" % run
		run += 1
	var error := DirAccess.make_dir_recursive_absolute(directory + "/save")
	if error != OK:
		return ""
	var file_list = JSON.parse_string(FileAccess.get_file_as_string("res://data/files.json"))
	if not file_list is Array:
		return ""
	var marker := directory.path_join(".assets_revision")
	var refresh := not FileAccess.file_exists(marker) or FileAccess.get_file_as_string(marker) != asset_revision
	for filename: String in file_list:
		# Refresh only bundled support files; runtime saves, bones and scores
		# are absent from the bundle manifest and are never replaced.
		var destination := directory.path_join(filename)
		if FileAccess.file_exists(destination) and not refresh and filename != "build.json":
			continue
		var bytes := FileAccess.get_file_as_bytes("res://data/" + filename)
		var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
		if file == null:
			return ""
		file.store_buffer(bytes)
		file.flush()
		file.close()
		if DirAccess.rename_absolute(destination + ".tmp", destination) != OK:
			return ""
	var installed := FileAccess.open(marker + ".tmp", FileAccess.WRITE)
	if installed == null:
		return ""
	installed.store_string(asset_revision)
	installed.flush()
	installed.close()
	if DirAccess.rename_absolute(marker + ".tmp", marker) != OK:
		return ""
	return ProjectSettings.globalize_path(directory)

func _start(name_text: String, allow_new_version := false, silently := false) -> void:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z][A-Za-z0-9_]{0,23}$")
	if regex.search(name_text) == null:
		if is_instance_valid(name_widget):
			name_widget.show_error("Start with a letter. Use up to 24 letters, digits or underscores.")
			name_widget.input.grab_focus()
		else:
			_show_error("Use 1–24 letters, digits or underscores; start with a letter.")
		return
	if not allow_new_version and DirAccess.dir_exists_absolute("user://games") and not DirAccess.dir_exists_absolute("user://games/%s/%s" % [save_namespace, name_text]):
		for saved_version: String in DirAccess.get_directories_at("user://games"):
			if saved_version != save_namespace and DirAccess.dir_exists_absolute("user://games/%s/%s" % [saved_version, name_text]):
				_clear_overlay("An older character is preserved")
				var explanation := Label.new()
				explanation.text = "This character has data from another engine version. Keep using its matching app version to finish that game. Starting here creates a separate game; your older files stay untouched."
				explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				overlay_box.add_child(explanation)
				_button("Start a separate game", func(): _start(name_text, true), overlay_box)
				_button("Back", _show_home, overlay_box)
				return
	var directory := _prepare_game(name_text)
	if directory.is_empty():
		_show_error("Could not install game data. Check available storage and try again.")
		return
	report_visible = false
	session_phase = 0
	current_name = name_text
	settings.set_value("game", "last_name", current_name)
	settings.save("user://settings.cfg")
	map.clear_map()
	character_snapshot = ""
	equipment.clear()
	menu_context.clear()
	item_metadata.clear()
	return_to_inventory = false
	status_fields.clear()
	windows.clear()
	window_types.clear()
	menus.clear()
	commands.clear()
	active_prompt.clear()
	auto_resume = false
	background_resume = false
	resume_ready = false
	quiet_resume = silently
	if session.start(directory, name_text):
		overlay.hide()
		if not silently:
			message.text = "Entering the dungeon…"
	else:
		_show_error("The native engine could not start.")

func _process(_delta: float) -> void:
	if session == null:
		return
	for e: Dictionary in session.poll():
		_handle_event(e)
	if dirty_ui:
		dirty_ui = false
		status.text = _format_status()
		_update_resources()
	_layout()

func _stat(index: int, fallback := "?") -> String:
	var value := String(status_fields.get(index, fallback))
	var separator := value.find(": ")
	return value.substr(separator + 2).strip_edges() if separator >= 0 else value.strip_edges()

func _item_icon(tile: int) -> Texture2D:
	if map.atlas == null or tile < 0:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = map.atlas
	icon.region = Rect2(Vector2(tile % 40, tile / 40) * 16, Vector2(16, 16))
	return icon

func _update_resources() -> void:
	hp_bar.update_value("♥", int(_stat(18, "0")), int(_stat(19, "0")), Color("d65b66"))
	power_bar.update_value("✦", int(_stat(11, "0")), int(_stat(12, "0")), Color("719ad6"))
	for child in badges.get_children():
		badges.remove_child(child)
		child.queue_free()
	for index in [9, 17, 22]:
		for condition in _stat(index, "").split(", ", false):
			var badge := Label.new()
			badge.theme_type_variation = "Caption"
			badge.text = "⚠ " + condition
			badge.add_theme_color_override("font_color", Color("ffe08c"))
			badges.add_child(badge)
	var cell: Dictionary = map.cells.get(map.player, {})
	avatar.icon = _item_icon(int(cell.get("tile", -1)))
	avatar.text = "" if avatar.icon != null else "@"

func _show_character() -> void:
	_clear_overlay("Character")
	var tabs := HBoxContainer.new()
	overlay_box.add_child(tabs)
	_button("Character", _show_character, tabs)
	_button("Inventory", _open_inventory, tabs)
	var label := Label.new()
	label.text = character_snapshot + "\n\n" + _format_status()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var content := _scroll_list()
	content.add_child(label)
	for item: Dictionary in equipment:
		var gear := Label.new()
		gear.text = "Equipped · " + String(item.text)
		gear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(gear)
	_button("Back", _close_character, overlay_box)

func _open_inventory() -> void:
	if not active_prompt.is_empty() and int(active_prompt.v[0]) == 4 and int(menu_context.get(active_prompt.v[2], {"v": [0, 0]}).v[1]) == 1:
		_show_menu()
	else:
		_send_key(105)

func _close_character() -> void:
	if not active_prompt.is_empty() and int(active_prompt.v[0]) == 4 and int(menu_context.get(active_prompt.v[2], {"v": [0, 0]}).v[1]) == 1:
		_reply({"type": 4, "key": 27})
	else:
		_return_to_game()

func _format_status() -> String:
	var summary := "%s\nHP %s/%s  ·  Pw %s/%s  ·  AC %s  ·  XL %s  ·  Gold %s  ·  %s" % [_stat(0), _stat(18), _stat(19), _stat(11), _stat(12), _stat(14), _stat(13), _stat(10), _stat(20)]
	summary += "\nSt %s  Dx %s  Co %s  In %s  Wi %s  Ch %s  ·  %s" % [_stat(1), _stat(2), _stat(3), _stat(4), _stat(5), _stat(6), _stat(7)]
	var conditions: Array[String] = []
	for index in [9, 17, 22]:
		var text := _stat(index, "")
		if not text.is_empty():
			conditions.append(text)
	if not conditions.is_empty():
		summary += "\n" + " · ".join(conditions)
	return summary

func _handle_event(e: Dictionary) -> void:
	var v: PackedInt64Array = e.v
	match int(e.type):
		1:
			if quiet_resume and (String(e.text).begins_with("Restoring save file") or String(e.text).ends_with("welcome back to NetHack!")):
				return
			if not windows.has(v[0]):
				windows[v[0]] = []
			windows[v[0]].append(String(e.text))
			if int(v[2]) in [0, 1]:
				history.append(String(e.text))
				if history.size() > 500:
					history.pop_front()
				message.show_entries(history.slice(maxi(0, history.size() - 100)))
		2:
			windows[v[0]] = []
			window_types[v[0]] = v[1]
		3:
			windows[v[0]] = []
			if int(window_types.get(v[0], 0)) == 3:
				map.clear_map()
		4:
			windows.erase(v[0])
			window_types.erase(v[0])
			menus.erase(v[0])
			titles.erase(v[0])
		5:
			map.update_cell(v)
		6:
			if int(v[3]) == 1:
				map.set_player(Vector2i(v[0], v[1]))
			else:
				map.cursor = Vector2i(v[0], v[1])
				map.queue_redraw()
		7:
			menus[v[0]] = []
			menu_context.erase(v[0])
			item_metadata[v[0]] = {}
		8:
			menus[v[0]].append(e)
		9:
			titles[v[0]] = e.text
		10:
			status_fields[v[0]] = e.text
			dirty_ui = true
		11:
			commands.append(e)
		12:
			active_prompt = e
			if session_phase == 3:
				_capture_postmortem(e)
			if int(v[0]) == 0:
				quiet_resume = false
			_show_prompt()
		13:
			active_prompt.clear()
			if report_visible and not end_report.is_empty():
				end_report.complete = true
				EndReport.write_report(end_report)
				_show_end_report(int(end_report.get("last_page", 0)))
				return
			if auto_resume:
				if background_resume and int(v[1]) == 1:
					resume_ready = true
					_resume_if_ready()
					return
				background_resume = false
				message.text = "Game saved. Resume when ready." if int(v[1]) == 1 else "Session stopped. If saving failed, recovery files have been preserved."
				_clear_overlay("Game safely suspended" if int(v[1]) == 1 else "Session stopped — check messages")
				_button("Resume", func():
					auto_resume = false
					_start(current_name), overlay_box)
				_button("Characters", _show_home, overlay_box)
			else:
				_clear_overlay("Session ended" if int(v[0]) == 0 else "Session stopped — see messages")
				var log := _scroll_list()
				var label := Label.new()
				label.text = "\n".join(history.slice(maxi(0, history.size() - 30)))
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				log.add_child(label)
				_button("Characters", _show_home, overlay_box)
		16:
			if menus.has(v[0]) and int(v[1]) < menus[v[0]].size():
				menus[v[0]][v[1]].tile = v[2]
		17:
			character_snapshot = String(e.text)
		18:
			if int(v[0]) == -1:
				equipment.clear()
			else:
				equipment.append(e)
		19:
			item_metadata[v[0]][v[1]] = e
		21:
			if not end_report.is_empty():
				end_report.outcome = int(v[0])
				end_report.cause = String(e.text)
				EndReport.write_report(end_report)
		20:
			menu_context[v[0]] = e
		15:
			session_phase = int(v[0])
			if session_phase == 3:
				auto_resume = false
				background_resume = false
				resume_ready = false
				report_visible = true
				end_report = {"version": 1, "name": current_name, "outcome": int(v[1]), "cause": String(e.text), "pages": [], "last_page": 0, "dismissed": false, "complete": false}
				EndReport.write_report(end_report)
		14:
			current_turn = int(v[2])
			map.set_player(Vector2i(v[0], v[1]))
			dirty_ui = true

func _capture_postmortem(prompt: Dictionary) -> void:
	var w := int(prompt.v[2])
	var lines: Array = windows.get(w, []).duplicate()
	if int(prompt.v[0]) == 4:
		for entry: Dictionary in menus.get(w, []):
			lines.append(String(entry.text))
	var title := String(titles.get(w, prompt.text))
	end_report.pages.append({"title": title, "text": "\n".join(lines), "question": String(prompt.text), "scroll": 0})
	end_report.last_page = end_report.pages.size() - 1
	EndReport.write_report(end_report)

func _show_end_report(index := 0) -> void:
	if end_report.is_empty():
		_show_home()
		return
	report_visible = true
	_clear_overlay("Last run · " + String(end_report.get("name", "")))
	var content := _scroll_list()
	report_scroll = content.get_parent()
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pages: Array = end_report.pages
	report_page = clampi(index, 0, maxi(0, pages.size() - 1))
	text.text = String(end_report.cause)
	if not pages.is_empty():
		var p: Dictionary = pages[report_page]
		text.text += "\n\n" + String(p.title) + "\n" + String(p.text)
	content.add_child(text)
	end_report.last_page = report_page
	EndReport.write_report(end_report)
	var nav := HBoxContainer.new()
	overlay_box.add_child(nav)
	if report_page > 0:
		_button("Previous", func(): _show_end_report(report_page - 1), nav)
	if report_page + 1 < pages.size():
		_button("Next", func(): _show_end_report(report_page + 1), nav)
	_button("Characters", _leave_report, overlay_box)
	if not pages.is_empty():
		report_scroll.set_deferred("scroll_vertical", int(pages[report_page].get("scroll", 0)))
		report_scroll.get_v_scroll_bar().value_changed.connect(func(value):
			end_report.pages[report_page].scroll = int(value)
			EndReport.write_report(end_report))

func _leave_report() -> void:
	if session != null and session.is_running():
		session.stop()
		session.poll() # Discard the terminated postmortem worker's final event.
	active_prompt.clear()
	report_visible = false
	end_report.dismissed = true
	EndReport.write_report(end_report)
	_show_home()

func _reply(input: Dictionary) -> void:
	if active_prompt.is_empty():
		return
	input.request = active_prompt.request
	if session.respond(input):
		_dismiss_keyboard()
		active_prompt = {}
		overlay.hide()

func _send_key(key: int) -> void:
	if key == 27 and session != null:
		session.interrupt()
	_reply({"type": 1, "key": key})

func _tile_pressed(cell: Vector2i) -> void:
	if overlay.visible:
		return
	if active_prompt.is_empty() or int(active_prompt.v[0]) not in [0, 6]:
		return
	_reply({"type": 2, "x": cell.x, "y": cell.y})

func _show_prompt() -> void:
	var kind := int(active_prompt.v[0])
	hint.text = String(active_prompt.text)
	match kind:
		0:
			if return_to_inventory:
				return_to_inventory = false
				_send_key(105)
				return
			overlay.hide()
			commands.clear()
		6:
			overlay.hide()
		1:
			var w := int(active_prompt.v[2])
			if w > 0 and windows.has(w) and not windows[w].is_empty():
				_show_text("\n".join(windows[w]), true)
			else:
				_show_keyboard()
		2:
			_clear_overlay(String(active_prompt.text))
			overlay.set_meta("engine_input", true)
			var choices := HFlowContainer.new()
			_scroll_list().add_child(choices)
			var chars := String(active_prompt.extra).split(String.chr(27))[0]
			if chars.is_empty():
				chars = "yn"
			if chars.contains("#"):
				var quantity := NumberField.instantiate()
				quantity.helper_text = "0 answers No; positive values select that quantity."
				quantity.maximum = 9223372036854775807
				choices.add_child(quantity)
				_button("Use quantity", func(): _reply({"type": 3, "text": str(quantity.value)}), choices)
			for c in chars:
				if c == "#":
					continue
				var label: String = {"y": "Yes", "n": "No", "q": "Quit", "a": "All", "r": "Recover"}.get(c, c)
				_button(label, func(): _send_key(c.unicode_at(0)), choices)
			var footer := HBoxContainer.new()
			overlay_box.add_child(footer)
			_button("Keys / count", _show_keyboard, footer)
			_button("Cancel", func(): _send_key(27), footer)
		7:
			_clear_overlay(String(active_prompt.text))
			overlay.set_meta("engine_input", true)
			var quantity := NumberField.instantiate()
			quantity.helper_text = "0 answers No."
			_scroll_list().add_child(quantity)
			quantity.value = int(active_prompt.extra)
			var footer := HBoxContainer.new()
			overlay_box.add_child(footer)
			_button("Cancel", func(): _send_key(27), footer)
			_button("Submit", func(): _reply({"type": 3, "text": str(quantity.value)}), footer)
			quantity.input.grab_focus()
		3:
			_clear_overlay(String(active_prompt.text))
			overlay.set_meta("engine_input", true)
			var form := _scroll_list()
			var field := _field(form, "Your answer", "Enter text")
			var line: LineEdit = field.input
			line.max_length = 255
			line.text = String(active_prompt.extra)
			field.text_submitted.connect(func(text): _reply({"type": 3, "text": text}))
			var footer := HBoxContainer.new()
			overlay_box.add_child(footer)
			_button("Cancel", func(): _send_key(27), footer)
			_button("Submit", func(): _reply({"type": 3, "text": line.text}), footer)
			line.grab_focus()
		4:
			_show_menu()
		5:
			_show_commands()

func _show_text(text: String, blocking := false) -> void:
	_clear_overlay("NetHack")
	overlay.set_meta("engine_input", blocking)
	var list := _scroll_list()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(label)
	_button("Continue" if blocking else "Back", func():
		if blocking:
			_send_key(32)
		else:
			_return_to_game(), overlay_box)

func _show_menu() -> void:
	var w := int(active_prompt.v[2])
	menu_how = int(active_prompt.v[1])
	selected.clear()
	var context: Dictionary = menu_context.get(w, {})
	var context_kind := int(context.v[1]) if not context.is_empty() else 0
	_clear_overlay("Inventory" if context_kind == 1 else "Item details" if context_kind == 2 else String(titles.get(w, "Choose")))
	overlay.set_meta("engine_input", true)
	if context_kind == 1:
		var tabs := HBoxContainer.new()
		overlay_box.add_child(tabs)
		_button("Character", _show_character, tabs)
		_button("Inventory", _show_menu, tabs)
	search = null
	if context_kind != 2 and menus.get(w, []).size() > 8:
		search = _field(overlay_box, "Filter choices", "Search this list…").input
	menu_list = _scroll_list()
	if context_kind == 2:
		var icon := TextureRect.new()
		icon.texture = _item_icon(int(context.v[2]))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)
		menu_list.add_child(icon)
		var known := Label.new()
		known.text = String(context.text) + "\nQuantity: %d%s" % [context.v[3], " · Equipped" if context.v[4] else ""]
		known.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		menu_list.add_child(known)

	for entry: Dictionary in menus.get(w, []):
		var v: PackedInt64Array = entry.v
		var row := VBoxContainer.new()
		row.set_meta("filter", String(entry.text).to_lower())
		menu_list.add_child(row)
		if int(v[3]) == 0 or menu_how == 0:
			var label := Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			label.text = entry.text
		elif menu_how == 1:
			var count_field: VBoxContainer = null
			if context_kind == 0 and item_metadata.get(w, {}).has(v[1]):
				count_field = NumberField.instantiate()
				row.add_child(count_field)
			var quantity_field := count_field
			var b := _button(String(entry.text), func():
				var count := int(quantity_field.value) if quantity_field != null and quantity_field.value > 0 else -1
				_reply({"type": 4, "text": "%d:%d" % [v[1], count]}), row)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var metadata: Dictionary = item_metadata.get(w, {}).get(v[1], {})
			var tile := int(metadata.v[2]) if not metadata.is_empty() else int(entry.get("tile", -1))
			b.icon = _item_icon(tile)
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 40)
			if not metadata.is_empty():
				b.text = String(metadata.text) + "\nQuantity: %d%s" % [metadata.v[3], " · Equipped" if metadata.v[4] else ""]
		else:
			var check := _toggle(row, String(entry.text), false)
			var quantity := NumberField.instantiate() as VBoxContainer
			row.add_child(quantity)
			quantity.hide()
			check.toggled.connect(func(on):
				quantity.visible = on
				if on:
					selected[v[1]] = int(quantity.value) if quantity.value > 0 else -1
				else:
					selected.erase(v[1]))
			quantity.value_changed.connect(func(value):
				if check.button_pressed:
					selected[v[1]] = int(value) if value > 0 else -1)
			if int(v[4]) & 1:
				check.button_pressed = true
	if search != null:
		search.text_changed.connect(_filter_rows)
	if menu_how != 1:
		_button("Confirm" if menu_how == 2 else "Continue", func():
			var result: Array[String] = []
			for index in selected:
				result.append("%d:%d" % [index, selected[index]])
			_reply({"type": 4, "text": ",".join(result)}), overlay_box)
	_button("Back" if context_kind else "Cancel", func():
		return_to_inventory = context_kind == 2
		_reply({"type": 4, "key": 27}), overlay_box)

func _filter_rows(text: String) -> void:
	for row in menu_list.get_children():
		row.visible = text.to_lower() in String(row.get_meta("filter", ""))

func _open_commands() -> void:
	if not active_prompt.is_empty() and int(active_prompt.v[0]) == 0:
		commands.clear()
		_send_key(35)
	elif not active_prompt.is_empty() and int(active_prompt.v[0]) == 5:
		_show_commands()

func _show_commands() -> void:
	_clear_overlay("All game commands")
	overlay.set_meta("engine_input", true)
	search = _field(overlay_box, "Find a command", "Search actions…").input
	menu_list = _scroll_list()
	for command: Dictionary in commands:
		var b := _button("%s — %s" % [command.text, command.extra], func(): _reply({"type": 5, "text": command.text}), menu_list)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.set_meta("filter", (String(command.text) + " " + String(command.extra)).to_lower())
	search.text_changed.connect(_filter_rows)
	_button("Cancel", func(): _reply({"type": 5, "key": 27}), overlay_box)

func _show_directions() -> void:
	_clear_overlay("Direction / movement")
	overlay.set_meta("engine_input", true)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_list().add_child(grid)
	var letters := ["y", "k", "u", "h", ".", "l", "b", "j", "n"]
	var labels := ["↖", "↑", "↗", "←", "Wait / self", "→", "↙", "↓", "↘"]
	for i in range(9):
		_button(labels[i], func(): _send_key(String(letters[i]).unicode_at(0)), grid)
	var vertical := HBoxContainer.new()
	overlay_box.add_child(vertical)
	_button("Up <", func(): _send_key(60), vertical)
	_button("Down >", func(): _send_key(62), vertical)
	_button("Cancel", _return_to_game, vertical)

func _show_keyboard() -> void:
	_clear_overlay(String(active_prompt.get("text", "NetHack keyboard")))
	overlay.set_meta("engine_input", true)
	var list := _scroll_list()
	var modifiers := HBoxContainer.new()
	list.add_child(modifiers)
	var ctrl := _button("Ctrl", func(): keyboard_ctrl = not keyboard_ctrl, modifiers)
	ctrl.toggle_mode = true
	ctrl.button_pressed = keyboard_ctrl
	var alt := _button("Alt", func(): keyboard_alt = not keyboard_alt, modifiers)
	alt.toggle_mode = true
	alt.button_pressed = keyboard_alt
	_button("Directions", _show_directions, modifiers)
	key_entry = _field(list, "Key", "Type a key or use the buttons below").input
	key_entry.text_changed.connect(func(text):
		if not text.is_empty():
			_keyboard_key(text.unicode_at(0)))
	for letters in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM", "<>.,:;!?@#", "$%^&*()-_=+", "[]{}\\|/\"'`~"]:
		var row := HFlowContainer.new()
		list.add_child(row)
		for c in letters:
			var b := _button(c, func(): _keyboard_key(c.unicode_at(0)), row, true)
			b.custom_minimum_size.x = _touch_size()
	var controls := HBoxContainer.new()
	list.add_child(controls)
	_button("Esc", func(): _send_key(27), controls)
	_button("Space", func(): _send_key(32), controls)
	_button("Enter", func(): _send_key(13), controls)
	_button("Back", _return_to_game, overlay_box)

func _keyboard_key(key: int) -> void:
	if keyboard_ctrl:
		key = key & 31
	if keyboard_alt:
		key = key | 128
	keyboard_ctrl = false
	keyboard_alt = false
	_send_key(key)

func _return_to_game() -> void:
	_dismiss_keyboard()
	if not active_prompt.is_empty():
		_show_prompt()
	elif session != null and session.is_running():
		overlay.hide()
	else:
		_show_home()

func _dismiss_keyboard() -> void:
	get_viewport().gui_release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()

func _toggle_mode() -> void:
	map.tiled = not map.tiled
	map.queue_redraw()
	(header.get_node("Mode") as Button).text = "Tiles" if map.tiled else "ASCII"
	settings.set_value("ui", "tiles", map.tiled)
	settings.save("user://settings.cfg")

func _show_settings() -> void:
	_clear_overlay("Settings")
	var options := _scroll_list()
	var tiles := _toggle(options, "Use tiles", map.tiled, "Turn off for classic ASCII characters.")
	tiles.toggled.connect(func(_on): _toggle_mode())
	var text_size := NumberField.instantiate() as VBoxContainer
	text_size.label_text = "Text size"
	text_size.helper_text = "100% is the default. Touch targets scale with the text."
	text_size.minimum = 90
	text_size.maximum = 150
	text_size.step = 10
	text_size.suffix = "%"
	options.add_child(text_size)
	text_size.value = roundi(ui_scale * 100)
	text_size.value_changed.connect(func(value): _change_scale(value / 100.0 - ui_scale))
	_button("Message history", func(): _show_text("\n".join(history)), options)
	_button("Customize action bar", _customize_actions, options)
	_button("Help, credits & licenses", _show_about, options)
	_button("Third-party license texts", _show_licenses, options)
	if session != null and session.is_running():
		_button("Save and suspend", _suspend_game, options)
	_button("Back", _return_to_game, overlay_box)

func _change_scale(delta: float) -> void:
	ui_scale = clampf(ui_scale + delta, 0.9, 1.5)
	theme = MobileTheme.create(ui_scale)
	settings.set_value("ui", "scale", ui_scale)
	settings.save("user://settings.cfg")

func _customize_actions() -> void:
	_clear_overlay("Action bar — choose up to 6")
	var list := _scroll_list()
	for action in ACTIONS:
		var check := _toggle(list, action, action in actions)
		check.toggled.connect(func(on):
			if on and actions.size() < 6:
				actions.append(action)
			elif not on:
				actions.erase(action)
			else:
				check.set_checked(false)
			settings.set_value("ui", "actions", actions)
			settings.save("user://settings.cfg")
			_refresh_actions())
	_button("Done", _show_settings, overlay_box)

func _show_about() -> void:
	_show_text("NetHack Mobile 0.1.0 · NetHack %s\n\nUnofficial Android port. Free, offline, and open source.\n\nTap a known destination to use NetHack travel. Adjacent taps use the game's movement and interactions. Stop cancels travel. Drag to pan, pinch to zoom, Center to follow your character.\n\nUse Commands for all game actions, Direction for precise movement or targeting, and Keys for prefixes, modifiers and unusual inputs. A quantity of 0 in item menus means the whole stack.\n\nGames save automatically at safe input boundaries for crash recovery. Use Save and suspend before leaving. Death follows standard NetHack rules.\n\nSource and release archives:\n%s\n\nGodot and godot-cpp: MIT. Lua: MIT. Upstream tiles retain their notices.\n\n%s\n\n%s" % [engine_version, SOURCE_URL, FileAccess.get_file_as_string("res://data/NOTICE"), FileAccess.get_file_as_string("res://data/NETHACK_LICENSE")])
	_button("Open source releases", func(): OS.shell_open(SOURCE_URL + "/releases"), overlay_box)

func _show_licenses() -> void:
	var texts: Array[String] = [Engine.get_license_text(), FileAccess.get_file_as_string("res://data/GODOT_LICENSE"), FileAccess.get_file_as_string("res://data/LUA_LICENSE"), FileAccess.get_file_as_string("res://data/ANDROID_CPP_LICENSES")]
	for component: Dictionary in Engine.get_copyright_info():
		texts.append(JSON.stringify(component, "  "))
	var licenses := Engine.get_license_info()
	for name in licenses:
		texts.append(String(name) + "\n" + String(licenses[name]))
	_show_text("\n\n".join(texts))

func _resume_if_ready() -> void:
	if resume_ready and not application_paused:
		resume_ready = false
		background_resume = false
		auto_resume = false
		_start(current_name, false, true)

func _suspend_game(automatic := false) -> void:
	if session_phase == 3 or report_visible:
		return
	if session != null and session.is_running():
		if not auto_resume:
			background_resume = automatic
		auto_resume = true
		session.suspend()
		if not automatic:
			message.text = "Saving at a safe boundary…"

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		application_paused = true
		_suspend_game(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		application_paused = false
		_resume_if_ready()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if session != null:
			session.stop()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if report_visible:
			if session != null and session.is_running():
				return # Preserve the pending disclosure; its own controls answer it.
			_leave_report()
		elif overlay.visible:
			if not active_prompt.is_empty() and int(active_prompt.v[0]) == 4 and menu_context.has(active_prompt.v[2]):
				return_to_inventory = int(menu_context[active_prompt.v[2]].v[1]) == 2
				_reply({"type": 4, "key": 27})
			else:
				_return_to_game()
		else:
			_show_settings()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or active_prompt.is_empty():
		return
	if overlay.visible and not bool(overlay.get_meta("engine_input", false)):
		if event.keycode == KEY_ESCAPE:
			_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
		get_viewport().set_input_as_handled()
		return
	var key: int = event.unicode
	if event.keycode == KEY_ESCAPE:
		key = 27
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		key = 13
	elif event.keycode == KEY_BACKSPACE:
		key = 8
	elif event.keycode == KEY_UP:
		key = 107
	elif event.keycode == KEY_DOWN:
		key = 106
	elif event.keycode == KEY_LEFT:
		key = 104
	elif event.keycode == KEY_RIGHT:
		key = 108
	if event.ctrl_pressed and event.keycode >= KEY_A and event.keycode <= KEY_Z:
		key = int(event.keycode) - KEY_A + 1
	if event.alt_pressed:
		key |= 128
	if key > 0:
		_send_key(key)
		get_viewport().set_input_as_handled()
