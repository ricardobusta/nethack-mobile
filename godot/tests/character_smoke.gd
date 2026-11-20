extends SceneTree

var app: Control
var step := 0
var handled := 0
var turn := 0
var deadline: int

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	if OS.get_cmdline_user_args().has("--screenshot"):
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/hud-" + name + ".png")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	assert(not quit_on_go_back)
	app._start("Flow%d" % Time.get_unix_time_from_system(), true)
	deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if app.active_prompt.is_empty() or int(app.active_prompt.request) == handled:
			continue
		var p: Dictionary = app.active_prompt
		handled = p.request
		var kind := int(p.v[0])
		var context: Dictionary = app.menu_context.get(p.v[2], {})
		var category := int(context.v[1]) if not context.is_empty() else 0
		if kind == 0:
			if step == 0:
				turn = app.current_turn
				assert(app.character_snapshot.contains("Class:") and app.character_snapshot.contains("Race:"))
				assert(not app.equipment.is_empty())
				root.size = Vector2i(411, 914)
				await capture("portrait")
				root.size = Vector2i(914, 411)
				await capture("landscape")
				root.size = Vector2i(411, 914)
				app._show_character()
				var stray_key := InputEventKey.new()
				stray_key.pressed = true
				stray_key.unicode = 113 # A gameplay key must not cross an information modal.
				app._unhandled_key_input(stray_key)
				app._tile_pressed(app.map.player + Vector2i(1, 0))
				assert(app.active_prompt.request == p.request and app.overlay.visible)
				await capture("character")
				app._close_character()
				assert(app.current_turn == turn)
				step = 1
				app._open_inventory()
			elif step == 3:
				assert(app.current_turn == turn)
				app._suspend_game()
				await create_timer(0.5).timeout
				app.session.stop()
				print("Character snapshots, equipment, item metadata, engine actions, nested Back and zero-turn browsing passed.")
				quit()
				return
		elif kind == 4:
			if category == 1:
				assert(not app.item_metadata[p.v[2]].is_empty())
				await capture("inventory")
				if step == 2:
					step = 3
					app._notification(Control.NOTIFICATION_WM_GO_BACK_REQUEST)
				else:
					for entry: Dictionary in app.menus[p.v[2]]:
						if app.item_metadata[p.v[2]].has(entry.v[1]):
							var metadata: Dictionary = app.item_metadata[p.v[2]][entry.v[1]]
							assert(metadata.text == entry.text)
							# Render exactly the engine's known name; the native
							# worker fixture checks explicitly unidentified objects.
							assert(metadata.v[5] == 0 and metadata.v[6] == 0 and metadata.v[7] == 0)
							assert(metadata.v[2] >= 0 and metadata.v[3] > 0)
							assert(app._item_icon(int(metadata.v[2])) != null)
							app._reply({"type": 4, "text": "%d:-1" % entry.v[1]})
							break
			elif category == 2:
				assert(not context.text.is_empty() and app.menus[p.v[2]].size() > 1)
				await capture("item-details")
				step = 2
				app._notification(Control.NOTIFICATION_WM_GO_BACK_REQUEST)
			else:
				var chosen := ""
				for entry: Dictionary in app.menus.get(p.v[2], []):
					if entry.v[3] and (chosen.is_empty() or "No, just start play" in entry.text):
						chosen = "%d:-1" % entry.v[1]
				app._reply({"type": 4, "text": chosen})
		elif kind == 1:
			app._send_key(32)
		elif kind == 2:
			app._send_key(int(p.v[1]) if p.v[1] else 110)
		elif kind == 3:
			app._reply({"type": 3, "text": "FlowTest"})
		else:
			app._send_key(27)
	push_error("Character flow timed out at step %d: %s" % [step, app.active_prompt])
	app.session.stop()
	quit(1)
