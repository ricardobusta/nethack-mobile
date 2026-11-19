extends SceneTree

const MobileScroll = preload("res://scripts/mobile_scroll.gd")
var activated := 0

func _initialize() -> void:
	call_deferred("run")

func touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)

func swipe(start: Vector2, distance: float, axis := Vector2.DOWN) -> void:
	touch(start, true)
	await process_frame
	for i in range(1, 9):
		var event := InputEventScreenDrag.new()
		event.position = start + axis * distance * i / 8.0
		event.relative = axis * distance / 8.0
		root.push_input(event, true)
		await process_frame
	touch(start + axis * distance, false)
	await process_frame

func run() -> void:
	root.size = Vector2i(400, 640)
	var scroll := MobileScroll.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(360, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var targets: Array[Control] = []
	for i in range(30):
		var row := HBoxContainer.new()
		list.add_child(row)
		var button := Button.new()
		button.text = "Item %d" % i
		button.custom_minimum_size = Vector2(200, 64)
		button.pressed.connect(func(): activated += 1)
		row.add_child(button)
		if i == 0:
			targets.append(button)
	for kind in ["toggle", "quantity", "text", "label"]:
		var control: Control
		match kind:
			"toggle":
				control = CheckButton.new()
				control.text = "Select item"
				control.toggled.connect(func(_on): activated += 1)
			"quantity":
				control = SpinBox.new()
			"text":
				control = LineEdit.new()
				control.text = "Character name"
			_:
				control = Label.new()
				control.text = "Scrollable paragraph"
		control.custom_minimum_size.y = 64
		list.add_child(control)
		targets.append(control)
	await process_frame
	await process_frame
	await swipe(Vector2(100, 250), -180)
	if scroll.scroll_vertical < 100 or activated != 0:
		push_error("Dragging over a button must scroll the list without activating it: scroll=%d taps=%d" % [scroll.scroll_vertical, activated])
		quit(1)
		return
	# Stop momentum with a new touch, then tap a visible item.
	touch(Vector2(100, 100), true)
	touch(Vector2(100, 100), false)
	await process_frame
	if activated != 0:
		push_error("Tapping to stop a fling must not activate an item")
		quit(1)
		return
	touch(Vector2(100, 100), true)
	touch(Vector2(100, 100), false)
	await process_frame
	if activated != 1:
		push_error("A stationary tap must activate exactly one item: %d" % activated)
		quit(1)
		return
	for target in targets:
		scroll.velocity = 0.0
		scroll.ensure_control_visible(target)
		await process_frame
		await process_frame
		var before := scroll.scroll_vertical
		var point := target.get_global_rect().get_center()
		await swipe(point, -120 if before == 0 else 120)
		if absi(scroll.scroll_vertical - before) < 50 or activated != 1:
			push_error("Dragging %s must move the list without activating an item: before=%d after=%d taps=%d point=%s rect=%s" % [target.get_class(), before, scroll.scroll_vertical, activated, point, scroll.get_global_rect()])
			quit(1)
			return
	scroll.velocity = 0.0
	scroll.scroll_vertical = 0
	await process_frame
	await swipe(Vector2(100, 200), -120)
	var released := scroll.scroll_vertical
	await create_timer(0.05).timeout
	if scroll.scroll_vertical <= released:
		push_error("A swipe must coast after release")
		quit(1)
		return
	await create_timer(0.5).timeout
	if scroll.scroll_vertical < 0 or scroll.scroll_vertical > scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page:
		push_error("Fling escaped the scroll bounds")
		quit(1)
		return
	scroll.velocity = 0.0
	scroll.scroll_vertical = 100
	await process_frame
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(100, 100)
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	if scroll.scroll_vertical <= 100:
		push_error("Desktop mouse-wheel scrolling regressed")
		quit(1)
		return
	scroll.hide()
	var strip := MobileScroll.new()
	strip.position = Vector2(20, 20)
	strip.size = Vector2(360, 100)
	strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(strip)
	var actions := HBoxContainer.new()
	strip.add_child(actions)
	for i in range(20):
		var button := Button.new()
		button.text = "Action %d" % i
		button.custom_minimum_size = Vector2(100, 64)
		button.pressed.connect(func(): activated += 1)
		actions.add_child(button)
	await process_frame
	await process_frame
	await swipe(Vector2(250, 60), -180, Vector2.RIGHT)
	if strip.scroll_horizontal < 100 or activated != 1:
		push_error("Horizontal action strips must swipe without triggering actions")
		quit(1)
		return
	print("Mobile scroll passed: buttons, toggles, fields, quantities, text, inertia, bounds, stop-on-touch, taps and horizontal action strips.")
	quit(0)
