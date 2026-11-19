extends ScrollContainer

# Own touch gestures before child widgets see them, including editable fields.
# Replay stationary taps through normal GUI dispatch; drags never activate items.
var finger := -1
var start := Vector2.ZERO
var previous := Vector2.ZERO
var dragging := false
var offset := 0.0
var velocity := 0.0
var last_motion := 0
var stopping_fling := false

func _inside(point: Vector2) -> bool:
	if not is_visible_in_tree() or not get_global_rect().has_point(point):
		return false
	var ancestor := get_parent()
	while ancestor is Control:
		if ancestor.clip_contents and not ancestor.get_global_rect().has_point(point):
			return false
		ancestor = ancestor.get_parent()
	return true

func _over_scrollbar(point: Vector2) -> bool:
	for bar in [get_v_scroll_bar(), get_h_scroll_bar()]:
		if bar.is_visible_in_tree() and bar.get_global_rect().has_point(point):
			return true
	return false

func _deadzone() -> float:
	var density := maxf(1.0, float(DisplayServer.screen_get_dpi()) / 160.0)
	var scale := maxf(0.1, get_viewport().get_screen_transform().get_scale().y)
	return maxf(8.0, 10.0 * density / scale)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == -1:
		if _inside(event.position) and not _over_scrollbar(event.position):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _inside(event.position) or _over_scrollbar(event.position):
				return
			get_viewport().set_input_as_handled()
			if finger != -1:
				return
			stopping_fling = absf(velocity) > 10.0
			_finish_drag()
			finger = event.index
			start = event.position
			previous = start
			dragging = false
			offset = scroll_vertical
			velocity = 0.0
			last_motion = Time.get_ticks_msec()
		elif event.index == finger:
			get_viewport().set_input_as_handled()
			finger = -1
			if event.canceled:
				velocity = 0.0
				_finish_drag()
			elif not dragging and not stopping_fling:
				_tap.call_deferred(start)
			elif Time.get_ticks_msec() - last_motion > 100:
				velocity = 0.0
	elif event is InputEventScreenDrag and event.index == finger:
		get_viewport().set_input_as_handled()
		if not dragging and event.position.distance_to(start) >= _deadzone():
			dragging = true
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			scroll_started.emit()
		if dragging:
			var now := Time.get_ticks_msec()
			var elapsed := maxf(0.008, (now - last_motion) / 1000.0)
			var distance: float = previous.y - event.position.y
			velocity = lerpf(velocity, distance / elapsed, 0.6)
			_move_to(offset + distance)
			last_motion = now
		previous = event.position

func _tap(point: Vector2) -> void:
	if not _inside(point):
		return
	for pressed in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = point
		mouse.global_position = point
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mouse.pressed = pressed
		get_viewport().push_input(mouse, true)

func _move_to(value: float) -> void:
	var bar := get_v_scroll_bar()
	offset = clampf(value, 0.0, maxf(0.0, bar.max_value - bar.page))
	scroll_vertical = roundi(offset)
	if not is_equal_approx(offset, value):
		velocity = 0.0

func _finish_drag() -> void:
	if dragging:
		dragging = false
		propagate_notification(Control.NOTIFICATION_SCROLL_END)
		scroll_ended.emit()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		finger = -1
		velocity = 0.0
		_finish_drag()
	elif finger == -1 and absf(velocity) > 10.0:
		_move_to(offset + velocity * delta)
		velocity *= exp(-8.0 * delta)
	elif finger == -1:
		velocity = 0.0
		_finish_drag()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED]:
		finger = -1
		velocity = 0.0
		_finish_drag()
