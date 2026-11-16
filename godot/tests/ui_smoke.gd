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
	root.add_child(app)
	await process_frame
	app._start("UITest")
	deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if app.active_prompt.is_empty():
			continue
		var prompt: Dictionary = app.active_prompt
		if int(prompt.request) == handled:
			continue
		handled = int(prompt.request)
		var kind := int(prompt.v[0])
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
					app._show_directions()
					app._return_to_game()
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
