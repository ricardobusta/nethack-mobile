extends Control

const MapView = preload("res://scripts/map_view.gd")
const SOURCE_URL := "https://github.com/ricardobusta/nethack-mobile"
var engine_version := "5.0.0"
var save_namespace := "5.0.0-0-mobile1"
const ACTIONS := {"Inventory": "i", "Search": "s", "Wait": ".", "Pick up": ",", "Down": ">", "Up": "<", "Open": "o", "Kick": "\u0004", "Eat": "e", "Drink": "q", "Read": "r", "Apply": "a", "Cast": "Z", "Fire": "f", "Throw": "t", "Zap": "z", "Look": ":", "Look far": ";", "Save": "S"}
var session: RefCounted
var map: Control
var page: VBoxContainer
var header: HBoxContainer
var body: BoxContainer
var info_column: VBoxContainer
var status: Label
var message: Label
var hint: Label
var action_bar: HFlowContainer
var overlay: PanelContainer
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
var selected: Dictionary = {}
var current_name := ""
var settings := ConfigFile.new()
var actions: Array = ["Inventory", "Search", "Wait", "Pick up", "Down"]
var ui_scale := 1.0
var auto_resume := false
var keyboard_ctrl := false
var keyboard_alt := false
var key_entry: LineEdit
var menu_how := 0
var dirty_ui := false

func _ready() -> void:
	var build_info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
	if build_info is Dictionary:
		engine_version = String(build_info.get("engine_version", engine_version))
		save_namespace = String(build_info.get("save_namespace", save_namespace))
	settings.load("user://settings.cfg")
	actions = settings.get_value("ui", "actions", actions)
	ui_scale = float(settings.get_value("ui", "scale", 1.0))
	theme = Theme.new()
	theme.default_font_size = int(22 * ui_scale)
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	get_tree().auto_accept_quit = false
	if ClassDB.class_exists("NetHackSession"):
		session = ClassDB.instantiate("NetHackSession")
	_show_home()
	_layout()

func _button(text: String, callback: Callable, parent: Node, compact := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(76 if compact else 96, _touch_size())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _touch_size() -> float:
	if not OS.has_feature("mobile"):
		return 72.0 * ui_scale
	var density := maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0)
	var pixels_per_unit := float(get_window().size.y) / maxf(1.0, get_viewport_rect().size.y)
	return maxf(72.0 * ui_scale, 48.0 * density / maxf(0.1, pixels_per_unit))

func _build_ui() -> void:
	root_margin = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_margin)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	root_margin.add_child(page)
	header = HBoxContainer.new()
	page.add_child(header)
	var title := Label.new()
	title.text = "NETHACK  /  MOBILE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color("e7c66b"))
	header.add_child(title)
	_button("ASCII", _toggle_mode, header, true).name = "Mode"
	_button("☰", _show_settings, header, true)
	body = BoxContainer.new()
	body.vertical = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	page.add_child(body)
	info_column = VBoxContainer.new()
	info_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(info_column)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "NetHack %s · Offline · NGPL" % engine_version
	info_column.add_child(status)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.max_lines_visible = 3
	message.custom_minimum_size.y = 86
	info_column.add_child(message)
	map = MapView.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size.y = 160
	map.tiled = bool(settings.get_value("ui", "tiles", true))
	map.tile_pressed.connect(_tile_pressed)
	body.add_child(map)
	hint = Label.new()
	hint.text = "Tap a destination · Pinch to zoom · Drag to explore"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("99a9bf"))
	page.add_child(hint)
	action_bar = HFlowContainer.new()
	page.add_child(action_bar)
	_refresh_actions()
	var navigation := HBoxContainer.new()
	page.add_child(navigation)
	_button("Commands", _open_commands, navigation)
	_button("Direction", _show_directions, navigation)
	_button("Keys", _show_keyboard, navigation)
	_button("Stop", func(): _send_key(27), navigation, true)
	_button("Center", func(): map.recenter(), navigation, true)
	overlay = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("101925")
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	overlay.add_theme_stylebox_override("panel", panel_style)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_box = VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 12)
	overlay.add_child(overlay_box)
	overlay.visibility_changed.connect(func(): page.visible = not overlay.visible)
	overlay.hide()

func _layout() -> void:
	var viewport := get_viewport_rect().size
	var landscape := viewport.x > viewport.y
	body.vertical = not landscape
	info_column.custom_minimum_size.x = clampf(viewport.x * 0.28, 280, 400) if landscape else 0
	info_column.size_flags_horizontal = Control.SIZE_FILL if landscape else Control.SIZE_EXPAND_FILL
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var left := 12.0
	var top := 12.0
	var right := 12.0
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
	overlay.offset_left = left + 6
	overlay.offset_top = top + 6
	overlay.offset_right = -right - 6
	overlay.offset_bottom = -bottom - 6
	message.max_lines_visible = 2 if viewport.x > viewport.y else 3
	message.custom_minimum_size.y = 48 if viewport.x > viewport.y else 86

func _refresh_actions() -> void:
	for child in action_bar.get_children():
		child.queue_free()
	for action in actions:
		if ACTIONS.has(action):
			_button(action, func(): _send_key(String(ACTIONS[action]).unicode_at(0)), action_bar)

func _clear_overlay(title: String) -> void:
	for child in overlay_box.get_children():
		overlay_box.remove_child(child)
		child.queue_free()
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(28 * ui_scale))
	overlay_box.add_child(label)
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _show_home() -> void:
	_clear_overlay("NetHack Mobile")
	var intro := Label.new()
	intro.text = "The dungeon awaits.\n\nTap to travel, choose actions below, and discover every command through the command browser. Both ASCII and classic tiles are available."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_box.add_child(intro)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Character name"
	name_field.text = settings.get_value("game", "last_name", "Adventurer")
	name_field.max_length = 24
	name_field.custom_minimum_size.y = 72
	overlay_box.add_child(name_field)
	var start_button := _button("Start / resume character", func(): _start(name_field.text), overlay_box)
	start_button.disabled = session == null
	if session == null:
		intro.text += "\n\nNative engine unavailable. Run python3 scripts/build.py host before opening this project."
	_button("Help & licenses", _show_about, overlay_box)

func _prepare_game(name_text: String) -> String:
	var directory := "user://games/%s/%s" % [save_namespace, name_text]
	var error := DirAccess.make_dir_recursive_absolute(directory + "/save")
	if error != OK:
		return ""
	var file_list = JSON.parse_string(FileAccess.get_file_as_string("res://data/files.json"))
	if not file_list is Array:
		return ""
	for filename: String in file_list:
		# Game data is installed atomically; saves, bones and scores are never replaced.
		var destination := directory.path_join(filename)
		if FileAccess.file_exists(destination):
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
	return ProjectSettings.globalize_path(directory)

func _start(name_text: String, allow_new_version := false) -> void:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z][A-Za-z0-9_]{0,23}$")
	if regex.search(name_text) == null:
		_show_error("Use 1–24 letters, digits or underscores; start with a letter.")
		return
	if not allow_new_version and DirAccess.dir_exists_absolute("user://games") and not DirAccess.dir_exists_absolute("user://games/%s/%s" % [save_namespace, name_text]):
		for namespace: String in DirAccess.get_directories_at("user://games"):
			if namespace != save_namespace and DirAccess.dir_exists_absolute("user://games/%s/%s" % [namespace, name_text]):
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
	current_name = name_text
	settings.set_value("game", "last_name", current_name)
	settings.save("user://settings.cfg")
	map.clear_map()
	status_fields.clear()
	windows.clear()
	window_types.clear()
	menus.clear()
	commands.clear()
	active_prompt.clear()
	if session.start(directory, name_text):
		overlay.hide()
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
	_layout()

func _stat(index: int, fallback := "?") -> String:
	var value := String(status_fields.get(index, fallback))
	var separator := value.find(": ")
	return value.substr(separator + 2).strip_edges() if separator >= 0 else value.strip_edges()

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
			if not windows.has(v[0]):
				windows[v[0]] = []
			windows[v[0]].append(String(e.text))
			if int(v[2]) in [0, 1]:
				history.append(String(e.text))
				if history.size() > 500:
					history.pop_front()
				message.text = "\n".join(history.slice(maxi(0, history.size() - 3)))
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
			_show_prompt()
		13:
			active_prompt.clear()
			if auto_resume:
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
		14:
			map.set_player(Vector2i(v[0], v[1]))

func _reply(input: Dictionary) -> void:
	if active_prompt.is_empty():
		return
	input.request = active_prompt.request
	if session.respond(input):
		active_prompt = {}
		overlay.hide()

func _send_key(key: int) -> void:
	if key == 27 and session != null:
		session.interrupt()
	_reply({"type": 1, "key": key})

func _tile_pressed(cell: Vector2i) -> void:
	if active_prompt.is_empty() or int(active_prompt.v[0]) not in [0, 6]:
		return
	_reply({"type": 2, "x": cell.x, "y": cell.y})

func _show_prompt() -> void:
	var kind := int(active_prompt.v[0])
	hint.text = String(active_prompt.text)
	match kind:
		0:
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
			var choices := HFlowContainer.new()
			overlay_box.add_child(choices)
			var chars := String(active_prompt.extra).split(String.chr(27))[0]
			if chars.is_empty():
				chars = "yn"
			for c in chars:
				var label: String = {"y": "Yes", "n": "No", "q": "Quit", "a": "All", "r": "Recover"}.get(c, c)
				_button(label, func(): _send_key(c.unicode_at(0)), choices)
			_button("Keyboard / quantity", _show_keyboard, overlay_box)
			_button("Cancel", func(): _send_key(27), overlay_box)
		3:
			_clear_overlay(String(active_prompt.text))
			var line := LineEdit.new()
			line.custom_minimum_size.y = 72
			line.max_length = 255
			overlay_box.add_child(line)
			line.text_submitted.connect(func(text): _reply({"type": 3, "text": text}))
			_button("Submit", func(): _reply({"type": 3, "text": line.text}), overlay_box)
			_button("Cancel", func(): _send_key(27), overlay_box)
			line.grab_focus()
		4:
			_show_menu()
		5:
			_show_commands()

func _show_text(text: String, blocking := false) -> void:
	_clear_overlay("NetHack")
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
	_clear_overlay(String(titles.get(w, "Choose")))
	search = LineEdit.new()
	search.placeholder_text = "Filter items…"
	search.custom_minimum_size.y = 72
	overlay_box.add_child(search)
	menu_list = _scroll_list()
	for entry: Dictionary in menus.get(w, []):
		var v: PackedInt64Array = entry.v
		var row := HBoxContainer.new()
		row.set_meta("filter", String(entry.text).to_lower())
		menu_list.add_child(row)
		if int(v[3]) == 0 or menu_how == 0:
			var label := Label.new()
			label.text = entry.text
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
		elif menu_how == 1:
			var b := _button(String(entry.text), func(): _reply({"type": 4, "text": "%d:-1" % v[1]}), row)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			var check := CheckButton.new()
			check.text = entry.text
			check.custom_minimum_size.y = 72
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(check)
			var quantity := SpinBox.new()
			quantity.min_value = 0
			quantity.max_value = 1000000
			quantity.value = 0
			quantity.custom_minimum_size = Vector2(140, 72)
			quantity.tooltip_text = "0 means the entire stack"
			row.add_child(quantity)
			check.toggled.connect(func(on):
				if on:
					selected[v[1]] = int(quantity.value) if quantity.value > 0 else -1
				else:
					selected.erase(v[1]))
			quantity.value_changed.connect(func(value):
				if check.button_pressed:
					selected[v[1]] = int(value) if value > 0 else -1)
			if int(v[4]) & 1:
				check.button_pressed = true
	search.text_changed.connect(_filter_rows)
	if menu_how != 1:
		_button("Confirm" if menu_how == 2 else "Continue", func():
			var result: Array[String] = []
			for index in selected:
				result.append("%d:%d" % [index, selected[index]])
			_reply({"type": 4, "text": ",".join(result)}), overlay_box)
	_button("Cancel", func(): _reply({"type": 4, "key": 27}), overlay_box)

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
	search = LineEdit.new()
	search.placeholder_text = "Search commands…"
	search.custom_minimum_size.y = 72
	overlay_box.add_child(search)
	menu_list = _scroll_list()
	for command: Dictionary in commands:
		var b := _button("%s — %s" % [command.text, command.extra], func(): _reply({"type": 5, "text": command.text}), menu_list)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.set_meta("filter", (String(command.text) + " " + String(command.extra)).to_lower())
	search.text_changed.connect(_filter_rows)
	_button("Cancel", func(): _reply({"type": 5, "key": 27}), overlay_box)

func _show_directions() -> void:
	_clear_overlay("Direction / movement")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_box.add_child(grid)
	var letters := ["y", "k", "u", "h", ".", "l", "b", "j", "n"]
	var labels := ["↖", "↑", "↗", "←", "Wait / self", "→", "↙", "↓", "↘"]
	for i in range(9):
		_button(labels[i], func(): _send_key(String(letters[i]).unicode_at(0)), grid)
	var vertical := HBoxContainer.new()
	overlay_box.add_child(vertical)
	_button("Up <", func(): _send_key(60), vertical)
	_button("Down >", func(): _send_key(62), vertical)
	_button("Cancel", _return_to_game, overlay_box)

func _show_keyboard() -> void:
	_clear_overlay(String(active_prompt.get("text", "NetHack keyboard")))
	var modifiers := HBoxContainer.new()
	overlay_box.add_child(modifiers)
	var ctrl := _button("Ctrl", func(): keyboard_ctrl = not keyboard_ctrl, modifiers)
	ctrl.toggle_mode = true
	ctrl.button_pressed = keyboard_ctrl
	var alt := _button("Alt", func(): keyboard_alt = not keyboard_alt, modifiers)
	alt.toggle_mode = true
	alt.button_pressed = keyboard_alt
	_button("Directions", _show_directions, modifiers)
	key_entry = LineEdit.new()
	key_entry.placeholder_text = "Type a key (or use buttons below)"
	key_entry.custom_minimum_size.y = 72
	overlay_box.add_child(key_entry)
	key_entry.text_changed.connect(func(text):
		if not text.is_empty():
			_keyboard_key(text.unicode_at(0)))
	var list := _scroll_list()
	for letters in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM", "<>.,:;!?@#", "$%^&*()-_=+", "[]{}\\|/\"'`~"]:
		var row := HBoxContainer.new()
		list.add_child(row)
		for c in letters:
			var b := _button(c, func(): _keyboard_key(c.unicode_at(0)), row, true)
			b.custom_minimum_size.x = 0
	var controls := HBoxContainer.new()
	overlay_box.add_child(controls)
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
	if not active_prompt.is_empty():
		_show_prompt()
	elif session != null and session.is_running():
		overlay.hide()
	else:
		_show_home()

func _toggle_mode() -> void:
	map.tiled = not map.tiled
	map.queue_redraw()
	(header.get_node("Mode") as Button).text = "ASCII" if map.tiled else "Tiles"
	settings.set_value("ui", "tiles", map.tiled)
	settings.save("user://settings.cfg")

func _show_settings() -> void:
	_clear_overlay("Settings")
	_button("Switch ASCII / tiles", _toggle_mode, overlay_box)
	_button("Message history", func(): _show_text("\n".join(history)), overlay_box)
	_button("Customize action bar", _customize_actions, overlay_box)
	_button("Larger text", func(): _change_scale(0.1), overlay_box)
	_button("Smaller text", func(): _change_scale(-0.1), overlay_box)
	_button("Help, credits & licenses", _show_about, overlay_box)
	_button("Third-party license texts", _show_licenses, overlay_box)
	if session != null and session.is_running():
		_button("Save and suspend", _suspend_game, overlay_box)
	_button("Back", _return_to_game, overlay_box)

func _change_scale(delta: float) -> void:
	ui_scale = clampf(ui_scale + delta, 0.8, 1.5)
	theme.default_font_size = int(22 * ui_scale)
	settings.set_value("ui", "scale", ui_scale)
	settings.save("user://settings.cfg")

func _customize_actions() -> void:
	_clear_overlay("Action bar — choose up to 6")
	var list := _scroll_list()
	for action in ACTIONS:
		var check := CheckButton.new()
		check.text = action
		check.custom_minimum_size.y = 72
		check.button_pressed = action in actions
		list.add_child(check)
		check.toggled.connect(func(on):
			if on and actions.size() < 6:
				actions.append(action)
			elif not on:
				actions.erase(action)
			else:
				check.set_pressed_no_signal(false)
			settings.set_value("ui", "actions", actions)
			settings.save("user://settings.cfg")
			_refresh_actions())
	_button("Done", _show_settings, overlay_box)

func _show_about() -> void:
	_show_text("NetHack Mobile 0.1.0 · NetHack %s\n\nUnofficial Android port. Free, offline, and open source.\n\nTap a known destination to use NetHack travel. Adjacent taps use the game's movement and interactions. Stop cancels travel. Drag to pan, pinch to zoom, Center to follow your character.\n\nUse Commands for all game actions, Direction for precise movement or targeting, and Keys for prefixes, modifiers and unusual inputs. A quantity of 0 in item menus means the whole stack.\n\nGames save automatically at safe input boundaries for crash recovery. Use Save and suspend before leaving. Death follows standard NetHack rules.\n\nSource and release archives:\n%s\n\nGodot and godot-cpp: MIT. Lua: MIT. Upstream tiles retain their notices.\n\n%s\n\n%s" % [engine_version, SOURCE_URL, FileAccess.get_file_as_string("res://data/NOTICE"), FileAccess.get_file_as_string("res://data/LICENSE")])
	_button("Open source releases", func(): OS.shell_open(SOURCE_URL + "/releases"), overlay_box)

func _show_licenses() -> void:
	var texts: Array[String] = [Engine.get_license_text(), FileAccess.get_file_as_string("res://data/GODOT_LICENSE"), FileAccess.get_file_as_string("res://data/LUA_LICENSE")]
	for component: Dictionary in Engine.get_copyright_info():
		texts.append(JSON.stringify(component, "  "))
	var licenses := Engine.get_license_info()
	for name in licenses:
		texts.append(String(name) + "\n" + String(licenses[name]))
	_show_text("\n\n".join(texts))

func _suspend_game() -> void:
	if session != null and session.is_running():
		auto_resume = true
		session.suspend()
		message.text = "Saving at a safe boundary…"

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_suspend_game()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if session != null:
			session.stop()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if overlay.visible:
			_return_to_game()
		else:
			_show_settings()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or active_prompt.is_empty():
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
