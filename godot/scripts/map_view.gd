extends Control

signal tile_pressed(cell: Vector2i)
const UNKNOWN_LEVEL := Vector2i(-1, -1)
const COLORS := [Color("18202c"), Color("d65b66"), Color("70b987"), Color("b88d58"), Color("719ad6"), Color("bb82d6"), Color("6bbfcb"), Color("c5cbd4"), Color("788494"), Color("ff8590"), Color("9fdb9e"), Color("ffe08c"), Color("a2c2ff"), Color("e4afff"), Color("a2e8ee"), Color("ffffff")]
var cells: Dictionary = {}
var player := Vector2i(40, 10)
var cursor := Vector2i(-1, -1)
var camera := Vector2(40, 10)
var cell_size := 32.0
var tiled := true
var atlas: Texture2D
var pointers: Dictionary = {}
var drag_start := Vector2.ZERO
var last_position := Vector2.ZERO
var dragged := false
var pinch_distance := 0.0
var follow_player := true
var current_level := UNKNOWN_LEVEL
var center_on_next_position := true

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://data/tiles.png"):
		atlas = load("res://data/tiles.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func clear_map() -> void:
	cells.clear()
	cursor = Vector2i(-1, -1)
	queue_redraw()

func reset_session() -> void:
	current_level = UNKNOWN_LEVEL
	center_on_next_position = true
	clear_map()

func update_cell(v: PackedInt64Array) -> void:
	cells[Vector2i(v[0], v[1])] = {"char": v[2], "color": v[3], "tile": v[4], "flags": v[5]}
	queue_redraw()

func set_player(position: Vector2i, level := UNKNOWN_LEVEL) -> void:
	if position.x < 1 or position.x >= 80 or position.y < 0 or position.y >= 21:
		return
	var moved := player != position
	var changed_level := level != UNKNOWN_LEVEL and level != current_level
	if level != UNKNOWN_LEVEL:
		current_level = level
	player = position
	if center_on_next_position or changed_level or (follow_player and moved):
		recenter()
	center_on_next_position = false
	queue_redraw()

func recenter() -> void:
	camera = Vector2(player) + Vector2(0.5, 0.5)
	queue_redraw()

func set_follow_player(enabled: bool) -> void:
	follow_player = enabled
	if enabled:
		recenter()

func zoom(factor: float) -> void:
	cell_size = clampf(cell_size * factor, 16.0, 80.0)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("080d15"))
	var origin := size / 2.0 - camera * cell_size
	var font := ThemeDB.fallback_font
	for cell: Vector2i in cells:
		var p: Vector2 = origin + Vector2(cell) * cell_size
		if p.x < -cell_size or p.y < -cell_size or p.x > size.x or p.y > size.y:
			continue
		var data: Dictionary = cells[cell]
		if tiled and atlas != null and int(data.tile) >= 0:
			var index := int(data.tile)
			draw_texture_rect_region(atlas, Rect2(p, Vector2.ONE * cell_size), Rect2(Vector2(index % 40, index / 40) * 16.0, Vector2(16, 16)))
		else:
			var character := String.chr(int(data.char)) if int(data.char) >= 32 else " "
			var font_size := int(cell_size * 0.86)
			var width := font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, p + Vector2((cell_size - width) / 2, cell_size * 0.81), character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLORS[clampi(int(data.color), 0, 15)])
		if int(data.flags) & 16:
			draw_circle(p + Vector2(cell_size - 4, 4), 3, Color("70dba1"))
	var hero := origin + Vector2(player) * cell_size
	draw_rect(Rect2(hero, Vector2.ONE * cell_size), Color("e7c66b"), false, 2.0)
	if cursor.x > 0:
		draw_rect(Rect2(origin + Vector2(cursor) * cell_size, Vector2.ONE * cell_size), Color("a1d9ff"), false, 2.0)

func _tap(position: Vector2) -> void:
	var cell := Vector2i(((position - size / 2.0) / cell_size + camera).floor())
	if cell.x < 1 or cell.x >= 80 or cell.y < 0 or cell.y >= 21 or not cells.has(cell):
		return
	if int(cells[cell].flags) & 2048:
		return
	tile_pressed.emit(cell)

func _gui_input(event: InputEvent) -> void:
	# Controls use emulated mouse clicks; this map handles native multi-touch.
	if event is InputEventMouse and event.device == -1:
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			pointers[event.index] = event.position
			drag_start = event.position
			last_position = event.position
			if pointers.size() == 1:
				dragged = false
			else:
				dragged = true
				var points := pointers.values()
				pinch_distance = points[0].distance_to(points[1])
		else:
			if pointers.size() == 1 and not dragged:
				_tap(event.position)
			pointers.erase(event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		pointers[event.index] = event.position
		if pointers.size() > 1:
			var points := pointers.values()
			var distance: float = points[0].distance_to(points[1])
			if pinch_distance > 0:
				zoom(distance / pinch_distance)
			pinch_distance = distance
		elif event.position.distance_to(drag_start) > 12 or dragged:
			dragged = true
			camera -= event.relative / cell_size
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom(1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_start = event.position
				dragged = false
			else:
				if not dragged:
					_tap(event.position)
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if event.position.distance_to(drag_start) > 12 or dragged:
			dragged = true
			camera -= event.relative / cell_size
			queue_redraw()
		accept_event()
