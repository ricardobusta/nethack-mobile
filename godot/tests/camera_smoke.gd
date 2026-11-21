extends SceneTree

const MapView = preload("res://scripts/map_view.gd")

func _initialize() -> void:
	call_deferred("run")

func ready_event(position: Vector2i, level: Vector2i) -> Dictionary:
	return {"type": 14, "v": PackedInt64Array([position.x, position.y, 17, level.x, level.y, 1])}

func run() -> void:
	var map := MapView.new()
	root.add_child(map)
	map.size = Vector2(320, 240)
	map.set_follow_player(false)
	map.set_player(Vector2i(4, 5), Vector2i(0, 1))
	assert(map.camera == Vector2(4.5, 5.5))
	map.camera = Vector2(30, 10)
	map.set_player(Vector2i(5, 5), Vector2i(0, 1))
	assert(map.camera == Vector2(30, 10))
	map.clear_map() # A redraw is not a floor transition.
	map.set_player(Vector2i(5, 5), Vector2i(0, 1))
	assert(map.camera == Vector2(30, 10))
	map.cell_size = 48
	map.set_player(Vector2i(70, 18), Vector2i(0, 2))
	assert(map.camera == Vector2(70.5, 18.5) and not map.follow_player)
	assert(map.cell_size == 48)
	map.camera = Vector2(30, 10)
	map.set_player(Vector2i(70, 18), Vector2i(1, 2)) # Same depth in another branch.
	assert(map.camera == Vector2(70.5, 18.5))
	map.set_follow_player(true)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(100, 100)
	map._gui_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(144, 124)
	drag.relative = Vector2(44, 24)
	map._gui_input(drag)
	var panned: Vector2 = map.camera
	assert(map.follow_player and panned != Vector2(70.5, 18.5))
	touch.pressed = false
	map._gui_input(touch)
	map.set_player(Vector2i(70, 18), Vector2i(1, 2))
	assert(map.camera == panned) # Repeated input/redraw must not undo a pan.
	map.set_player(Vector2i(69, 18), Vector2i(1, 2))
	assert(map.camera == Vector2(69.5, 18.5))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(100, 100)
	map._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(140, 120)
	motion.relative = Vector2(40, 20)
	map._gui_input(motion)
	assert(map.follow_player and map.camera != Vector2(69.5, 18.5))
	map.set_follow_player(false)
	map.recenter()
	assert(not map.follow_player and map.camera == Vector2(69.5, 18.5))
	var tapped: Array[Vector2i] = []
	map.cells[map.player] = {"flags": 0}
	map.tile_pressed.connect(func(cell): tapped.append(cell))
	map._tap(map.size / 2)
	assert(tapped == [map.player]) # Center is the player tile's center, not its corner.
	map.reset_session()
	map.set_player(Vector2i(8, 9), Vector2i(0, 1))
	assert(map.camera == Vector2(8.5, 9.5) and not map.follow_player)
	map.free()

	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var previous := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	app._set_camera_follow(false)
	app._handle_event(ready_event(Vector2i(4, 5), Vector2i(0, 1)))
	app.map.camera = Vector2(30, 10)
	app._handle_event(ready_event(Vector2i(5, 5), Vector2i(0, 1)))
	assert(app.map.camera == Vector2(30, 10))
	# Cliparound may arrive before READY carries the new floor identity.
	app._handle_event({"type": 6, "v": PackedInt64Array([2, 3, 0, 1])})
	app._handle_event(ready_event(Vector2i(2, 3), Vector2i(0, 2)))
	assert(app.map.camera == Vector2(2.5, 3.5))
	assert(not app.follow_camera_button.button_pressed and app.follow_camera_button.text == "Follow: Off")
	app.active_prompt = {"request": 1234, "v": PackedInt64Array([0])}
	app.follow_camera_button.button_pressed = true
	app.follow_camera_button.pressed.emit()
	assert(app.map.follow_player and app.follow_camera_button.text == "Follow: On")
	assert(app.active_prompt.request == 1234 and app.current_turn == 17)
	app.map.camera = Vector2(30, 10)
	app._handle_event({"type": 6, "v": PackedInt64Array([20, 12, 0, 0])})
	assert(app.map.cursor == Vector2i(20, 12))
	assert(app.map.player == Vector2i(2, 3) and app.map.camera == Vector2(30, 10))
	var saved := ConfigFile.new()
	assert(saved.load("user://settings.cfg") == OK)
	assert(saved.get_value("ui", "follow_player") == true)
	app._set_camera_follow(false)
	assert(saved.load("user://settings.cfg") == OK)
	assert(saved.get_value("ui", "follow_player") == false)
	app.free()
	if had_settings:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(previous)
		file.close()
	else:
		DirAccess.remove_absolute("user://settings.cfg")
	print("Camera regression passed: floor/branch transitions, redraws, following, touch/mouse pan, one-shot center, tile targeting and saved toggle.")
	quit()
