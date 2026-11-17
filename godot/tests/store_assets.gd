extends SceneTree

class FeatureGraphic extends Node2D:
	var icon: Texture2D
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1024, 500), Color("0b1220"))
		for x in range(0, 1024, 32):
			draw_line(Vector2(x, 0), Vector2(x, 500), Color("101d2d"), 1)
		for y in range(0, 500, 32):
			draw_line(Vector2(0, y), Vector2(1024, y), Color("101d2d"), 1)
		draw_texture_rect(icon, Rect2(64, 122, 256, 256), false)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(360, 222), "NetHack", HORIZONTAL_ALIGNMENT_LEFT, -1, 88, Color("e7c66b"))
		draw_string(font, Vector2(365, 300), "Mobile", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color("eef2f8"))
		draw_string(font, Vector2(367, 356), "ASCII + tiles. Full touch control.", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("a7b8cf"))

func _initialize() -> void:
	call_deferred("generate")

func generate() -> void:
	var output := ProjectSettings.globalize_path("res://../dist/store")
	DirAccess.make_dir_recursive_absolute(output)
	var image := Image.new()
	# Play applies its own corner mask to the listing icon.
	var icon_svg := FileAccess.get_file_as_string("res://icon.svg").replace('rx="104"', '')
	if image.load_svg_from_string(icon_svg) != OK:
		push_error("Could not rasterize the original vector icon")
		quit(1)
		return
	image.save_png(output.path_join("app-icon-512.png"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 500)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var graphic := FeatureGraphic.new()
	graphic.icon = ImageTexture.create_from_image(image)
	viewport.add_child(graphic)
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	rendered.convert(Image.FORMAT_RGB8)
	if rendered.save_png(output.path_join("feature-graphic-1024x500.png")) != OK:
		push_error("Could not export the feature graphic")
		quit(1)
		return
	print("Generated original icon and feature graphic in dist/store")
	quit(0)
