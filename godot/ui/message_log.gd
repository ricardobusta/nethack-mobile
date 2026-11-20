extends RichTextLabel
## One scroll owner, with text measured before following the final wrapped line.
const LATEST := Color("ffffff")
const PREVIOUS := Color("8693a4")
var scroll_host: ScrollContainer
var follow_frames := 0
var entry_colors: Array[Color] = []

func _ready() -> void:
	set_process(false)
	fit_content = true
	scroll_active = false
	bbcode_enabled = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_queue_follow)
	visibility_changed.connect(_queue_follow)
	theme_changed.connect(_queue_follow)

func show_entries(entries: Array[String]) -> void:
	clear()
	entry_colors.clear()
	for i in range(entries.size()):
		var color := LATEST if i == entries.size() - 1 else PREVIOUS
		entry_colors.append(color)
		push_color(color)
		if i > 0:
			add_text("\n")
		add_text(entries[i]) # Engine strings are plain text, never parsed as markup.
		pop()
	_queue_follow()

func _queue_follow() -> void:
	if not is_inside_tree():
		return
	follow_frames = 2
	set_process(true)

func _process(_delta: float) -> void:
	# Wait for container sorting and wrapping without a coroutine that can
	# outlive this control when a screen is disposed or the app exits.
	if follow_frames > 0:
		follow_frames -= 1
		return
	if is_instance_valid(scroll_host):
		scroll_host.scroll_vertical = ceili(scroll_host.get_v_scroll_bar().max_value)
	set_process(false)
