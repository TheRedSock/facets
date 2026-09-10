extends RefCounted
## Builds the Atelier control tree in code: flat dark panels, subtle 1px
## borders, preview column left, scrollable control panel right (~360 px).
## Construction and styling only — signal wiring and state live in
## gem_atelier.gd, which receives every named control in one dictionary.

const BG := Color("#17171b")
const SURFACE := Color("#1d1d23")
const WELL := Color("#101014")
const BORDER := Color("#2a2a33")
const BTN := Color("#26262e")
const BTN_HOVER := Color("#2e2e39")
const BTN_PRESSED := Color("#1f1f26")
const TEXT := Color("#d8d8dc")
const DIM := Color("#8b8b95")

const PANEL_WIDTH := 360.0
const PREVIEW_SIZE := 512.0
const LABEL_WIDTH := 92.0


static func build(root: Control) -> Dictionary:
	var c := {}

	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_theme_stylebox_override("panel", _flat(BG))
	root.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.name = "Layout"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	root.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	margin.add_child(columns)

	_build_preview_column(columns, c)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(spacer)

	_build_control_panel(columns, c)
	return c


static func set_enabled(c: Dictionary, on: bool) -> void:
	for key in ["stones", "rigs", "clips", "reset", "export", "print_toggle"]:
		(c[key] as BaseButton).disabled = not on
	for key in ["scatter", "anisotropy", "band_period", "band_contrast",
			"yaw", "exposure", "tilt", "turn", "scrub"]:
		(c[key] as Slider).editable = on
	for key in ["seed", "size"]:
		(c[key] as SpinBox).editable = on


# ------------------------------------------------------------------ columns

static func _build_preview_column(parent: Control, c: Dictionary) -> void:
	var column := VBoxContainer.new()
	column.name = "PreviewColumn"
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _flat(WELL, BORDER))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(frame)

	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.add_child(preview)
	c["preview"] = preview

	var overlay := Label.new()
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_theme_color_override("font_color", TEXT)
	overlay.visible = false
	frame.add_child(overlay)
	c["overlay"] = overlay

	var status := Label.new()
	status.add_theme_color_override("font_color", TEXT)
	column.add_child(status)
	c["status"] = status

	var message := Label.new()
	message.custom_minimum_size = Vector2(PREVIEW_SIZE, 0)
	message.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	message.add_theme_color_override("font_color", DIM)
	column.add_child(message)
	c["message"] = message


static func _build_control_panel(parent: Control, c: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "ControlPanel"
	panel.add_theme_stylebox_override("panel", _flat(SURFACE, BORDER))
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	parent.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	scroll.add_child(pad)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	pad.add_child(box)

	_section(box, "STONE", true)
	c["stones"] = _picker_row(box, "Stone")
	c["scatter"] = _slider_row(box, "Scatter /mm", 0.0, 2.0, 0.001, 0.0, "%.3f")
	c["anisotropy"] = _slider_row(box, "Scatter g", -0.95, 0.95, 0.01, 0.6, "%.2f")
	c["band_period"] = _slider_row(box, "Bands mm", 0.05, 10.0, 0.01, 1.0, "%.2f")
	c["band_contrast"] = _slider_row(box, "Band contrast", 0.0, 1.0, 0.01, 0.0, "%.2f")
	c["seed"] = _spin_row(box, "Seed", 0, 1 << 30, 1, 1, true)
	c["size"] = _spin_row(box, "Size mm", 2.0, 8.0, 0.1, 4.0, false)
	c["reset"] = _button(box, "Reset to authored")

	_section(box, "RIG")
	c["rigs"] = _picker_row(box, "Rig")
	c["yaw"] = _slider_row(box, "Rig yaw", -180.0, 180.0, 1.0, 0.0, "%.0f")
	c["exposure"] = _slider_row(box, "Exposure", 0.25, 4.0, 0.05, 1.0, "%.2f")

	_section(box, "ORIENTATION")
	c["tilt"] = _slider_row(box, "Tilt", -45.0, 45.0, 1.0, -12.0, "%.0f")
	c["turn"] = _slider_row(box, "Turn", 0.0, 360.0, 1.0, 0.0, "%.0f")

	_section(box, "OUTPUT")
	var print_toggle := CheckButton.new()
	print_toggle.text = "House print (off = raw)"
	print_toggle.button_pressed = true
	print_toggle.add_theme_color_override("font_color", TEXT)
	box.add_child(print_toggle)
	c["print_toggle"] = print_toggle

	var clip_row := VBoxContainer.new()
	clip_row.add_theme_constant_override("separation", 6)
	box.add_child(clip_row)
	_section(clip_row, "CLIP SCRUB")
	c["clips"] = _picker_row(clip_row, "Clip")
	c["scrub"] = _slider_row(clip_row, "Time", 0.0, 1.0, 0.01, 0.0, "%.2f")
	c["clip_row"] = clip_row

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)
	c["export"] = _button(box, "Export PNG")


# ------------------------------------------------------------------ row helpers

static func _section(parent: Control, title: String, first := false) -> void:
	if not first:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		parent.add_child(gap)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", DIM)
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)


static func _picker_row(parent: Control, text: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_row_label(text))
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(picker)
	row.add_child(picker)
	parent.add_child(row)
	return picker


static func _slider_row(parent: Control, text: String, minv: float, maxv: float,
		step: float, value: float, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_row_label(text))
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var val := Label.new()
	val.text = fmt % value
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", TEXT)
	row.add_child(val)
	slider.value_changed.connect(func(v: float) -> void: val.text = fmt % v)
	parent.add_child(row)
	return slider


static func _spin_row(parent: Control, text: String, minv: float, maxv: float,
		step: float, value: float, integer: bool) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_row_label(text))
	var spin := SpinBox.new()
	spin.min_value = minv
	spin.max_value = maxv
	spin.step = step
	spin.value = value
	spin.rounded = integer
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	parent.add_child(row)
	return spin


static func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	_style_button(button)
	parent.add_child(button)
	return button


static func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.add_theme_color_override("font_color", TEXT)
	return label


# ------------------------------------------------------------------ styling

static func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _flat(BTN, BORDER, 10.0, 5.0))
	button.add_theme_stylebox_override("hover", _flat(BTN_HOVER, BORDER, 10.0, 5.0))
	button.add_theme_stylebox_override("pressed", _flat(BTN_PRESSED, BORDER, 10.0, 5.0))
	button.add_theme_stylebox_override("disabled", _flat(Color(BTN, 0.45), BORDER, 10.0, 5.0))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_disabled_color", DIM)


static func _flat(bg: Color, border := Color(0, 0, 0, 0), pad_x := 0.0, pad_y := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	if pad_x > 0.0 or pad_y > 0.0:
		sb.content_margin_left = pad_x
		sb.content_margin_right = pad_x
		sb.content_margin_top = pad_y
		sb.content_margin_bottom = pad_y
	return sb
