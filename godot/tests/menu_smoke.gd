extends SceneTree

class InputRecorder extends RefCounted:
	var result: Dictionary = {}
	func respond(input: Dictionary) -> bool:
		result = input.duplicate()
		return true
	func poll() -> Array:
		return []
	func is_running() -> bool:
		return false
	func interrupt() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	var engine: RefCounted = app.session
	var recorder := InputRecorder.new()
	app.session = recorder
	app.menus[42] = []
	for i in range(3):
		app.menus[42].append({"text": "Stack %d" % i, "v": PackedInt64Array([42, i, 0, 1, 1 if i == 0 else 0, 0, 0, 0])})
	app.active_prompt = {"request": 101, "v": PackedInt64Array([4, 2, 42])}
	app._show_menu()
	assert(app.selected[0] == -1)
	app.menu_list.get_child(0).get_child(1).value = 2
	app.menu_list.get_child(1).get_child(0).button_pressed = true
	app.menu_list.get_child(1).get_child(1).value = 5
	app.menu_list.get_child(2).get_child(0).button_pressed = true
	app.menu_list.get_child(1).get_child(0).button_pressed = false
	assert(not app.selected.has(1))
	app.menu_list.get_child(1).get_child(0).button_pressed = true
	for control in app.overlay_box.get_children():
		if control is Button and control.text == "Confirm":
			control.pressed.emit()
	var counts := {}
	for pair: String in String(recorder.result.text).split(","):
		var values := pair.split(":")
		counts[int(values[0])] = int(values[1])
	assert(recorder.result.request == 101 and recorder.result.type == 4)
	assert(counts == {0: 2, 1: 5, 2: -1})
	# A command-specific PICK_ONE item preserves the selected stack count.
	app.item_metadata[42] = {0: {"text": "Stack 0", "v": PackedInt64Array([42, 0, 0, 7, 0, 0, 0, 0])}}
	app.active_prompt = {"request": 102, "v": PackedInt64Array([4, 1, 42])}
	app._show_menu()
	var row: Control = app.menu_list.get_child(0)
	row.get_child(0).value = 3
	row.get_child(1).pressed.emit()
	assert(recorder.result.request == 102 and recorder.result.text == "0:3")
	# Numeric yes/no answers use complete text, including PC zero-as-No.
	for count in [0, 23]:
		app.active_prompt = {"request": 103, "text": "How many?", "extra": "yn#", "v": PackedInt64Array([2, 110, 0])}
		app._show_prompt()
		var flow: Control = app.overlay_box.get_child(2).get_child(0).get_child(0)
		flow.get_child(0).value = count
		flow.get_child(1).pressed.emit()
		assert(recorder.result.request == 103 and recorder.result.type == 3 and recorder.result.text == str(count))
	app.session = engine
	print("Menu regression passed: multiselect, preselection, retained quantities, whole stacks and PC numeric answers.")
	quit()
