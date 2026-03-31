extends Control

## Gem Designer — interactive tool for designing gem visual configurations.
## Provides real-time preview with all GemVisualResource parameters exposed
## as controls, plus export to .tres or JSON for creating new gem variants.

# All 23 available cut profiles from GemCutGenerators.
const CUT_IDS = [
	&"classic_round", &"old_european_round", &"cushion", &"heart_brilliant",
	&"trillion", &"straight_trillion",
	&"radiant_diamond", &"princess_square", &"radiant_octagon",
	&"hex_brilliant", &"pentagon_brilliant",
	&"emerald_step", &"asscher_step", &"octagon_step",
	&"baguette_step", &"tapered_baguette_step",
	&"oval_brilliant", &"marquise_brilliant", &"pear_brilliant",
	&"rose_round", &"half_dutch_rose_hex", &"double_rose", &"cross_rose",
]

# Built-in gem presets available from GemVisualRegistry.
const PRESET_IDS = [
	&"quartz", &"amethyst", &"peridot", &"topaz",
	&"sapphire", &"emerald", &"ruby", &"diamond",
]

# ---- UI references ----
var _preview: GemPreview
var _visual_id_input: LineEdit
var _cut_dropdown: OptionButton
var _preset_dropdown: OptionButton
var _base_color_picker: ColorPickerButton
var _depth_tint_picker: ColorPickerButton
var _shininess_slider: HSlider
var _shininess_value: Label
var _specular_slider: HSlider
var _specular_value: Label
var _contrast_slider: HSlider
var _contrast_value: Label
var _saturation_slider: HSlider
var _saturation_value: Label
var _dispersion_slider: HSlider
var _dispersion_value: Label
var _transparency_slider: HSlider
var _transparency_value: Label
var _edge_color_picker: ColorPickerButton
var _edge_width_slider: HSlider
var _edge_width_value: Label
var _outline_color_picker: ColorPickerButton
var _outline_width_slider: HSlider
var _outline_width_value: Label
var _rim_intensity_slider: HSlider
var _rim_intensity_value: Label
var _rim_color_picker: ColorPickerButton
var _rim_power_slider: HSlider
var _rim_power_value: Label
var _translucency_slider: HSlider
var _translucency_value: Label
var _translucency_color_picker: ColorPickerButton
var _secondary_spec_slider: HSlider
var _secondary_spec_value: Label
var _secondary_angle_slider: HSlider
var _secondary_angle_value: Label
var _sparkle_intensity_slider: HSlider
var _sparkle_intensity_value: Label
var _sparkle_threshold_slider: HSlider
var _sparkle_threshold_value: Label
var _gradient_color_picker: ColorPickerButton
var _gradient_strength_slider: HSlider
var _gradient_strength_value: Label
var _brilliance_slider: HSlider
var _brilliance_value: Label
var _extinction_slider: HSlider
var _extinction_value: Label
var _export_text: TextEdit

# Suppress redundant refreshes during preset loading.
var _loading_preset: bool = false


func _ready() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.14)
	add_child(bg)

	# Main layout with margins
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)

	# === Left: Settings panel ===
	_build_settings_panel(hbox)

	# === Right: Preview + Export ===
	_build_preview_panel(hbox)

	# Initial render
	_refresh_preview()


# ===========================================================================
#  Settings panel (left column)
# ===========================================================================


func _build_settings_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.18)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# ---- Header ----
	_add_header(vbox, "Gem Designer")
	_add_separator(vbox)

	# ---- Preset loader ----
	_add_section_label(vbox, "Load Preset")
	_preset_dropdown = OptionButton.new()
	_preset_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_dropdown.add_item("(none)", 0)
	for i in PRESET_IDS.size():
		_preset_dropdown.add_item(String(PRESET_IDS[i]).capitalize(), i + 1)
	_preset_dropdown.item_selected.connect(_on_preset_selected)
	vbox.add_child(_preset_dropdown)

	_add_separator(vbox)

	# ---- Visual ID (for export naming) ----
	_add_section_label(vbox, "Visual ID (for export)")
	_visual_id_input = LineEdit.new()
	_visual_id_input.text = "custom_gem"
	_visual_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_visual_id_input)

	_add_separator(vbox)

	# ---- Cut profile ----
	_add_section_label(vbox, "Cut Profile")
	_cut_dropdown = OptionButton.new()
	_cut_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in CUT_IDS.size():
		_cut_dropdown.add_item(String(CUT_IDS[i]), i)
	_cut_dropdown.item_selected.connect(func(_idx: int): _refresh_preview())
	vbox.add_child(_cut_dropdown)

	_add_separator(vbox)

	# ---- Colours ----
	_add_section_label(vbox, "Colours")

	_add_field_label(vbox, "Base Color")
	_base_color_picker = _create_color_picker(Color(0.92, 0.93, 0.95))
	vbox.add_child(_base_color_picker)

	_add_field_label(vbox, "Depth Tint")
	_depth_tint_picker = _create_color_picker(Color.TRANSPARENT)
	vbox.add_child(_depth_tint_picker)

	_add_separator(vbox)

	# ---- Material properties ----
	_add_section_label(vbox, "Material")

	var row: Array

	row = _add_slider_row(vbox, "Shininess", 1.0, 256.0, 32.0, 0.5)
	_shininess_slider = row[0]; _shininess_value = row[1]

	row = _add_slider_row(vbox, "Specular Intensity", 0.0, 1.0, 0.4, 0.01)
	_specular_slider = row[0]; _specular_value = row[1]

	row = _add_slider_row(vbox, "Contrast", 0.0, 1.0, 0.3, 0.01)
	_contrast_slider = row[0]; _contrast_value = row[1]

	row = _add_slider_row(vbox, "Saturation Boost", -0.5, 0.5, 0.0, 0.01)
	_saturation_slider = row[0]; _saturation_value = row[1]

	row = _add_slider_row(vbox, "Hue Dispersion", 0.0, 0.5, 0.0, 0.01)
	_dispersion_slider = row[0]; _dispersion_value = row[1]

	row = _add_slider_row(vbox, "Transparency", 0.0, 1.0, 0.0, 0.01)
	_transparency_slider = row[0]; _transparency_value = row[1]

	_add_separator(vbox)

	# ---- Edge rendering ----
	_add_section_label(vbox, "Edge Rendering")

	_add_field_label(vbox, "Edge Color")
	_edge_color_picker = _create_color_picker(Color(1.0, 1.0, 1.0, 0.0))
	vbox.add_child(_edge_color_picker)

	row = _add_slider_row(vbox, "Edge Width", 0.0, 3.0, 0.0, 0.1)
	_edge_width_slider = row[0]; _edge_width_value = row[1]

	_add_field_label(vbox, "Outline Color")
	_outline_color_picker = _create_color_picker(Color(0.0, 0.0, 0.0, 0.15))
	vbox.add_child(_outline_color_picker)

	row = _add_slider_row(vbox, "Outline Width", 0.0, 4.0, 1.0, 0.1)
	_outline_width_slider = row[0]; _outline_width_value = row[1]

	_add_separator(vbox)

	# ---- Rim lighting ----
	_add_section_label(vbox, "Rim Lighting")

	row = _add_slider_row(vbox, "Rim Intensity", 0.0, 1.0, 0.0, 0.01)
	_rim_intensity_slider = row[0]; _rim_intensity_value = row[1]

	_add_field_label(vbox, "Rim Color")
	_rim_color_picker = _create_color_picker(Color.WHITE)
	vbox.add_child(_rim_color_picker)

	row = _add_slider_row(vbox, "Rim Power", 1.0, 5.0, 2.0, 0.1)
	_rim_power_slider = row[0]; _rim_power_value = row[1]

	_add_separator(vbox)

	# ---- Translucency ----
	_add_section_label(vbox, "Translucency")

	row = _add_slider_row(vbox, "Translucency", 0.0, 1.0, 0.0, 0.01)
	_translucency_slider = row[0]; _translucency_value = row[1]

	_add_field_label(vbox, "Translucency Color")
	_translucency_color_picker = _create_color_picker(Color.WHITE)
	vbox.add_child(_translucency_color_picker)

	_add_separator(vbox)

	# ---- Secondary specular ----
	_add_section_label(vbox, "Secondary Specular")

	row = _add_slider_row(vbox, "Secondary Specular", 0.0, 1.0, 0.0, 0.01)
	_secondary_spec_slider = row[0]; _secondary_spec_value = row[1]

	row = _add_slider_row(vbox, "Light Angle Offset", 0.0, 360.0, 120.0, 1.0)
	_secondary_angle_slider = row[0]; _secondary_angle_value = row[1]

	_add_separator(vbox)

	# ---- Sparkle ----
	_add_section_label(vbox, "Sparkle")

	row = _add_slider_row(vbox, "Sparkle Intensity", 0.0, 3.0, 0.0, 0.01)
	_sparkle_intensity_slider = row[0]; _sparkle_intensity_value = row[1]

	row = _add_slider_row(vbox, "Sparkle Threshold", 0.0, 1.0, 0.85, 0.01)
	_sparkle_threshold_slider = row[0]; _sparkle_threshold_value = row[1]

	_add_separator(vbox)

	# ---- Color gradient ----
	_add_section_label(vbox, "Color Gradient")

	_add_field_label(vbox, "Gradient Color")
	_gradient_color_picker = _create_color_picker(Color.TRANSPARENT)
	vbox.add_child(_gradient_color_picker)

	row = _add_slider_row(vbox, "Gradient Strength", 0.0, 1.0, 0.0, 0.01)
	_gradient_strength_slider = row[0]; _gradient_strength_value = row[1]

	_add_separator(vbox)

	# ---- Zone brilliance ----
	_add_section_label(vbox, "Zone Brilliance")

	row = _add_slider_row(vbox, "Brilliance Contrast", 0.0, 1.0, 0.0, 0.01)
	_brilliance_slider = row[0]; _brilliance_value = row[1]

	_add_separator(vbox)

	# ---- Extinction ----
	_add_section_label(vbox, "Extinction")

	row = _add_slider_row(vbox, "Extinction", 0.0, 1.0, 0.0, 0.01)
	_extinction_slider = row[0]; _extinction_value = row[1]


# ===========================================================================
#  Preview + Export panel (right column)
# ===========================================================================


func _build_preview_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	parent.add_child(vbox)

	# ---- Top bar ----
	var top_bar := HBoxContainer.new()
	vbox.add_child(top_bar)

	var back_btn := Button.new()
	back_btn.text = "< Back to Menu"
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn"))
	top_bar.add_child(back_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var title := Label.new()
	title.text = "Preview"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	top_bar.add_child(title)

	# ---- Gem preview (centred) ----
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(center)

	var preview_bg := PanelContainer.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.09)
	bg_style.set_corner_radius_all(12)
	bg_style.content_margin_left = 32
	bg_style.content_margin_right = 32
	bg_style.content_margin_top = 32
	bg_style.content_margin_bottom = 32
	preview_bg.add_theme_stylebox_override("panel", bg_style)
	center.add_child(preview_bg)

	_preview = GemPreview.new()
	_preview.custom_minimum_size = Vector2(400, 400)
	preview_bg.add_child(_preview)

	# ---- Export section ----
	_add_separator(vbox)

	var export_bar := HBoxContainer.new()
	export_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(export_bar)

	var export_tres_btn := Button.new()
	export_tres_btn.text = "Export .tres to Clipboard"
	export_tres_btn.pressed.connect(_on_export_tres)
	export_bar.add_child(export_tres_btn)

	var export_json_btn := Button.new()
	export_json_btn.text = "Export JSON to Clipboard"
	export_json_btn.pressed.connect(_on_export_json)
	export_bar.add_child(export_json_btn)

	_export_text = TextEdit.new()
	_export_text.custom_minimum_size = Vector2(0, 160)
	_export_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_text.editable = false
	_export_text.placeholder_text = "Export output will appear here. Use the buttons above to generate."
	vbox.add_child(_export_text)


# ===========================================================================
#  UI helpers
# ===========================================================================


func _add_header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.75, 0.77, 0.82))
	parent.add_child(label)


func _add_field_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	parent.add_child(label)


func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	parent.add_child(sep)


func _create_color_picker(default_color: Color) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.color = default_color
	picker.custom_minimum_size = Vector2(0, 32)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.edit_alpha = true
	picker.color_changed.connect(func(_c: Color): _refresh_preview())
	return picker


## Creates a labelled slider row. Returns [slider, value_label].
## The container is added directly to parent.
func _add_slider_row(
	parent: VBoxContainer,
	label_text: String,
	min_val: float,
	max_val: float,
	default_val: float,
	step_val: float,
) -> Array:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	parent.add_child(container)

	var header := HBoxContainer.new()
	container.add_child(header)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var value_label := Label.new()
	value_label.text = _format_display(default_val)
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(60, 0)
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(val: float):
		value_label.text = _format_display(val)
		_refresh_preview()
	)
	container.add_child(slider)

	return [slider, value_label]


func _format_display(val: float) -> String:
	if absf(val) >= 10.0:
		return "%.1f" % val
	return "%.2f" % val


# ===========================================================================
#  Preview refresh
# ===========================================================================


func _refresh_preview() -> void:
	if _loading_preset:
		return
	if _preview == null or _cut_dropdown == null:
		return
	var cut_idx := _cut_dropdown.selected
	if cut_idx < 0 or cut_idx >= CUT_IDS.size():
		return
	_preview.update_preview(CUT_IDS[cut_idx], _build_visual())


func _build_visual() -> GemVisualResource:
	var v := GemVisualResource.new()
	v.visual_id = StringName(_visual_id_input.text) if _visual_id_input else &"custom_gem"
	v.cut_id = CUT_IDS[_cut_dropdown.selected] if _cut_dropdown.selected >= 0 else &"classic_round"
	v.base_color = _base_color_picker.color
	v.depth_tint = _depth_tint_picker.color
	v.shininess = _shininess_slider.value
	v.specular_intensity = _specular_slider.value
	v.contrast = _contrast_slider.value
	v.saturation_boost = _saturation_slider.value
	v.hue_dispersion = _dispersion_slider.value
	v.transparency = _transparency_slider.value
	v.edge_color = _edge_color_picker.color
	v.edge_width = _edge_width_slider.value
	v.outline_color = _outline_color_picker.color
	v.outline_width = _outline_width_slider.value
	v.rim_intensity = _rim_intensity_slider.value
	v.rim_color = _rim_color_picker.color
	v.rim_power = _rim_power_slider.value
	v.translucency = _translucency_slider.value
	v.translucency_color = _translucency_color_picker.color
	v.secondary_specular = _secondary_spec_slider.value
	v.secondary_light_angle = _secondary_angle_slider.value
	v.sparkle_intensity = _sparkle_intensity_slider.value
	v.sparkle_threshold = _sparkle_threshold_slider.value
	v.gradient_color = _gradient_color_picker.color
	v.gradient_strength = _gradient_strength_slider.value
	v.brilliance_contrast = _brilliance_slider.value
	v.extinction = _extinction_slider.value
	return v


# ===========================================================================
#  Preset loading
# ===========================================================================


func _on_preset_selected(idx: int) -> void:
	if idx <= 0:
		return
	var preset_id: StringName = PRESET_IDS[idx - 1]
	var visual := GemVisualRegistry.get_visual(preset_id)
	if visual == null:
		return
	_load_from_visual(visual)


func _load_from_visual(visual: GemVisualResource) -> void:
	_loading_preset = true

	# Update cut dropdown
	var cut_idx := -1
	for i in CUT_IDS.size():
		if CUT_IDS[i] == visual.cut_id:
			cut_idx = i
			break
	if cut_idx >= 0:
		_cut_dropdown.select(cut_idx)

	_visual_id_input.text = String(visual.visual_id) if visual.visual_id != &"" else "custom_gem"
	_base_color_picker.color = visual.base_color
	_depth_tint_picker.color = visual.depth_tint
	_shininess_slider.value = visual.shininess
	_shininess_value.text = _format_display(visual.shininess)
	_specular_slider.value = visual.specular_intensity
	_specular_value.text = _format_display(visual.specular_intensity)
	_contrast_slider.value = visual.contrast
	_contrast_value.text = _format_display(visual.contrast)
	_saturation_slider.value = visual.saturation_boost
	_saturation_value.text = _format_display(visual.saturation_boost)
	_dispersion_slider.value = visual.hue_dispersion
	_dispersion_value.text = _format_display(visual.hue_dispersion)
	_transparency_slider.value = visual.transparency
	_transparency_value.text = _format_display(visual.transparency)
	_edge_color_picker.color = visual.edge_color
	_edge_width_slider.value = visual.edge_width
	_edge_width_value.text = _format_display(visual.edge_width)
	_outline_color_picker.color = visual.outline_color
	_outline_width_slider.value = visual.outline_width
	_outline_width_value.text = _format_display(visual.outline_width)
	_rim_intensity_slider.value = visual.rim_intensity
	_rim_intensity_value.text = _format_display(visual.rim_intensity)
	_rim_color_picker.color = visual.rim_color
	_rim_power_slider.value = visual.rim_power
	_rim_power_value.text = _format_display(visual.rim_power)
	_translucency_slider.value = visual.translucency
	_translucency_value.text = _format_display(visual.translucency)
	_translucency_color_picker.color = visual.translucency_color
	_secondary_spec_slider.value = visual.secondary_specular
	_secondary_spec_value.text = _format_display(visual.secondary_specular)
	_secondary_angle_slider.value = visual.secondary_light_angle
	_secondary_angle_value.text = _format_display(visual.secondary_light_angle)
	_sparkle_intensity_slider.value = visual.sparkle_intensity
	_sparkle_intensity_value.text = _format_display(visual.sparkle_intensity)
	_sparkle_threshold_slider.value = visual.sparkle_threshold
	_sparkle_threshold_value.text = _format_display(visual.sparkle_threshold)
	_gradient_color_picker.color = visual.gradient_color
	_gradient_strength_slider.value = visual.gradient_strength
	_gradient_strength_value.text = _format_display(visual.gradient_strength)
	_brilliance_slider.value = visual.brilliance_contrast
	_brilliance_value.text = _format_display(visual.brilliance_contrast)
	_extinction_slider.value = visual.extinction
	_extinction_value.text = _format_display(visual.extinction)

	_loading_preset = false
	_refresh_preview()


# ===========================================================================
#  Export
# ===========================================================================


func _on_export_tres() -> void:
	var text := _generate_tres(_build_visual())
	DisplayServer.clipboard_set(text)
	_export_text.text = text


func _on_export_json() -> void:
	var text := _generate_json(_build_visual())
	DisplayServer.clipboard_set(text)
	_export_text.text = text


func _generate_tres(v: GemVisualResource) -> String:
	var lines := PackedStringArray()
	lines.append('[gd_resource type="Resource" script_class="GemVisualResource" load_steps=2 format=3]')
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://resources/visuals/gem_visual_resource.gd" id="1"]')
	lines.append("")
	lines.append("[resource]")
	lines.append('script = ExtResource("1")')
	lines.append('visual_id = &"%s"' % String(v.visual_id))
	lines.append('cut_id = &"%s"' % String(v.cut_id))
	lines.append("base_color = Color(%s)" % _fmt_color(v.base_color))

	# Only include non-default properties (matches Godot serialisation behaviour).
	if not is_equal_approx(v.shininess, 32.0):
		lines.append("shininess = %s" % _fmt_prop(v.shininess))
	if not is_equal_approx(v.specular_intensity, 0.4):
		lines.append("specular_intensity = %s" % _fmt_prop(v.specular_intensity))
	if not is_equal_approx(v.contrast, 0.3):
		lines.append("contrast = %s" % _fmt_prop(v.contrast))
	if v.depth_tint.a > 0.001:
		lines.append("depth_tint = Color(%s)" % _fmt_color(v.depth_tint))
	if not is_zero_approx(v.saturation_boost):
		lines.append("saturation_boost = %s" % _fmt_prop(v.saturation_boost))
	if v.hue_dispersion > 0.001:
		lines.append("hue_dispersion = %s" % _fmt_prop(v.hue_dispersion))
	if v.transparency > 0.001:
		lines.append("transparency = %s" % _fmt_prop(v.transparency))
	if v.edge_width > 0.001:
		lines.append("edge_color = Color(%s)" % _fmt_color(v.edge_color))
		lines.append("edge_width = %s" % _fmt_prop(v.edge_width))
	if not is_equal_approx(v.outline_width, 1.0) or _color_differs(v.outline_color, Color(0, 0, 0, 0.15)):
		lines.append("outline_color = Color(%s)" % _fmt_color(v.outline_color))
		lines.append("outline_width = %s" % _fmt_prop(v.outline_width))
	if v.rim_intensity > 0.001:
		lines.append("rim_intensity = %s" % _fmt_prop(v.rim_intensity))
		lines.append("rim_color = Color(%s)" % _fmt_color(v.rim_color))
		if not is_equal_approx(v.rim_power, 2.0):
			lines.append("rim_power = %s" % _fmt_prop(v.rim_power))
	if v.translucency > 0.001:
		lines.append("translucency = %s" % _fmt_prop(v.translucency))
		lines.append("translucency_color = Color(%s)" % _fmt_color(v.translucency_color))
	if v.secondary_specular > 0.001:
		lines.append("secondary_specular = %s" % _fmt_prop(v.secondary_specular))
		if not is_equal_approx(v.secondary_light_angle, 120.0):
			lines.append("secondary_light_angle = %s" % _fmt_prop(v.secondary_light_angle))
	if v.sparkle_intensity > 0.001:
		lines.append("sparkle_intensity = %s" % _fmt_prop(v.sparkle_intensity))
		if not is_equal_approx(v.sparkle_threshold, 0.85):
			lines.append("sparkle_threshold = %s" % _fmt_prop(v.sparkle_threshold))
	if v.gradient_strength > 0.001 and v.gradient_color.a > 0.001:
		lines.append("gradient_color = Color(%s)" % _fmt_color(v.gradient_color))
		lines.append("gradient_strength = %s" % _fmt_prop(v.gradient_strength))
	if v.brilliance_contrast > 0.001:
		lines.append("brilliance_contrast = %s" % _fmt_prop(v.brilliance_contrast))
	if v.extinction > 0.001:
		lines.append("extinction = %s" % _fmt_prop(v.extinction))
	lines.append("")
	return "\n".join(lines)


func _generate_json(v: GemVisualResource) -> String:
	var data := {
		"visual_id": String(v.visual_id),
		"cut_id": String(v.cut_id),
		"base_color": _color_array(v.base_color),
		"shininess": snappedf(v.shininess, 0.01),
		"specular_intensity": snappedf(v.specular_intensity, 0.001),
		"contrast": snappedf(v.contrast, 0.001),
		"depth_tint": _color_array(v.depth_tint),
		"saturation_boost": snappedf(v.saturation_boost, 0.001),
		"hue_dispersion": snappedf(v.hue_dispersion, 0.001),
		"transparency": snappedf(v.transparency, 0.001),
		"edge_color": _color_array(v.edge_color),
		"edge_width": snappedf(v.edge_width, 0.01),
		"outline_color": _color_array(v.outline_color),
		"outline_width": snappedf(v.outline_width, 0.01),
		"rim_intensity": snappedf(v.rim_intensity, 0.001),
		"rim_color": _color_array(v.rim_color),
		"rim_power": snappedf(v.rim_power, 0.01),
		"translucency": snappedf(v.translucency, 0.001),
		"translucency_color": _color_array(v.translucency_color),
		"secondary_specular": snappedf(v.secondary_specular, 0.001),
		"secondary_light_angle": snappedf(v.secondary_light_angle, 0.1),
		"sparkle_intensity": snappedf(v.sparkle_intensity, 0.001),
		"sparkle_threshold": snappedf(v.sparkle_threshold, 0.001),
		"gradient_color": _color_array(v.gradient_color),
		"gradient_strength": snappedf(v.gradient_strength, 0.001),
		"brilliance_contrast": snappedf(v.brilliance_contrast, 0.001),
		"extinction": snappedf(v.extinction, 0.001),
	}
	return JSON.stringify(data, "  ")


# ===========================================================================
#  Formatting helpers
# ===========================================================================


func _fmt_color(c: Color) -> String:
	return "%s, %s, %s, %s" % [_fmt_cc(c.r), _fmt_cc(c.g), _fmt_cc(c.b), _fmt_cc(c.a)]


func _fmt_cc(val: float) -> String:
	## Format a color component for .tres Color() syntax.
	var s := snappedf(val, 0.0001)
	if is_equal_approx(s, roundf(s)):
		return str(int(roundf(s)))
	var text := "%.4f" % s
	text = text.rstrip("0")
	if text.ends_with("."):
		text += "0"
	return text


func _fmt_prop(val: float) -> String:
	## Format a scalar property for .tres syntax.
	var s := snappedf(val, 0.0001)
	if is_equal_approx(s, roundf(s)):
		return "%d.0" % int(roundf(s))
	var text := "%.4f" % s
	text = text.rstrip("0")
	return text


func _color_array(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001), snappedf(c.a, 0.001)]


func _color_differs(a: Color, b: Color) -> bool:
	return not (is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g)
		and is_equal_approx(a.b, b.b) and is_equal_approx(a.a, b.a))
