extends SceneTree

const Report = preload("res://scripts/end_report.gd")
var app: Control
var handled := 0
var moves := 0
var saw_death := false
var previous: PackedByteArray

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	previous = FileAccess.get_file_as_bytes(Report.PATH) if FileAccess.file_exists(Report.PATH) else PackedByteArray()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app._start("Death%d" % Time.get_unix_time_from_system(), true)
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if app.report_visible and not app.session.is_running() and app.end_report.get("complete", false):
			assert(saw_death and app.end_report.outcome < 13 and not app.end_report.pages.is_empty())
			if OS.get_cmdline_user_args().has("--screenshot"):
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../build/hud-postmortem.png")
			app.free()
			app = load("res://main.tscn").instantiate()
			root.add_child(app)
			await process_frame
			assert(app.report_visible and not app.session.is_running() and app.active_prompt.is_empty())
			app._leave_report()
			assert(not app.report_visible)
			# Reusing the same name must select a fresh run, never old checkpoints.
			var next_directory := String(app._prepare_game(app.end_report.name))
			assert(next_directory.contains("-run-"))
			app._start(app.end_report.name, true)
			saw_death = false
			moves = -100000 # Verify starting a separate living character below.
		if app.active_prompt.is_empty() or app.active_prompt.request == handled:
			continue
		var p: Dictionary = app.active_prompt
		handled = p.request
		if app.session_phase == 3:
			saw_death = true
			var shown: Node = app.overlay_box.get_child(0)
			var pending: Dictionary = app.active_prompt.duplicate()
			app._notification(Control.NOTIFICATION_APPLICATION_PAUSED)
			app._notification(Control.NOTIFICATION_APPLICATION_RESUMED)
			assert(app.active_prompt == pending and shown == app.overlay_box.get_child(0) and not app.auto_resume)
		match int(p.v[0]):
			0:
				if moves < 0:
					app._suspend_game()
					await create_timer(0.5).timeout
					app.session.stop()
					if previous.is_empty():
						DirAccess.remove_absolute(Report.PATH)
					else:
						var file := FileAccess.open(Report.PATH, FileAccess.WRITE)
						file.store_buffer(previous)
						file.close()
					print("Actual death disclosures, background preservation, final journal, cold reopen and another character passed.")
					quit()
					return
				moves += 1
				app._send_key(109 if moves % 2 else 46) # Upstream m. forces resting near monsters.
			1: app._send_key(32)
			2: app._send_key(121 if app.session_phase == 3 else int(p.v[1]) if p.v[1] else 110)
			3: app._reply({"type": 3, "text": "DeathTest"})
			4:
				var chosen := ""
				if int(p.v[1]) != 0:
					for entry: Dictionary in app.menus.get(p.v[2], []):
						if entry.v[3] and (chosen.is_empty() or "No, just start play" in entry.text):
							chosen = "%d:-1" % entry.v[1]
				app._reply({"type": 4, "text": chosen})
			_: app._send_key(27)
	push_error("Death flow timed out")
	app.session.stop()
	quit(1)
