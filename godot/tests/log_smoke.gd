extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	for scale in [1.0, 1.5]:
		app._change_scale(scale - app.ui_scale)
		for dimensions in [Vector2i(320, 640), Vector2i(411, 914), Vector2i(914, 411), Vector2i(1200, 800)]:
			root.size = dimensions
			app.overlay.hide()
			var entries: Array[String] = ["An earlier message.", "Another earlier message.", "Latest [b]plain text[/b] message with enough words to wrap over several lines on a phone or a narrow landscape log panel. The final wrapped line must remain visible after text layout."]
			app.message.show_entries(entries)
			for i in range(8):
				await process_frame
			assert(app.message.entry_colors == [app.message.PREVIOUS, app.message.PREVIOUS, app.message.LATEST])
			assert(app.message.get_parsed_text().contains("[b]plain text[/b]"))
			assert(app.message.get_line_count() > entries.size())
			var bar: VScrollBar = app.info_scroll.get_v_scroll_bar()
			assert(bar.value + bar.page >= bar.max_value - 1)
			# Adding a message while scrolled up must follow its fully wrapped end.
			app.info_scroll.scroll_vertical = 0
			entries.append("A newly received message that also wraps across several lines. Its final words should be visible at the bottom.")
			app.message.show_entries(entries)
			for i in range(8):
				await process_frame
			assert(bar.value + bar.page >= bar.max_value - 1)
			assert(app.message.entry_colors[-2] == app.message.PREVIOUS and app.message.entry_colors[-1] == app.message.LATEST)
	app._change_scale(1.0 - app.ui_scale)
	print("Message log passed: latest white, older gray, literal text and wrapped-line follow at phone/tablet sizes and enlarged text.")
	quit()
