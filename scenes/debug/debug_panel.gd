class_name DebugPanel
extends PanelContainer

## Runtime tuning panel for animation feel variables.
## Toggle with F1. All changes take effect on the next animation.

var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _sliders: Dictionary = {}  # label_text -> HSlider


func _ready() -> void:
	# Panel styling
	mouse_filter = MOUSE_FILTER_STOP
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.3, 0.3, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)

	_add_header("Animation Timing")
	_add_slider("Match Highlight", 0.0, 0.5, AnimationSequencer.match_highlight_duration,
		func(v: float): AnimationSequencer.match_highlight_duration = v)
	_add_slider("Removal Duration", 0.0, 0.5, AnimationSequencer.removal_duration,
		func(v: float): AnimationSequencer.removal_duration = v)
	_add_slider("Upgrade Scale Time", 0.0, 0.5, AnimationSequencer.upgrade_scale_duration,
		func(v: float): AnimationSequencer.upgrade_scale_duration = v)
	_add_slider("Upgrade Scale Factor", 1.0, 2.0, AnimationSequencer.upgrade_scale_factor,
		func(v: float): AnimationSequencer.upgrade_scale_factor = v)
	_add_slider("Swap Duration", 0.05, 0.5, AnimationSequencer.swap_duration,
		func(v: float): AnimationSequencer.swap_duration = v)
	_add_slider("Invalid Swap Duration", 0.02, 0.4, AnimationSequencer.invalid_swap_duration,
		func(v: float): AnimationSequencer.invalid_swap_duration = v)

	_add_header("Gravity & Spawns")
	_add_slider("Min Fall Duration", 0.02, 0.4, AnimationSequencer.min_fall_duration,
		func(v: float): AnimationSequencer.min_fall_duration = v)
	_add_slider("Gravity Accel", 10.0, 120.0, AnimationSequencer.gravity_accel,
		func(v: float): AnimationSequencer.gravity_accel = v)

	_add_header("Pacing")
	_add_slider("Cascade Pause", 0.0, 0.3, AnimationSequencer.cascade_pause,
		func(v: float): AnimationSequencer.cascade_pause = v)
	_add_slider("Chain Pause", 0.0, 0.2, AnimationSequencer.chain_pause,
		func(v: float): AnimationSequencer.chain_pause = v)
	_add_slider("Removal→Gravity Overlap", 0.0, 0.3, AnimationSequencer.removal_gravity_overlap,
		func(v: float): AnimationSequencer.removal_gravity_overlap = v)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			visible = not visible
			get_viewport().set_input_as_handled()


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	_vbox.add_child(label)
	var sep := HSeparator.new()
	_vbox.add_child(sep)


func _add_slider(label_text: String, min_val: float, max_val: float,
		initial: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 200
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.01
	slider.value = initial
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 160
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "%.2f" % initial
	value_label.custom_minimum_size.x = 50
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 14)
	row.add_child(value_label)

	slider.value_changed.connect(func(val: float):
		on_change.call(val)
		value_label.text = "%.2f" % val
	)

	_vbox.add_child(row)
	_sliders[label_text] = slider
