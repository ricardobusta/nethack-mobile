extends SceneTree

var app: Control
var deadline: int
var handled: int = 0
var boundaries := 0
var completed := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	if not app.has_method("_start"):
		push_error("Main UI script could not load")
		quit(1)
		return
	root.add_child(app)
	await process_frame
	if not verify_asset_refresh():
		return
	app._start("UITest", true)
	print("UI test started")
	deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if app.active_prompt.is_empty():
			if not app.session.is_running():
				fail("Engine stopped: " + "\n".join(app.history))
				return
			continue
		var prompt: Dictionary = app.active_prompt
		if int(prompt.request) == handled:
			continue
		handled = int(prompt.request)
		var kind := int(prompt.v[0])
		print("UI prompt ", handled, " kind ", kind, " ", prompt.text)
		match kind:
			0:
				boundaries += 1
				if boundaries == 1:
					if app.map.cells.size() < 20:
						fail("No map cells received")
						return
					var tiles: Dictionary = {}
					for cell: Dictionary in app.map.cells.values():
						tiles[cell.tile] = true
					if tiles.size() < 5:
						fail("Tile mapping collapsed to fewer than five tiles")
						return
					app._toggle_mode()
					app._toggle_mode()
					var original_size := root.size
					root.size = Vector2i(960, 540)
					await process_frame
					await process_frame
					if app.body.vertical or app.map.size.y < 200:
						fail("Landscape did not reflow into a usable map layout")
						return
					var original_scale: float = app.ui_scale
					app._change_scale(1.0)
					app._show_settings()
					await process_frame
					await process_frame
					var back: Control = app.overlay_box.get_child(app.overlay_box.get_child_count() - 1)
					if back.get_global_rect().end.y > app.overlay.get_global_rect().end.y + 1:
						fail("Large-text landscape settings pushed Back off screen")
						return
					app._change_scale(original_scale - app.ui_scale)
					app._return_to_game()
					if OS.get_cmdline_user_args().has("--screenshot"):
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png("res://../build/ui-landscape.png")
					root.size = original_size
					await process_frame
					app._show_directions()
					app._return_to_game()
					if not await verify_automatic_resume():
						return
					app._send_key(105)
				elif boundaries == 2:
					app._open_commands()
				else:
					if OS.get_cmdline_user_args().has("--screenshot"):
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png("res://../build/ui-portrait.png")
					app._suspend_game()
					await create_timer(0.5).timeout
					app.session.stop()
					print("Godot UI smoke passed: character setup, inventory, command browser, ASCII/tiles, suspend.")
					quit(0)
					return
			1:
				app._send_key(32)
			2:
				var key := int(prompt.v[1])
				if "Recover" in String(prompt.text):
					key = 114
				app._send_key(key if key > 0 else 110)
			3:
				app._reply({"type": 3, "text": "UITest"})
			4:
				var chosen := ""
				if int(prompt.v[1]) != 0:
					for entry: Dictionary in app.menus.get(prompt.v[2], []):
						if int(entry.v[3]) != 0:
							chosen = "%d:-1" % int(entry.v[1])
							break
				app._reply({"type": 4, "text": chosen})
			5:
				if app.commands.size() < 50:
					fail("Command browser incomplete")
					return
				app._reply({"type": 5, "text": "search"})
			6:
				app._send_key(27)
	fail("UI test timed out")

func fail(reason: String) -> void:
	push_error(reason)
	app.session.stop()
	quit(1)

func verify_automatic_resume() -> bool:
	var position: Vector2i = app.map.player
	for foreground_early in [false, true]:
		app._notification(Control.NOTIFICATION_APPLICATION_PAUSED)
		if foreground_early:
			app._notification(Control.NOTIFICATION_APPLICATION_RESUMED)
		var timeout := Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < timeout:
			await process_frame
			if not foreground_early and app.resume_ready:
				if app.session.is_running():
					fail("Background save restarted before returning to the app")
					return false
				app._notification(Control.NOTIFICATION_APPLICATION_RESUMED)
				foreground_early = true
			if not app.auto_resume and not app.active_prompt.is_empty() and int(app.active_prompt.v[0]) == 0:
				break
		if app.auto_resume or app.active_prompt.is_empty() or app.overlay.visible or app.map.player != position or app.map.cells.size() < 20:
			fail("Automatic resume did not return directly to the restored game")
			return false
	print("Background resume passed both save/foreground orderings without a confirmation screen.")
	return true

func verify_asset_refresh() -> bool:
	var name := "AssetCheck" + str(Time.get_ticks_usec())
	var directory: String = app._prepare_game(name)
	if directory.is_empty():
		fail("Initial asset installation failed")
		return false
	var sentinel := directory.path_join("save/keep-state")
	var saved := FileAccess.open(sentinel, FileAccess.WRITE)
	saved.store_string("saved game must survive an asset refresh")
	saved.close()
	var old_data := FileAccess.open(directory.path_join("nhdat"), FileAccess.WRITE)
	old_data.store_string("old bundled data")
	old_data.close()
	var old_marker := FileAccess.open(directory.path_join(".assets_revision"), FileAccess.WRITE)
	old_marker.store_string("previous asset version")
	old_marker.close()
	if app._prepare_game(name).is_empty() or FileAccess.get_file_as_bytes(directory.path_join("nhdat")) != FileAccess.get_file_as_bytes("res://data/nhdat") or FileAccess.get_file_as_string(sentinel) != "saved game must survive an asset refresh":
		fail("Asset refresh failed or overwrote a save")
		return false
	DirAccess.remove_absolute(sentinel)
	DirAccess.remove_absolute(directory.path_join("save"))
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory.path_join(".assets_revision"))
	DirAccess.remove_absolute(directory)
	print("Bundled-data upgrade preserved saved-game files.")
	return true
