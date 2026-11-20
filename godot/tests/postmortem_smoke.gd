extends SceneTree

const Report = preload("res://scripts/end_report.gd")
var app: Control

func _initialize() -> void:
	call_deferred("run")

func event(kind: int, values: Array, text := "", request := 0) -> Dictionary:
	values.resize(8)
	for i in range(8):
		if values[i] == null:
			values[i] = 0
	return {"type": kind, "v": PackedInt64Array(values), "text": text, "extra": "yn", "request": request}

func run() -> void:
	# This test uses a separate report path until the live UI is constructed.
	var path := "user://report-test.json"
	var report := {"version": 1, "cause": "Killed by a jackal", "pages": [{"title": "Inventory", "text": "Known items"}], "last_page": 0}
	assert(Report.write_report(report, path))
	assert(Report.read_report(path).get("cause") == report.cause)
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{partial")
	broken.close()
	assert(Report.read_report(path).is_empty())
	report.version = 100
	assert(Report.write_report(report, path))
	assert(Report.read_report(path).is_empty())
	DirAccess.remove_absolute(path)
	# Preserve the user's journal while exercising cold launch and dismissal.
	var previous := FileAccess.get_file_as_bytes(Report.PATH) if FileAccess.file_exists(Report.PATH) else PackedByteArray()
	DirAccess.remove_absolute(Report.PATH)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.current_name = "ReportTest"
	app._handle_event(event(15, [3, 0], "Killed by a jackal"))
	app._handle_event(event(2, [9, 5]))
	app._handle_event(event(1, [9, 0, 5], "You were level 3."))
	app._handle_event(event(12, [1, 0, 9], "Continue", 42))
	app._handle_event(event(21, [0], "killed by a jackal"))
	assert(app.end_report.cause == "killed by a jackal" and app.end_report.pages.size() == 1)
	var pending: Dictionary = app.active_prompt.duplicate()
	var panel: Node = app.overlay_box.get_child(2)
	app._notification(Control.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Control.NOTIFICATION_APPLICATION_RESUMED)
	assert(app.active_prompt == pending and not app.auto_resume)
	assert(app.overlay_box.get_child(2) == panel)
	app._handle_event(event(15, [4]))
	app._handle_event(event(13, [0, 0]))
	assert(app.report_visible and app.end_report.complete)
	app._notification(Control.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Control.NOTIFICATION_APPLICATION_RESUMED)
	assert(app.report_visible and not app.auto_resume)
	app.free()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	assert(app.report_visible and app.active_prompt.is_empty())
	assert(app.end_report.pages[0].text == "You were level 3.")
	app._leave_report()
	assert(not app.report_visible and app.end_report.dismissed)
	app.free()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	assert(not app.report_visible)
	app._show_end_report()
	assert(app.report_visible)
	app._leave_report()
	app.free()
	if previous.is_empty():
		DirAccess.remove_absolute(Report.PATH)
	else:
		var restore := FileAccess.open(Report.PATH, FileAccess.WRITE)
		restore.store_buffer(previous)
		restore.close()
	print("Postmortem journal, background preservation, cold launch, dismissal and corrupt recovery passed.")
	quit()
