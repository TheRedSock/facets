extends Control

## Runtime gem designer: edit visual + cut spec, live traced preview, showroom bake + arcball viewer.

const SESSION_TILE_ID := &"gem_designer_session"
const ANALYSIS_PREVIEW_BASE_PX := 320.0
const GAMEPLAY_BLEND_SHADER := preload("res://scenes/tile/gameplay_sprite_blend.gdshader")
const PREVIEW_SIZE := Vector2i(256, 256)
const DEBOUNCE_SEC := 1.0

const GemDesignSessionScript = preload("res://scenes/design/gem_design_session.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const GemViewSphereSamplingScript = preload("res://core/visuals/gem_view_sphere_sampling.gd")
const GemCutModelModifierScript = preload("res://resources/visuals/gem_cut_model_modifier.gd")
const GemEnvironmentPresetsScript = preload("res://core/visuals/gem_environment_presets.gd")

var _session: GemDesignSessionScript

var _gem_dropdown: OptionButton
var _preview_tex: TextureRect
var _preview_timer: Timer
var _preview_gen := 0
var _preview_thread: Thread
var _preview_stylize_checkbox: CheckBox

var _visual_scroll: VBoxContainer
var _visual_json_edit: TextEdit
var _cut_edit: TextEdit
## ColorRect (not TextureRect): UV for the blend shader must span the preview rect.
## Wrapped in AspectRatioContainer so a wide Tab row does not squash the rect to a strip
## (which stretches UVs and hides orbit updates).
var _analysis_aspect: AspectRatioContainer
var _analysis_viewport: ColorRect
var _analysis_blend_material: ShaderMaterial
var _analysis_transparent_tex: Texture2D
var _analysis_debug_checkbox: CheckBox
var _analysis_debug_label: RichTextLabel
var _showroom_axis_steps_spin: SpinBox
var _showroom_orbit_checkbox: CheckBox
var _showroom_dir_spin: SpinBox
var _showroom_roll_spin: SpinBox
var _showroom_theta_label: Label
var _showroom_total_label: Label
var _analysis_draw_spin: SpinBox
var _analysis_sample_spin: SpinBox
var _analysis_output: LineEdit
var _showroom_stylize_checkbox: CheckBox
var _preview_bounces_spin: SpinBox
var _preview_samples_spin: SpinBox
var _showroom_bounces_spin: SpinBox
var _status: Label

var _orientation := Quaternion.IDENTITY
var _zoom := 1.0
## 0 = free arcball, 1 = pitch (X-axis), 2 = yaw (Y-axis).
var _showroom_interaction_mode := 1
var _axis_angle_deg := 0.0
var _drag_active := false
var _last_drag: Vector2
var _has_showroom_bake := false
var _has_orbit_bake := false
var _showroom_mode_row: HBoxContainer
var _free_orbit_btn: Button
var _analysis_scroll: ScrollContainer
var _invert_x := false
var _invert_y := false
var _invert_x_checkbox: CheckBox
var _invert_y_checkbox: CheckBox

var _bake_in_progress := false
var _bake_btn: Button
var _bake_progress: ProgressBar
var _bake_progress_label: Label

var _section_collapse_state: Dictionary = {}
var _updating_property := false

## Tracks sentinel-aware compound widgets keyed by property name.
## Each entry: { "checkbox": CheckBox, "slider": HSlider, "spinbox": SpinBox,
##   "color_picker": ColorPickerButton (for color sentinels), "auto_key": String }
var _sentinel_widgets: Dictionary = {}
## Tracks all property row Controls keyed by property name (for dependency dimming).
var _prop_row_controls: Dictionary = {}

# ---------------------------------------------------------------------------
# Sentinel property definitions
# ---------------------------------------------------------------------------
# Float sentinels: property_name -> { sentinel, auto_key, override_min, override_max, override_step }
const _FLOAT_SENTINEL_PROPERTIES := {
	&"optics_ground_albedo": { "sentinel": -1.0, "auto_key": "ground_albedo", "override_min": 0.0, "override_max": 1.0, "override_step": 0.01 },
	&"optics_ground_distance": { "sentinel": -1.0, "auto_key": "ground_distance", "override_min": 0.1, "override_max": 4.0, "override_step": 0.01 },
	&"optics_light_temperature_kelvin": { "sentinel": 0.0, "auto_key": "light_temperature_kelvin", "override_min": 2500.0, "override_max": 10000.0, "override_step": 50.0 },
	&"optics_cloudiness_override": { "sentinel": -1.0, "auto_key": "cloudiness", "override_min": 0.0, "override_max": 0.5, "override_step": 0.005 },
	&"optics_transmission_override": { "sentinel": -1.0, "auto_key": "transmission", "override_min": 0.0, "override_max": 1.0, "override_step": 0.01 },
	&"optics_grade_exposure": { "sentinel": -1.0, "auto_key": "grade_exposure", "override_min": 0.0, "override_max": 4.0, "override_step": 0.01 },
	&"optics_grade_saturation": { "sentinel": -1.0, "auto_key": "grade_saturation", "override_min": -0.1, "override_max": 0.56, "override_step": 0.01 },
}
# Color sentinels: property_name -> { auto_key }
const _COLOR_SENTINEL_PROPERTIES := {
	&"optics_ground_tint": { "auto_key": "ground_tint" },
}

# ---------------------------------------------------------------------------
# Dependency rules: property -> { requires: { prop: condition }, reason: String }
# Condition strings: "> 0", "!= 0", "> 0 (effective)"
# ---------------------------------------------------------------------------
const _DEPENDENCY_RULES := {
	&"sparkle_threshold": { "requires": { &"sparkle_intensity": "> 0" }, "reason": "Requires sparkle intensity > 0" },
	&"optics_sparkle_power_multiplier": { "requires": { &"sparkle_intensity": "> 0" }, "reason": "Requires sparkle intensity > 0" },
	&"rim_color": { "requires": { &"rim_intensity": "> 0" }, "reason": "Requires rim intensity > 0" },
	&"rim_power": { "requires": { &"rim_intensity": "> 0" }, "reason": "Requires rim intensity > 0" },
	&"optics_rim_strength_multiplier": { "requires": { &"rim_intensity": "> 0" }, "reason": "Requires rim intensity > 0" },
	&"optics_ground_tint": { "requires": { &"optics_ground_albedo": "> 0 (effective)" }, "reason": "Ground albedo must be > 0 for tint to apply" },
	&"optics_ground_distance": { "requires": { &"optics_ground_albedo": "> 0 (effective)" }, "reason": "Ground albedo must be > 0 for distance to apply" },
	&"gradient_mode": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"gradient_angle_degrees": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"gradient_color": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"phenomenon_angle_degrees": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
	&"phenomenon_sharpness": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
	&"phenomenon_color": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
	&"translucency_color": { "requires": { &"translucency": "> 0" }, "reason": "Requires translucency > 0" },
	&"secondary_light_angle": { "requires": { &"secondary_specular": "> 0" }, "reason": "Requires secondary specular > 0" },
	&"surface_pattern_mix": { "requires": { &"surface_pattern_type": "!= 0" }, "reason": "Requires surface pattern type != None" },
	&"surface_pattern_scale": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_rotation_degrees": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_density": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_contrast": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_warp_strength": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_warp_scale": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_specular_variation": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"surface_pattern_roughness_variation": { "requires": { &"surface_pattern_type": "!= 0", &"surface_pattern_mix": "> 0" }, "reason": "Requires surface pattern active" },
	&"volume_pattern_mix": { "requires": { &"volume_pattern_type": "!= 0" }, "reason": "Requires volume pattern type != None" },
	&"volume_pattern_scale": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_pattern_axis": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_pattern_density": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_pattern_contrast": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_pattern_warp_strength": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_pattern_warp_scale": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_absorption_variation": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"volume_scattering_variation": { "requires": { &"volume_pattern_type": "!= 0", &"volume_pattern_mix": "> 0" }, "reason": "Requires volume pattern active" },
	&"reactive_color": { "requires": { &"reactive_effect_type": "!= 0", &"reactive_strength": "> 0" }, "reason": "Requires reactive effect active" },
	&"reactive_secondary_color": { "requires": { &"reactive_effect_type": "!= 0", &"reactive_strength": "> 0" }, "reason": "Requires reactive effect active" },
	&"reactive_sharpness": { "requires": { &"reactive_effect_type": "!= 0", &"reactive_strength": "> 0" }, "reason": "Requires reactive effect active" },
	&"reactive_density": { "requires": { &"reactive_effect_type": "!= 0", &"reactive_strength": "> 0" }, "reason": "Requires reactive effect active" },
	&"reactive_scale": { "requires": { &"reactive_effect_type": "!= 0", &"reactive_strength": "> 0" }, "reason": "Requires reactive effect active" },
	&"reactive_axis": { "requires": { &"reactive_effect_type": "!= 0", &"reactive_strength": "> 0" }, "reason": "Requires reactive effect active" },
	&"stylize_facet_edge_gain": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_plane_contrast": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_shadow_floor": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_highlight_bloom_gain": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_highlight_bloom_threshold": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_microdetail_suppression": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_internal_color_shift_gain": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_tone_steps": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_edge_ink_strength": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_highlight_snap": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
}

const _PERCENTAGE_EXCLUSIONS := [
	&"hue_dispersion", &"saturation_boost", &"stylize_shadow_floor",
	&"stylize_highlight_bloom_threshold", &"optics_dispersion",
	&"optics_birefringence_strength", &"sparkle_threshold",
	&"optics_cloudiness_override", &"optics_transmission_override",
	&"optics_grade_exposure", &"optics_grade_saturation",
]
const _ALPHA_EDIT_PROPERTIES := [
	&"depth_tint", &"gradient_color", &"phenomenon_color", &"edge_color",
	&"optics_absorption_color", &"material_secondary_color",
	&"material_tertiary_color", &"reactive_color", &"reactive_secondary_color",
]
const _DEFAULT_COLLAPSED_GROUPS := [
	"Traced Optics", "Stylization", "Detailing",
]
const _GROUP_PREFIX_MAP := {
	"Surface Field": "surface_pattern_",
	"Volume Field": "volume_pattern_",
	"Angle Reactive": "reactive_",
	"Traced Optics": "optics_",
	"Refraction": "optics_",
	"Absorption & Scattering": "optics_",
	"Camera": "optics_",
	"Environment": "optics_",
	"Tuning": "optics_",
	"Output Grade": "optics_grade_",
	"Stylization": "stylize_",
	"Gradient": "gradient_",
	"Phenomenon": "phenomenon_",
	"Rim Lighting": "rim_",
	"Sparkle": "sparkle_",
	"Secondary Specular": "secondary_",
	"Edge Rendering": "edge_",
}


func _ready() -> void:
	_session = GemDesignSessionScript.new()
	_build_ui()
	_fill_gem_dropdown()
	if _gem_dropdown.item_count > 0:
		_on_gem_selected(0)


func _exit_tree() -> void:
	if _preview_thread != null and _preview_thread.is_started():
		_preview_thread.wait_to_finish()
		_preview_thread = null


func _build_ui() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.09)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := HBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(left)

	var title := Label.new()
	title.text = "Gem designer"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	left.add_child(title)

	_gem_dropdown = OptionButton.new()
	_gem_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	_gem_dropdown.item_selected.connect(_on_gem_selected)
	left.add_child(_labeled("Base gem", _gem_dropdown))

	var load_btn := Button.new()
	load_btn.text = "Load from file…"
	load_btn.pressed.connect(_on_load_file_pressed)
	left.add_child(load_btn)

	var save_btn := Button.new()
	save_btn.text = "Save visual as…"
	save_btn.pressed.connect(_on_save_file_pressed)
	left.add_child(save_btn)

	left.add_child(_make_separator())

	var mod_title := Label.new()
	mod_title.text = "Cut model modifiers"
	mod_title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	left.add_child(mod_title)

	var mod_add := Button.new()
	mod_add.text = "Add modifier resource…"
	mod_add.pressed.connect(_on_add_modifier_pressed)
	left.add_child(mod_add)

	left.add_child(_labeled("Preview (debounced)", _make_preview_panel()))

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = DEBOUNCE_SEC
	_preview_timer.timeout.connect(_on_preview_timer_timeout)
	add_child(_preview_timer)

	_status = Label.new()
	_status.text = "Ready"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	left.add_child(_status)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(center)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	center.add_child(tabs)

	var visual_panel := ScrollContainer.new()
	visual_panel.size_flags_vertical = SIZE_EXPAND_FILL
	visual_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	visual_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(visual_panel)
	tabs.set_tab_title(visual_panel.get_index(), "Visual")

	_visual_scroll = VBoxContainer.new()
	_visual_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_visual_scroll.add_theme_constant_override("separation", 4)
	visual_panel.add_child(_visual_scroll)

	var visual_json_panel := VBoxContainer.new()
	visual_json_panel.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.add_child(visual_json_panel)
	tabs.set_tab_title(visual_json_panel.get_index(), "Visual (JSON)")

	_visual_json_edit = TextEdit.new()
	_visual_json_edit.size_flags_vertical = SIZE_EXPAND_FILL
	_visual_json_edit.custom_minimum_size = Vector2(0, 200)
	visual_json_panel.add_child(_visual_json_edit)

	var vj_row := HBoxContainer.new()
	vj_row.add_theme_constant_override("separation", 8)
	visual_json_panel.add_child(vj_row)

	var apply_vj := Button.new()
	apply_vj.text = "Apply visual JSON"
	apply_vj.pressed.connect(_on_apply_visual_json)
	vj_row.add_child(apply_vj)

	var reload_vj := Button.new()
	reload_vj.text = "Reload from session"
	reload_vj.pressed.connect(_refresh_visual_json_text)
	vj_row.add_child(reload_vj)

	var copy_vj := Button.new()
	copy_vj.text = "Copy to clipboard"
	copy_vj.pressed.connect(func() -> void: DisplayServer.clipboard_set(_visual_json_edit.text))
	vj_row.add_child(copy_vj)

	var paste_vj := Button.new()
	paste_vj.text = "Paste from clipboard"
	paste_vj.pressed.connect(func() -> void: _visual_json_edit.text = DisplayServer.clipboard_get())
	vj_row.add_child(paste_vj)

	var cut_panel := VBoxContainer.new()
	cut_panel.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.add_child(cut_panel)
	tabs.set_tab_title(cut_panel.get_index(), "Cut (JSON)")

	_cut_edit = TextEdit.new()
	_cut_edit.size_flags_vertical = SIZE_EXPAND_FILL
	_cut_edit.custom_minimum_size = Vector2(0, 200)
	cut_panel.add_child(_cut_edit)

	var cut_row := HBoxContainer.new()
	cut_row.add_theme_constant_override("separation", 8)
	cut_panel.add_child(cut_row)

	var apply_cut := Button.new()
	apply_cut.text = "Apply cut JSON"
	apply_cut.pressed.connect(_on_apply_cut_json)
	cut_row.add_child(apply_cut)

	var reload_cut := Button.new()
	reload_cut.text = "Reload from session"
	reload_cut.pressed.connect(_refresh_cut_json_text)
	cut_row.add_child(reload_cut)

	var analysis_scroll := ScrollContainer.new()
	analysis_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	analysis_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	analysis_scroll.follow_focus = true
	_analysis_scroll = analysis_scroll
	tabs.add_child(analysis_scroll)
	tabs.set_tab_title(analysis_scroll.get_index(), "Analysis (Showroom)")

	var analysis_panel := VBoxContainer.new()
	analysis_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	analysis_scroll.add_child(analysis_panel)

	analysis_panel.add_child(_labeled("Axis rotation steps (per axis)", _make_axis_steps_spinbox()))
	_showroom_orbit_checkbox = CheckBox.new()
	_showroom_orbit_checkbox.text = "Include free orbit (Fibonacci)"
	_showroom_orbit_checkbox.toggled.connect(_on_orbit_checkbox_toggled)
	analysis_panel.add_child(_showroom_orbit_checkbox)
	analysis_panel.add_child(_labeled("  Fibonacci directions", _make_showroom_dir_spinbox()))
	_showroom_theta_label = Label.new()
	_showroom_theta_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	analysis_panel.add_child(_showroom_theta_label)
	analysis_panel.add_child(_labeled("  Roll steps per direction", _make_showroom_roll_spinbox()))
	_showroom_total_label = Label.new()
	_showroom_total_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	analysis_panel.add_child(_showroom_total_label)
	_on_orbit_checkbox_toggled(false)
	_update_showroom_info_labels()
	analysis_panel.add_child(_labeled("Bake draw size (px)", _make_analysis_draw_spinbox()))
	analysis_panel.add_child(_labeled("Samples", _make_analysis_sample_spinbox()))
	analysis_panel.add_child(_labeled("Max trace bounces", _make_showroom_bounces_spinbox()))
	analysis_panel.add_child(_labeled("Output folder", _analysis_output_line()))

	_showroom_stylize_checkbox = CheckBox.new()
	_showroom_stylize_checkbox.text = "Apply stylization"
	_showroom_stylize_checkbox.button_pressed = false
	analysis_panel.add_child(_showroom_stylize_checkbox)

	_bake_btn = Button.new()
	_bake_btn.text = "Run Showroom Bake"
	_bake_btn.pressed.connect(_on_run_showroom_bake)
	analysis_panel.add_child(_bake_btn)

	var _reload_btn := Button.new()
	_reload_btn.text = "Reload Previous Session"
	_reload_btn.pressed.connect(_on_reload_showroom_session)
	analysis_panel.add_child(_reload_btn)

	_bake_progress = ProgressBar.new()
	_bake_progress.min_value = 0.0
	_bake_progress.max_value = 1.0
	_bake_progress.value = 0.0
	_bake_progress.show_percentage = false
	_bake_progress.custom_minimum_size = Vector2(0, 18)
	_bake_progress.visible = false
	analysis_panel.add_child(_bake_progress)

	_bake_progress_label = Label.new()
	_bake_progress_label.text = ""
	_bake_progress_label.add_theme_font_size_override("font_size", 12)
	_bake_progress_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	_bake_progress_label.visible = false
	analysis_panel.add_child(_bake_progress_label)

	var hint := Label.new()
	hint.text = "Drag to rotate. Shift+drag horizontally for roll. Wheel = zoom. Bake first, then inspect."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	analysis_panel.add_child(hint)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	_showroom_mode_row = mode_row
	var mode_labels := ["Free Orbit", "Pitch", "Yaw"]
	for mode_i in mode_labels.size():
		var mbtn := Button.new()
		mbtn.text = mode_labels[mode_i]
		mbtn.toggle_mode = true
		mbtn.set_meta("showroom_mode", mode_i)
		mbtn.toggled.connect(_on_showroom_mode_toggled.bind(mode_i))
		mode_row.add_child(mbtn)
		if mode_i == 0:
			_free_orbit_btn = mbtn
			mbtn.disabled = true
	# Default to Pitch mode (mode 1) since Free Orbit starts disabled.
	(mode_row.get_child(1) as Button).button_pressed = true
	_showroom_interaction_mode = 1
	analysis_panel.add_child(mode_row)

	var invert_row := HBoxContainer.new()
	invert_row.add_theme_constant_override("separation", 12)
	_invert_x_checkbox = CheckBox.new()
	_invert_x_checkbox.text = "Invert X"
	_invert_x_checkbox.toggled.connect(func(pressed: bool) -> void: _invert_x = pressed)
	invert_row.add_child(_invert_x_checkbox)
	_invert_y_checkbox = CheckBox.new()
	_invert_y_checkbox.text = "Invert Y"
	_invert_y_checkbox.toggled.connect(func(pressed: bool) -> void: _invert_y = pressed)
	invert_row.add_child(_invert_y_checkbox)
	analysis_panel.add_child(invert_row)

	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	_analysis_transparent_tex = ImageTexture.create_from_image(blank)
	_analysis_aspect = AspectRatioContainer.new()
	_analysis_aspect.ratio = 1.0
	_analysis_aspect.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	_analysis_aspect.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	_analysis_aspect.custom_minimum_size = Vector2(ANALYSIS_PREVIEW_BASE_PX, ANALYSIS_PREVIEW_BASE_PX)
	_analysis_aspect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_analysis_aspect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_analysis_aspect.mouse_filter = Control.MOUSE_FILTER_PASS
	_analysis_viewport = ColorRect.new()
	_analysis_viewport.color = Color.WHITE
	_analysis_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_analysis_viewport.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_analysis_blend_material = ShaderMaterial.new()
	_analysis_blend_material.shader = GAMEPLAY_BLEND_SHADER
	_analysis_viewport.material = _analysis_blend_material
	_clear_showroom_blend_layers()
	_analysis_viewport.gui_input.connect(_on_analysis_gui_input)
	_analysis_viewport.resized.connect(_on_analysis_viewport_resized)
	_analysis_aspect.add_child(_analysis_viewport)
	analysis_panel.add_child(_analysis_aspect)

	_analysis_debug_checkbox = CheckBox.new()
	_analysis_debug_checkbox.text = "Show live orbit diagnostics"
	_analysis_debug_checkbox.button_pressed = true
	_analysis_debug_checkbox.toggled.connect(func(_pressed: bool): _update_analysis_debug_visibility())
	analysis_panel.add_child(_analysis_debug_checkbox)

	_analysis_debug_label = RichTextLabel.new()
	_analysis_debug_label.fit_content = true
	_analysis_debug_label.scroll_active = false
	_analysis_debug_label.bbcode_enabled = false
	_analysis_debug_label.custom_minimum_size = Vector2(0, 170)
	_analysis_debug_label.add_theme_font_size_override("normal_font_size", 12)
	analysis_panel.add_child(_analysis_debug_label)
	_update_analysis_debug_visibility()


func _make_axis_steps_spinbox() -> SpinBox:
	_showroom_axis_steps_spin = SpinBox.new()
	_showroom_axis_steps_spin.min_value = 8.0
	_showroom_axis_steps_spin.max_value = 360.0
	_showroom_axis_steps_spin.step = 1.0
	_showroom_axis_steps_spin.value = 36.0
	_showroom_axis_steps_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_showroom_axis_steps_spin.value_changed.connect(func(_v: float) -> void: _update_showroom_info_labels())
	return _showroom_axis_steps_spin


func _make_showroom_dir_spinbox() -> SpinBox:
	_showroom_dir_spin = SpinBox.new()
	_showroom_dir_spin.min_value = 16.0
	_showroom_dir_spin.max_value = 2000.0
	_showroom_dir_spin.step = 1.0
	_showroom_dir_spin.value = 200.0
	_showroom_dir_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_showroom_dir_spin.value_changed.connect(func(_v: float) -> void: _update_showroom_info_labels())
	return _showroom_dir_spin


func _make_showroom_roll_spinbox() -> SpinBox:
	_showroom_roll_spin = SpinBox.new()
	_showroom_roll_spin.min_value = 1.0
	_showroom_roll_spin.max_value = 24.0
	_showroom_roll_spin.step = 1.0
	_showroom_roll_spin.value = 6.0
	_showroom_roll_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_showroom_roll_spin.value_changed.connect(func(_v: float) -> void: _update_showroom_info_labels())
	return _showroom_roll_spin


func _on_showroom_mode_toggled(pressed: bool, mode: int) -> void:
	if not pressed:
		return
	if mode == 0 and not _has_orbit_bake:
		# Re-press the previously active button if Free Orbit isn't available.
		if _showroom_mode_row != null:
			for c in _showroom_mode_row.get_children():
				if c is Button and int(c.get_meta("showroom_mode", -1)) == _showroom_interaction_mode:
					(c as Button).set_pressed_no_signal(true)
		return
	_showroom_interaction_mode = mode
	if _showroom_mode_row != null:
		for c in _showroom_mode_row.get_children():
			if c is Button and int(c.get_meta("showroom_mode", -1)) != mode:
				(c as Button).set_pressed_no_signal(false)
	_update_showroom_display()


func _on_orbit_checkbox_toggled(enabled: bool) -> void:
	if _showroom_dir_spin != null:
		_showroom_dir_spin.editable = enabled
	if _showroom_roll_spin != null:
		_showroom_roll_spin.editable = enabled
	_update_showroom_info_labels()


func _update_showroom_info_labels() -> void:
	var axis_steps := 36
	if _showroom_axis_steps_spin != null:
		axis_steps = int(_showroom_axis_steps_spin.value)
	var axis_total := axis_steps * 2  # pitch + yaw
	var dirs := 200
	var rolls := 6
	if _showroom_dir_spin != null:
		dirs = int(_showroom_dir_spin.value)
	if _showroom_roll_spin != null:
		rolls = int(_showroom_roll_spin.value)
	var include_orbit := _showroom_orbit_checkbox != null and _showroom_orbit_checkbox.button_pressed
	if _showroom_theta_label != null:
		if include_orbit:
			var theta := GemViewSphereSamplingScript.showroom_angular_resolution_degrees(dirs)
			_showroom_theta_label.text = "  Approx. angular resolution: ~%.1f°" % theta
		else:
			_showroom_theta_label.text = ""
	if _showroom_total_label != null:
		if include_orbit:
			var orbit_total := dirs * rolls
			_showroom_total_label.text = "Total: %d axis + %d orbit = %d frames" % [
				axis_total, orbit_total, axis_total + orbit_total
			]
		else:
			_showroom_total_label.text = "Total: %d axis frames (%d pitch + %d yaw)" % [
				axis_total, axis_steps, axis_steps
			]


func _on_analysis_viewport_resized() -> void:
	if _analysis_viewport == null:
		return
	_analysis_viewport.pivot_offset = _analysis_viewport.size * 0.5
	if _analysis_blend_material == null:
		return
	var a: Variant = _analysis_blend_material.get_shader_parameter("atlas")
	_update_showroom_texture_size_uniform_atlas(a as Texture2DArray)


func _scroll_showroom_to_bottom() -> void:
	if _analysis_scroll == null:
		return
	# Defer so layout has settled after the preview resize.
	_analysis_scroll.call_deferred("set_v_scroll", 999999)


func _clear_showroom_blend_layers() -> void:
	if _analysis_blend_material == null:
		return
	_analysis_blend_material.set_shader_parameter("weights", Vector4.ZERO)
	_analysis_blend_material.set_shader_parameter("layer_index", Vector4.ZERO)
	if GemVisualRegistry != null:
		_analysis_blend_material.set_shader_parameter(
			"atlas",
			GemVisualRegistry.get_gameplay_blend_placeholder_atlas()
		)
	else:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ta := Texture2DArray.new()
		ta.create_from_images([img])
		_analysis_blend_material.set_shader_parameter("atlas", ta)
	_analysis_blend_material.set_shader_parameter("outline_enabled", false)


func _apply_showroom_blend_entries(entries: Array) -> void:
	if _analysis_blend_material == null or GemVisualRegistry == null:
		return
	var texs: Array[Texture2D] = []
	var weights: Array[float] = []
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = e
		var w := float(ed.get("weight", 0.0))
		var tex: Texture2D = ed.get("texture", null)
		if w <= 0.0001 or tex == null:
			continue
		texs.append(tex)
		weights.append(w)
	while texs.size() < 4:
		texs.append(_analysis_transparent_tex)
		weights.append(0.0)
	var tw := weights[0] + weights[1] + weights[2] + weights[3]
	if tw <= 1e-6:
		_clear_showroom_blend_layers()
		return
	var wv := Vector4(
		weights[0] / tw,
		weights[1] / tw,
		weights[2] / tw,
		weights[3] / tw
	)
	var atlas: Texture2DArray = GemVisualRegistry.build_gameplay_sprite_atlas_from_textures(texs)
	_analysis_blend_material.set_shader_parameter("weights", wv)
	_analysis_blend_material.set_shader_parameter("layer_index", Vector4(0.0, 1.0, 2.0, 3.0))
	_analysis_blend_material.set_shader_parameter("atlas", atlas)
	_update_showroom_texture_size_uniform_atlas(atlas)
	if _analysis_viewport != null:
		_analysis_viewport.queue_redraw()


func _apply_showroom_snap_entry(entries: Array) -> void:
	## Display only the single best-matching baked frame (no multi-frame blur).
	if _analysis_blend_material == null or GemVisualRegistry == null:
		return
	if entries.is_empty():
		_clear_showroom_blend_layers()
		return
	var best: Dictionary = entries[0] if typeof(entries[0]) == TYPE_DICTIONARY else {}
	var tex: Texture2D = best.get("texture", null)
	if tex == null:
		_clear_showroom_blend_layers()
		return
	var snap_atlas: Texture2DArray = GemVisualRegistry.build_gameplay_sprite_atlas_from_textures(
		[tex, null, null, null]
	)
	_analysis_blend_material.set_shader_parameter("weights", Vector4(1.0, 0.0, 0.0, 0.0))
	_analysis_blend_material.set_shader_parameter("layer_index", Vector4.ZERO)
	_analysis_blend_material.set_shader_parameter("atlas", snap_atlas)
	_update_showroom_texture_size_uniform_atlas(snap_atlas)
	if _analysis_viewport != null:
		_analysis_viewport.queue_redraw()


func _snap_orientation_to_best_frame() -> void:
	## On drag release, snap _orientation to the exact baked quaternion of the
	## nearest frame so the next drag starts from a clean known position.
	if not _has_showroom_bake or GemVisualRegistry == null:
		return
	var q := _current_showroom_query_quaternion().normalized()
	var q_lookup := q.inverse() if _showroom_interaction_mode == 0 else q
	var entries := GemVisualRegistry.find_nearest_showroom_frames(SESSION_TILE_ID, q_lookup, 1)
	if entries.is_empty():
		return
	var best: Dictionary = entries[0] if typeof(entries[0]) == TYPE_DICTIONARY else {}
	var q_frame: Quaternion = best.get("orientation", Quaternion.IDENTITY)
	if _showroom_interaction_mode == 0:
		# Free arcball: _orientation.inverse() was the lookup key, so snap to inverse of frame q
		_orientation = q_frame.inverse().normalized()
	else:
		# Axis modes: orientation is used directly
		var axis_map := {1: Vector3.RIGHT, 2: Vector3.UP}
		var _ax: Vector3 = axis_map.get(_showroom_interaction_mode, Vector3.UP)
		# Extract the angle from the frame quaternion projected onto this axis
		# For simplicity, keep the current axis angle (the snap is mainly for free orbit)
		pass


func _update_showroom_texture_size_uniform_atlas(atlas: Texture2DArray) -> void:
	if _analysis_blend_material == null or _analysis_viewport == null:
		return
	var tex_sz := _analysis_viewport.size.max(Vector2.ONE)
	if atlas != null:
		tex_sz = Vector2(atlas.get_width(), atlas.get_height()).max(Vector2.ONE)
	_analysis_blend_material.set_shader_parameter("texture_size_px", tex_sz)


func _map_to_trackball(pixel: Vector2, center: Vector2, radius: float) -> Vector3:
	var p := (pixel - center) / maxf(radius, 1.0)
	var len_sq := p.x * p.x + p.y * p.y
	if len_sq <= 1.0:
		return Vector3(p.x, -p.y, sqrt(1.0 - len_sq))
	var inv_len := 1.0 / sqrt(len_sq)
	return Vector3(p.x * inv_len, -p.y * inv_len, 0.0)


func _current_showroom_query_quaternion() -> Quaternion:
	match _showroom_interaction_mode:
		1:
			return Quaternion(Vector3.RIGHT, deg_to_rad(_axis_angle_deg)).normalized()
		2:
			return Quaternion(Vector3.UP, deg_to_rad(_axis_angle_deg)).normalized()
		_:
			return _orientation.normalized()


func _update_showroom_display() -> void:
	if not _has_showroom_bake or GemVisualRegistry == null:
		_clear_showroom_blend_layers()
		return
	var q := _current_showroom_query_quaternion().normalized()
	# Free arcball: composition matches camera motion — compare using inverse rotation
	# vs baked view_basis quaternions. Axis tabs set absolute world-axis quaternions; no inverse.
	var q_lookup := q.inverse() if _showroom_interaction_mode == 0 else q
	# Filter to axis-specific frames for Pitch/Yaw modes; search all for Free Orbit.
	var filter := &""
	match _showroom_interaction_mode:
		1: filter = &"pitch"
		2: filter = &"yaw"
	var entries := GemVisualRegistry.find_nearest_showroom_frames(SESSION_TILE_ID, q_lookup, 1, filter)
	# Snap to best frame — no blending, avoids blur.
	_apply_showroom_snap_entry(entries)
	if _analysis_aspect != null:
		var px: float = ANALYSIS_PREVIEW_BASE_PX * _zoom
		_analysis_aspect.custom_minimum_size = Vector2(px, px)
	_on_analysis_viewport_resized()
	_refresh_showroom_debug_text(entries, q, q_lookup)
	_scroll_showroom_to_bottom()


func _refresh_showroom_debug_text(
	entries: Array,
	q_arcball: Quaternion = Quaternion.IDENTITY,
	q_lookup: Quaternion = Quaternion.IDENTITY,
) -> void:
	if _analysis_debug_label == null:
		return
	if _analysis_debug_checkbox == null or not _analysis_debug_checkbox.button_pressed:
		return
	var lines := PackedStringArray()
	lines.append("mode=%d  zoom=%.2f" % [_showroom_interaction_mode, _zoom])
	lines.append("arcball_q=(%.4f, %.4f, %.4f, %.4f)" % [q_arcball.x, q_arcball.y, q_arcball.z, q_arcball.w])
	lines.append("lookup_q=(%.4f, %.4f, %.4f, %.4f)" % [q_lookup.x, q_lookup.y, q_lookup.z, q_lookup.w])
	var i := 0
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = e
		lines.append(
			"  #%d w=%.4f d=%d r=%d tex=%s" % [
				i,
				float(ed.get("weight", 0.0)),
				int(ed.get("direction_index", -1)),
				int(ed.get("roll_index", -1)),
				"ok" if ed.get("texture", null) != null else "missing",
			]
		)
		i += 1
	_analysis_debug_label.text = "\n".join(lines)


func _make_analysis_draw_spinbox() -> SpinBox:
	_analysis_draw_spin = SpinBox.new()
	_analysis_draw_spin.min_value = 32.0
	_analysis_draw_spin.max_value = 512.0
	_analysis_draw_spin.step = 16.0
	_analysis_draw_spin.value = 128.0
	_analysis_draw_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	return _analysis_draw_spin


func _make_analysis_sample_spinbox() -> SpinBox:
	_analysis_sample_spin = SpinBox.new()
	_analysis_sample_spin.min_value = 1.0
	_analysis_sample_spin.max_value = 5.0
	_analysis_sample_spin.step = 1.0
	_analysis_sample_spin.value = 1.0
	_analysis_sample_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	return _analysis_sample_spin


func _make_showroom_bounces_spinbox() -> SpinBox:
	_showroom_bounces_spin = SpinBox.new()
	_showroom_bounces_spin.min_value = 1.0
	_showroom_bounces_spin.max_value = 24.0
	_showroom_bounces_spin.step = 1.0
	_showroom_bounces_spin.value = 12.0
	_showroom_bounces_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	return _showroom_bounces_spin


func _analysis_output_line() -> LineEdit:
	_analysis_output = LineEdit.new()
	_analysis_output.text = "user://gem_designer_analysis"
	_analysis_output.size_flags_horizontal = SIZE_EXPAND_FILL
	return _analysis_output


func _update_analysis_debug_visibility() -> void:
	var debug_visible := _analysis_debug_checkbox != null and _analysis_debug_checkbox.button_pressed
	if _analysis_debug_label != null:
		_analysis_debug_label.visible = debug_visible


func _make_preview_panel() -> Control:
	var box := VBoxContainer.new()
	_preview_tex = TextureRect.new()
	_preview_tex.custom_minimum_size = Vector2(256, 256)
	_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_preview_tex)
	_preview_stylize_checkbox = CheckBox.new()
	_preview_stylize_checkbox.text = "Apply stylization"
	_preview_stylize_checkbox.button_pressed = false
	_preview_stylize_checkbox.toggled.connect(func(_on: bool) -> void: _schedule_preview())
	box.add_child(_preview_stylize_checkbox)
	var settings_row := HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 8)
	var bounces_label := Label.new()
	bounces_label.text = "Bounces"
	bounces_label.add_theme_font_size_override("font_size", 12)
	bounces_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	settings_row.add_child(bounces_label)
	_preview_bounces_spin = SpinBox.new()
	_preview_bounces_spin.min_value = 1.0
	_preview_bounces_spin.max_value = 24.0
	_preview_bounces_spin.step = 1.0
	_preview_bounces_spin.value = 12.0
	_preview_bounces_spin.custom_minimum_size = Vector2(70, 0)
	_preview_bounces_spin.value_changed.connect(func(_v: float) -> void: _schedule_preview())
	settings_row.add_child(_preview_bounces_spin)
	var samples_label := Label.new()
	samples_label.text = "Samples"
	samples_label.add_theme_font_size_override("font_size", 12)
	samples_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	settings_row.add_child(samples_label)
	_preview_samples_spin = SpinBox.new()
	_preview_samples_spin.min_value = 1.0
	_preview_samples_spin.max_value = 5.0
	_preview_samples_spin.step = 1.0
	_preview_samples_spin.value = 1.0
	_preview_samples_spin.custom_minimum_size = Vector2(60, 0)
	_preview_samples_spin.value_changed.connect(func(_v: float) -> void: _schedule_preview())
	settings_row.add_child(_preview_samples_spin)
	box.add_child(settings_row)
	return box


func _labeled(text: String, ctrl: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86))
	v.add_child(l)
	ctrl.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_child(ctrl)
	return v


func _make_separator() -> Control:
	var h := HSeparator.new()
	h.custom_minimum_size = Vector2(0, 8)
	return h


func _fill_gem_dropdown() -> void:
	_gem_dropdown.clear()
	if GemVisualRegistry == null:
		return
	for id in GemVisualRegistry.get_visual_ids():
		var tier := 0
		if TileRegistry != null and TileRegistry.has_definitions():
			var def = TileRegistry.get_definition(id)
			if def != null:
				tier = def.tier
		_gem_dropdown.add_item("%s (T%d)" % [String(id), tier], 0)
		_gem_dropdown.set_item_metadata(_gem_dropdown.item_count - 1, id)


func _on_gem_selected(index: int) -> void:
	var id: StringName = _gem_dropdown.get_item_metadata(index)
	if _session.load_from_tile_id(id):
		_refresh_all()
		_reset_showroom_viewer()
		_status.text = "Loaded %s" % String(id)


func _on_load_file_pressed() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; GemVisualResource"])
	dlg.file_selected.connect(func(p: String):
		if _session.load_from_visual_path(p):
			_refresh_all()
			_reset_showroom_viewer()
			_status.text = "Loaded %s" % p
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _on_save_file_pressed() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; GemVisualResource"])
	dlg.file_selected.connect(func(p: String):
		var err := _session.save_to_path(p)
		_status.text = "Save %s" % ("ok" if err == OK else str(err))
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _on_add_modifier_pressed() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; GemCutModelModifier"])
	dlg.file_selected.connect(func(p: String):
		var res = load(p)
		if res is GemCutModelModifierScript:
			_session.cut_model_modifiers.append(res)
			_session.mark_geometry_dirty()
			_schedule_preview()
			_status.text = "Added modifier %s" % p
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _refresh_all() -> void:
	_session.compile_geometry(true)
	_rebuild_visual_inspector()
	_refresh_cut_json_text()
	_refresh_visual_json_text()
	_schedule_preview()


func _reset_showroom_viewer() -> void:
	_has_showroom_bake = false
	_orientation = Quaternion.IDENTITY
	_zoom = 1.0
	_axis_angle_deg = 0.0
	if GemVisualRegistry != null:
		GemVisualRegistry.set_showroom_bake_session(SESSION_TILE_ID, [])
	_clear_showroom_blend_layers()


func _refresh_cut_json_text() -> void:
	if _session.working_cut_spec == null:
		_cut_edit.text = "{}"
		return
	var d := _session.working_cut_spec.build_json_safe_contract_dict()
	_cut_edit.text = JSON.stringify(d, "\t")


func _on_apply_cut_json() -> void:
	var parsed = JSON.parse_string(_cut_edit.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status.text = "Cut JSON: expected object"
		return
	_session.apply_contract_dict_to_cut(parsed)
	_refresh_cut_json_text()
	_rebuild_visual_inspector()
	_schedule_preview()
	_status.text = "Cut applied"


func _refresh_visual_json_text() -> void:
	if _visual_json_edit == null:
		return
	var d := _session.get_visual_json_dict()
	_visual_json_edit.text = JSON.stringify(d, "\t")


func _on_apply_visual_json() -> void:
	var parsed = JSON.parse_string(_visual_json_edit.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status.text = "Visual JSON: expected object"
		return
	_session.apply_visual_json_dict(parsed)
	_rebuild_visual_inspector()
	_refresh_visual_json_text()
	_schedule_preview()
	_status.text = "Visual JSON applied"


func _rebuild_visual_inspector() -> void:
	for c in _visual_scroll.get_children():
		c.queue_free()
	_sentinel_widgets.clear()
	_prop_row_controls.clear()
	if _session.working_visual == null:
		return
	var vis: GemVisualResource = _session.working_visual
	var current_group := ""
	var current_subgroup := ""
	var group_container: VBoxContainer = _visual_scroll
	var prop_container: VBoxContainer = _visual_scroll

	for prop in vis.get_property_list():
		# Handle group headers (top-level sections).
		if prop.type == TYPE_NIL and (prop.usage & PROPERTY_USAGE_GROUP):
			current_group = String(prop.name)
			current_subgroup = ""
			if current_group == "Identity":
				group_container = null
				prop_container = null
				continue
			var section := _make_section_header(current_group, false)
			_visual_scroll.add_child(section.header)
			_visual_scroll.add_child(section.container)
			group_container = section.container
			prop_container = section.container
			continue

		# Handle subgroup headers (nested sections within a group).
		if prop.type == TYPE_NIL and (prop.usage & PROPERTY_USAGE_SUBGROUP):
			current_subgroup = String(prop.name)
			if group_container == null:
				continue
			var section := _make_section_header(current_subgroup, true)
			group_container.add_child(section.header)
			group_container.add_child(section.container)
			prop_container = section.container
			continue

		if prop_container == null:
			continue
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var n: String = prop.name
		if n.begins_with(&"resource_") or n == &"script":
			continue
		if n == &"cut_spec":
			var lbl := Label.new()
			lbl.text = "cut_spec: edit via Cut tab / base gem"
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
			prop_container.add_child(lbl)
			continue
		var val = vis.get(n)
		var display_group := current_subgroup if current_subgroup != "" else current_group
		var row := _make_property_row(n, prop, val, vis, display_group)
		if row:
			prop_container.add_child(row)
			_prop_row_controls[StringName(n)] = row
	# Initial dependency state update after building all rows.
	_update_dependency_states()


func _make_section_header(group_name: String, is_subgroup: bool) -> Dictionary:
	var is_collapsed: bool = _section_collapse_state.get(group_name,
		group_name in _DEFAULT_COLLAPSED_GROUPS)
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.visible = not is_collapsed

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)

	if not is_subgroup:
		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 4)
		sep.add_theme_color_override("separator", Color(0.25, 0.28, 0.35))
		header.add_child(sep)

	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "%s %s" % ["\u25bc" if not is_collapsed else "\u25b6", group_name]
	if is_subgroup:
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
		btn.add_theme_color_override("font_hover_color", Color(0.72, 0.76, 0.86))
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", 12)
		indent.add_child(btn)
		header.add_child(indent)
	else:
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		btn.add_theme_color_override("font_hover_color", Color(0.8, 0.85, 0.95))
		header.add_child(btn)

	btn.pressed.connect(func() -> void:
		var collapsed := container.visible
		container.visible = not collapsed
		_section_collapse_state[group_name] = collapsed
		btn.text = "%s %s" % ["\u25b6" if collapsed else "\u25bc", group_name]
	)

	return {"header": header, "container": container}


func _make_property_row(n: String, prop: Dictionary, val, vis: GemVisualResource, group_name: String) -> Control:
	var t: int = prop.type
	if t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_DICTIONARY:
		return null

	# Sentinel float properties get a compound "Auto" checkbox + slider widget.
	var sn := StringName(n)
	if t == TYPE_FLOAT and sn in _FLOAT_SENTINEL_PROPERTIES:
		return _make_sentinel_float_row(sn, val, vis, group_name)
	# Sentinel color properties get a compound "Auto" checkbox + color picker widget.
	if t == TYPE_COLOR and sn in _COLOR_SENTINEL_PROPERTIES:
		return _make_sentinel_color_row(sn, val, vis, group_name)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var name_l := Label.new()
	name_l.text = _display_name(n, group_name)
	name_l.custom_minimum_size = Vector2(160, 0)
	name_l.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	name_l.add_theme_font_size_override("font_size", 13)
	h.add_child(name_l)

	if t == TYPE_FLOAT:
		var range_info := _parse_range_hint(prop)
		if range_info.has_range:
			_add_float_slider_row(h, n, val, vis, range_info)
		else:
			var sb := SpinBox.new()
			sb.step = 0.01
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.min_value = -999999.0
			sb.max_value = 999999.0
			sb.value = float(val)
			sb.value_changed.connect(func(v: float): vis.set(n, v); _on_visual_prop_changed())
			sb.size_flags_horizontal = SIZE_EXPAND_FILL
			h.add_child(sb)
		return h

	if t == TYPE_INT:
		var enum_labels := _parse_enum_hint(prop)
		if not enum_labels.is_empty():
			var ob := OptionButton.new()
			for i in enum_labels.size():
				ob.add_item(enum_labels[i], i)
			ob.selected = int(val)
			ob.item_selected.connect(func(idx: int): vis.set(n, idx); _on_visual_prop_changed())
			ob.size_flags_horizontal = SIZE_EXPAND_FILL
			h.add_child(ob)
			return h
		var range_info := _parse_range_hint(prop)
		var sb2 := SpinBox.new()
		sb2.step = 1.0
		sb2.rounded = true
		if range_info.has_range:
			sb2.min_value = range_info.min_val
			sb2.max_value = range_info.max_val
			sb2.allow_greater = false
			sb2.allow_lesser = false
		else:
			sb2.allow_greater = true
			sb2.allow_lesser = true
			sb2.min_value = -2147483648.0
			sb2.max_value = 2147483647.0
		sb2.value = int(val)
		sb2.value_changed.connect(func(v: float): vis.set(n, int(v)); _on_visual_prop_changed())
		sb2.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(sb2)
		return h

	if t == TYPE_BOOL:
		var cb := CheckBox.new()
		cb.button_pressed = bool(val)
		cb.toggled.connect(func(on: bool): vis.set(n, on); _on_visual_prop_changed())
		h.add_child(cb)
		return h

	if t == TYPE_COLOR:
		var pb := ColorPickerButton.new()
		pb.color = val as Color
		pb.edit_alpha = StringName(n) in _ALPHA_EDIT_PROPERTIES
		pb.color_changed.connect(func(c: Color): vis.set(n, c); _on_visual_prop_changed())
		pb.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(pb)
		return h

	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		var le := LineEdit.new()
		le.text = String(val)
		le.text_changed.connect(func(s: String) -> void:
			if t == TYPE_STRING:
				vis.set(n, s)
			else:
				vis.set(n, StringName(s))
			_on_visual_prop_changed()
		)
		le.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(le)
		return h

	if t == TYPE_VECTOR2:
		var gv := _vec2_editor(val as Vector2, func(v: Vector2) -> void:
			vis.set(n, v)
			_on_visual_prop_changed()
		)
		gv.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(gv)
		return h

	if t == TYPE_VECTOR3:
		var gv3 := _vec3_editor(val as Vector3, func(v: Vector3) -> void:
			vis.set(n, v)
			_on_visual_prop_changed()
		)
		gv3.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(gv3)
		return h

	return null


func _add_float_slider_row(h: HBoxContainer, n: String, val, vis: GemVisualResource, range_info: Dictionary) -> void:
	var is_pct := _is_percentage_property(n, range_info)
	var is_log_shininess := (n == "shininess")
	var is_degrees := n.ends_with("_degrees")

	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(100, 0)

	var sb := SpinBox.new()
	sb.custom_minimum_size = Vector2(90, 0)
	sb.allow_greater = false
	sb.allow_lesser = false

	if is_log_shininess:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.005
		sb.min_value = range_info.min_val
		sb.max_value = range_info.max_val
		sb.step = 1.0
		sb.suffix = " exp"
		slider.value = _shininess_to_slider(float(val))
		sb.value = float(val)
	elif is_pct:
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		sb.min_value = range_info.min_val * 100.0
		sb.max_value = range_info.max_val * 100.0
		sb.step = 1.0
		sb.suffix = "%"
		slider.value = float(val) * 100.0
		sb.value = float(val) * 100.0
	else:
		slider.min_value = range_info.min_val
		slider.max_value = range_info.max_val
		slider.step = range_info.step
		sb.min_value = range_info.min_val
		sb.max_value = range_info.max_val
		sb.step = range_info.step
		slider.value = float(val)
		sb.value = float(val)
		if is_degrees:
			sb.suffix = "\u00b0"

	slider.value_changed.connect(func(v: float) -> void:
		if _updating_property:
			return
		_updating_property = true
		if is_log_shininess:
			var actual := _slider_to_shininess(v)
			sb.value = actual
			vis.set(n, actual)
		elif is_pct:
			sb.value = v
			vis.set(n, v / 100.0)
		else:
			sb.value = v
			vis.set(n, v)
		_on_visual_prop_changed()
		_updating_property = false
	)

	sb.value_changed.connect(func(v: float) -> void:
		if _updating_property:
			return
		_updating_property = true
		if is_log_shininess:
			slider.value = _shininess_to_slider(v)
			vis.set(n, v)
		elif is_pct:
			slider.value = v
			vis.set(n, v / 100.0)
		else:
			slider.value = v
			vis.set(n, v)
		_on_visual_prop_changed()
		_updating_property = false
	)

	h.add_child(slider)
	h.add_child(sb)


# ---------------------------------------------------------------------------
# Sentinel compound widgets
# ---------------------------------------------------------------------------

func _make_sentinel_float_row(prop_name: StringName, val, vis: GemVisualResource, group_name: String) -> Control:
	var cfg: Dictionary = _FLOAT_SENTINEL_PROPERTIES[prop_name]
	var sentinel_val: float = cfg.sentinel
	var auto_key: String = cfg.auto_key
	var override_min: float = cfg.override_min
	var override_max: float = cfg.override_max
	var override_step: float = cfg.get("override_step", 0.01)

	var is_auto: bool = float(val) <= sentinel_val + 0.001

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var name_l := Label.new()
	name_l.text = _display_name(String(prop_name), group_name)
	name_l.custom_minimum_size = Vector2(160, 0)
	name_l.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	name_l.add_theme_font_size_override("font_size", 13)
	h.add_child(name_l)

	var auto_cb := CheckBox.new()
	auto_cb.text = "Auto"
	auto_cb.button_pressed = is_auto
	auto_cb.add_theme_font_size_override("font_size", 11)
	h.add_child(auto_cb)

	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(80, 0)
	slider.min_value = override_min
	slider.max_value = override_max
	slider.step = override_step

	var sb := SpinBox.new()
	sb.custom_minimum_size = Vector2(90, 0)
	sb.allow_greater = false
	sb.allow_lesser = false
	sb.min_value = override_min
	sb.max_value = override_max
	sb.step = override_step

	# Resolve the effective auto value from the preset.
	var defaults := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
	var auto_val: float = defaults.get(auto_key, override_min)

	if is_auto:
		slider.value = auto_val
		sb.value = auto_val
		slider.editable = false
		sb.editable = false
		slider.modulate.a = 0.45
		sb.modulate.a = 0.45
	else:
		slider.value = float(val)
		sb.value = float(val)

	auto_cb.toggled.connect(func(on: bool) -> void:
		if _updating_property:
			return
		_updating_property = true
		if on:
			vis.set(prop_name, sentinel_val)
			var defs := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
			var av: float = defs.get(auto_key, override_min)
			slider.value = av
			sb.value = av
			slider.editable = false
			sb.editable = false
			slider.modulate.a = 0.45
			sb.modulate.a = 0.45
		else:
			var defs := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
			var av: float = defs.get(auto_key, override_min)
			slider.value = av
			sb.value = av
			vis.set(prop_name, av)
			slider.editable = true
			sb.editable = true
			slider.modulate.a = 1.0
			sb.modulate.a = 1.0
		_on_visual_prop_changed()
		_updating_property = false
	)

	slider.value_changed.connect(func(v: float) -> void:
		if _updating_property:
			return
		_updating_property = true
		sb.value = v
		vis.set(prop_name, v)
		_on_visual_prop_changed()
		_updating_property = false
	)

	sb.value_changed.connect(func(v: float) -> void:
		if _updating_property:
			return
		_updating_property = true
		slider.value = v
		vis.set(prop_name, v)
		_on_visual_prop_changed()
		_updating_property = false
	)

	h.add_child(slider)
	h.add_child(sb)

	_sentinel_widgets[prop_name] = {
		"checkbox": auto_cb,
		"slider": slider,
		"spinbox": sb,
		"auto_key": auto_key,
		"sentinel_val": sentinel_val,
		"override_min": override_min,
	}
	return h


func _make_sentinel_color_row(prop_name: StringName, val, vis: GemVisualResource, group_name: String) -> Control:
	var cfg: Dictionary = _COLOR_SENTINEL_PROPERTIES[prop_name]
	var auto_key: String = cfg.auto_key
	var current_color: Color = val as Color
	var is_auto: bool = current_color.a <= 0.01

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var name_l := Label.new()
	name_l.text = _display_name(String(prop_name), group_name)
	name_l.custom_minimum_size = Vector2(160, 0)
	name_l.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	name_l.add_theme_font_size_override("font_size", 13)
	h.add_child(name_l)

	var auto_cb := CheckBox.new()
	auto_cb.text = "Auto"
	auto_cb.button_pressed = is_auto
	auto_cb.add_theme_font_size_override("font_size", 11)
	h.add_child(auto_cb)

	var pb := ColorPickerButton.new()
	pb.edit_alpha = false
	pb.size_flags_horizontal = SIZE_EXPAND_FILL

	var defaults := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
	var auto_color: Color = defaults.get(auto_key, Color.WHITE)

	if is_auto:
		pb.color = auto_color
		pb.disabled = true
		pb.modulate.a = 0.45
	else:
		pb.color = current_color

	auto_cb.toggled.connect(func(on: bool) -> void:
		if _updating_property:
			return
		_updating_property = true
		if on:
			vis.set(prop_name, Color.TRANSPARENT)
			var defs := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
			var ac: Color = defs.get(auto_key, Color.WHITE)
			pb.color = ac
			pb.disabled = true
			pb.modulate.a = 0.45
		else:
			var defs := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
			var ac: Color = defs.get(auto_key, Color.WHITE)
			pb.color = ac
			vis.set(prop_name, ac)
			pb.disabled = false
			pb.modulate.a = 1.0
		_on_visual_prop_changed()
		_updating_property = false
	)

	pb.color_changed.connect(func(c: Color) -> void:
		if _updating_property:
			return
		_updating_property = true
		vis.set(prop_name, c)
		_on_visual_prop_changed()
		_updating_property = false
	)

	h.add_child(pb)

	_sentinel_widgets[prop_name] = {
		"checkbox": auto_cb,
		"color_picker": pb,
		"auto_key": auto_key,
	}
	return h


## Refresh the displayed auto values for all sentinel widgets in auto mode.
## Called when any property changes (preset, scattering, roughness, etc. can
## affect the resolved auto value).
func _refresh_sentinel_auto_values() -> void:
	if _session.working_visual == null:
		return
	var vis: GemVisualResource = _session.working_visual
	var defaults := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)

	for prop_name in _sentinel_widgets:
		var w: Dictionary = _sentinel_widgets[prop_name]
		var auto_key: String = w.auto_key
		if w.has("checkbox") and w.checkbox is CheckBox:
			if not w.checkbox.button_pressed:
				continue  # Not in auto mode — skip.
		if w.has("slider") and w.slider is HSlider:
			var cb: CheckBox = w.checkbox
			if cb.button_pressed:
				_updating_property = true
				var av: float = defaults.get(auto_key, w.get("override_min", 0.0))
				w.slider.value = av
				w.spinbox.value = av
				_updating_property = false
		elif w.has("color_picker") and w.color_picker is ColorPickerButton:
			var cb: CheckBox = w.checkbox
			if cb.button_pressed:
				_updating_property = true
				var ac: Color = defaults.get(auto_key, Color.WHITE)
				w.color_picker.color = ac
				_updating_property = false


# ---------------------------------------------------------------------------
# Dependency dimming
# ---------------------------------------------------------------------------

func _evaluate_prop_condition(vis: GemVisualResource, prop_name: StringName, condition: String) -> bool:
	var effective_val: float
	if condition == "> 0 (effective)":
		# For sentinel properties, check whether the effective value (after preset fallback) is > 0.
		if prop_name in _FLOAT_SENTINEL_PROPERTIES:
			var raw: float = vis.get(prop_name)
			var cfg: Dictionary = _FLOAT_SENTINEL_PROPERTIES[prop_name]
			if raw <= cfg.sentinel + 0.001:
				# Auto mode: resolve the preset default.
				var defaults := GemEnvironmentPresetsScript.resolve_effective_defaults(vis)
				effective_val = defaults.get(cfg.auto_key, 0.0)
			else:
				effective_val = raw
		else:
			effective_val = float(vis.get(prop_name))
		return effective_val > 0.001
	var raw_val = vis.get(prop_name)
	if condition == "> 0":
		return float(raw_val) > 0.001
	if condition == "!= 0":
		return int(raw_val) != 0
	return true


func _update_dependency_states() -> void:
	if _session.working_visual == null:
		return
	var vis: GemVisualResource = _session.working_visual
	for prop_name in _prop_row_controls:
		var row: Control = _prop_row_controls[prop_name]
		if prop_name not in _DEPENDENCY_RULES:
			row.modulate.a = 1.0
			row.tooltip_text = ""
			continue
		var rule: Dictionary = _DEPENDENCY_RULES[prop_name]
		var requires: Dictionary = rule.requires
		var active := true
		for req_prop in requires:
			if not _evaluate_prop_condition(vis, req_prop, requires[req_prop]):
				active = false
				break
		if active:
			row.modulate.a = 1.0
			row.tooltip_text = ""
		else:
			row.modulate.a = 0.4
			row.tooltip_text = rule.reason


static func _shininess_to_slider(value: float) -> float:
	return log(maxf(value, 1.0)) / log(256.0)


static func _slider_to_shininess(slider_val: float) -> float:
	return roundf(pow(256.0, clampf(slider_val, 0.0, 1.0)))


static func _parse_range_hint(prop: Dictionary) -> Dictionary:
	if prop.hint != PROPERTY_HINT_RANGE or prop.hint_string == "":
		return {"has_range": false}
	var parts: PackedStringArray = prop.hint_string.split(",")
	var result := {
		"has_range": true,
		"min_val": float(parts[0].strip_edges()) if parts.size() > 0 else 0.0,
		"max_val": float(parts[1].strip_edges()) if parts.size() > 1 else 1.0,
		"step": float(parts[2].strip_edges()) if parts.size() > 2 else 0.01,
	}
	return result


static func _parse_enum_hint(prop: Dictionary) -> PackedStringArray:
	if prop.hint != PROPERTY_HINT_ENUM or prop.hint_string == "":
		return PackedStringArray()
	return prop.hint_string.split(",")


static func _display_name(prop_name: String, group_name: String) -> String:
	var label := prop_name
	var prefix: String = _GROUP_PREFIX_MAP.get(group_name, "")
	if prefix != "" and label.begins_with(prefix):
		label = label.substr(prefix.length())
	return label.replace("_", " ").capitalize()


static func _is_percentage_property(prop_name: String, range_info: Dictionary) -> bool:
	if not range_info.has_range:
		return false
	if range_info.min_val < 0.0 or not is_equal_approx(range_info.max_val, 1.0):
		return false
	if StringName(prop_name) in _PERCENTAGE_EXCLUSIONS:
		return false
	return true


func _vec2_editor(v: Vector2, setter: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var sbx := SpinBox.new()
	var sby := SpinBox.new()
	sbx.step = 0.01
	sby.step = 0.01
	sbx.prefix = "x"
	sby.prefix = "y"
	sbx.value = v.x
	sby.value = v.y
	var push := func() -> void:
		setter.call(Vector2(sbx.value, sby.value))
	sbx.value_changed.connect(func(_v: float) -> void: push.call())
	sby.value_changed.connect(func(_v: float) -> void: push.call())
	hb.add_child(sbx)
	hb.add_child(sby)
	return hb


func _vec3_editor(v: Vector3, setter: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var sbx := SpinBox.new()
	var sby := SpinBox.new()
	var sbz := SpinBox.new()
	for sb in [sbx, sby, sbz]:
		sb.step = 0.01
	sbx.prefix = "x"
	sby.prefix = "y"
	sbz.prefix = "z"
	sbx.value = v.x
	sby.value = v.y
	sbz.value = v.z
	var push := func() -> void:
		setter.call(Vector3(sbx.value, sby.value, sbz.value))
	sbx.value_changed.connect(func(_v: float) -> void: push.call())
	sby.value_changed.connect(func(_v: float) -> void: push.call())
	sbz.value_changed.connect(func(_v: float) -> void: push.call())
	hb.add_child(sbx)
	hb.add_child(sby)
	hb.add_child(sbz)
	return hb


func _on_visual_prop_changed() -> void:
	_session.mark_visual_dirty()
	_refresh_sentinel_auto_values()
	_update_dependency_states()
	_schedule_preview()


func _schedule_preview() -> void:
	_preview_gen += 1
	_preview_timer.stop()
	_preview_timer.start()


func _on_preview_timer_timeout() -> void:
	_start_preview_trace(_preview_gen)


func _start_preview_trace(gen: int) -> void:
	if _preview_thread != null and _preview_thread.is_started():
		return
	_session.compile_geometry(false)
	var model = _session.get_cached_model()
	var cut = _session.get_cached_projected_cut()
	var vis_snap: GemVisualResource = _session.working_visual.duplicate(true)
	if model == null or cut == null or vis_snap == null:
		_status.text = "Preview: invalid geometry"
		return
	var mesh = GemMeshGeneratorsScript.generate_from_model(model)
	if mesh == null:
		_status.text = "Preview: mesh failed"
		return
	var req := GemVisualRegistry.build_designer_preview_crown_request(
		SESSION_TILE_ID,
		vis_snap,
		model,
		cut,
		PREVIEW_SIZE,
		PREVIEW_SIZE
	)
	req["mesh_includes_cut_rotation"] = true
	var preview_bounces := 12
	if _preview_bounces_spin != null:
		preview_bounces = int(_preview_bounces_spin.value)
	var preview_samples := 1
	if _preview_samples_spin != null:
		preview_samples = int(_preview_samples_spin.value)
	var pack := {
		"gen": gen,
		"mesh": mesh,
		"visual": vis_snap,
		"request": req,
		"weak_self": weakref(self),
		"skip_stylize": not (_preview_stylize_checkbox != null and _preview_stylize_checkbox.button_pressed),
		"max_trace_bounces": preview_bounces,
		"sample_count": preview_samples,
		"environment_profile": GemEnvironmentPresetsScript.resolve_preset(vis_snap.optics_environment_preset),
	}
	_preview_thread = Thread.new()
	var err := _preview_thread.start(Callable(self, "_preview_thread_body").bind(pack))
	if err != OK:
		_preview_thread = null
		_status.text = "Preview thread start failed"
		return
	set_process(true)


func _process(_delta: float) -> void:
	if _preview_thread == null or not _preview_thread.is_started():
		return
	if not _preview_thread.is_alive():
		_preview_thread.wait_to_finish()
		_preview_thread = null
		set_process(false)


func _preview_thread_body(pack: Dictionary) -> void:
	var gen := int(pack.get("gen", 0))
	var mesh: GemMeshResource = pack.get("mesh", null)
	var visual: GemVisualResource = pack.get("visual", null)
	var req: Dictionary = pack.get("request", {}).duplicate(true)
	var w: WeakRef = pack.get("weak_self", null)
	if mesh == null or visual == null or w == null:
		return
	var tracer = OfflineGemBakeJobScript.create_tracer()
	req["mesh_resource"] = mesh
	req["sample_count"] = int(pack.get("sample_count", 1))
	req["max_trace_bounces"] = int(pack.get("max_trace_bounces", 12))
	req["skip_stylize"] = bool(pack.get("skip_stylize", true))
	var env_profile = pack.get("environment_profile", null)
	if env_profile != null:
		req["environment_profile"] = env_profile
	var img: Image = tracer.trace_to_image(mesh, visual, req)
	var node = w.get_ref()
	if node != null:
		node.call_deferred("_on_preview_image_ready", gen, img)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _preview_thread != null and _preview_thread.is_started():
			_preview_thread.wait_to_finish()


func _on_preview_image_ready(gen: int, img: Image) -> void:
	if gen != _preview_gen:
		return
	if img == null:
		_status.text = "Preview trace failed"
		return
	var tex := ImageTexture.create_from_image(img)
	_preview_tex.texture = tex
	_status.text = "Preview updated"


func _get_showroom_output_root() -> String:
	if _analysis_output != null:
		var out := String(_analysis_output.text).strip_edges()
		if not out.is_empty():
			return out
	return "user://gem_designer_analysis"


func _on_reload_showroom_session() -> void:
	if _bake_in_progress:
		return
	var out := _get_showroom_output_root()
	var manifest_path := out + "/" + GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME
	_status.text = "Reading manifest…"
	_bake_progress.visible = true
	_bake_progress_label.visible = true
	_bake_progress.value = 0.0
	_bake_progress_label.text = "Reading manifest…"
	_bake_in_progress = true
	_bake_btn.disabled = true
	await get_tree().process_frame
	var entries := _read_manifest_entries(manifest_path)
	if entries.is_empty():
		_status.text = "No previous session found at %s" % manifest_path
		_bake_progress.visible = false
		_bake_progress_label.visible = false
		_bake_in_progress = false
		_bake_btn.disabled = false
		return
	var showroom_entries: Array = []
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("variant_type", "")) == "showroom":
			showroom_entries.append(e)
	if showroom_entries.is_empty():
		_status.text = "Manifest has no showroom entries"
		_bake_progress.visible = false
		_bake_progress_label.visible = false
		_bake_in_progress = false
		_bake_btn.disabled = false
		return
	var total := showroom_entries.size()
	_bake_progress_label.text = "Loading %d textures…" % total
	_bake_progress.value = 0.0
	await get_tree().process_frame
	_load_showroom_entries(showroom_entries)
	_bake_progress.value = 1.0
	_bake_progress_label.text = "Loaded %d frames" % total
	await get_tree().process_frame
	_bake_progress.visible = false
	_bake_progress_label.visible = false
	_bake_in_progress = false
	_bake_btn.disabled = false
	_status.text = "Reloaded %d showroom frames from manifest" % total


func _read_manifest_entries(manifest_path: String) -> Array:
	var gpath := ProjectSettings.globalize_path(manifest_path)
	if not FileAccess.file_exists(gpath):
		return []
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var manifest: Dictionary = parsed
	return manifest.get("entries", [])


func _on_run_showroom_bake() -> void:
	if _bake_in_progress:
		return
	_session.compile_geometry(true)
	var model = _session.get_cached_model()
	var cut = _session.get_cached_projected_cut()
	var vis_snap: GemVisualResource = _session.working_visual.duplicate(true)
	if model == null or cut == null:
		_status.text = "Showroom: invalid geometry"
		return
	var draw_sz := Vector2i(int(_analysis_draw_spin.value), int(_analysis_draw_spin.value))
	var axis_steps := int(_showroom_axis_steps_spin.value) if _showroom_axis_steps_spin != null else 36
	var include_orbit := _showroom_orbit_checkbox != null and _showroom_orbit_checkbox.button_pressed
	var dir_n := int(_showroom_dir_spin.value) if include_orbit else 0
	var roll_n := int(_showroom_roll_spin.value) if include_orbit else 0
	var opts := {
		"include_lighting": false,
		"include_rotation_suite": false,
		"include_showroom": include_orbit,
		"showroom_axis_steps": axis_steps,
		"showroom_direction_count": dir_n,
		"showroom_roll_steps": roll_n,
	}
	var raw: Array = GemVisualRegistry.build_explicit_bake_requests(
		SESSION_TILE_ID,
		vis_snap,
		model,
		cut,
		draw_sz,
		draw_sz,
		opts
	)
	if raw.is_empty():
		_status.text = "Showroom: no requests"
		return
	_bake_in_progress = true
	_bake_btn.disabled = true
	_bake_progress.visible = true
	_bake_progress_label.visible = true
	_bake_progress.value = 0.0
	_bake_progress_label.text = "Preparing %d views…" % raw.size()
	_status.text = "Baking %d views…" % raw.size()
	var job := OfflineGemBakeJobScript.new()
	var out := _get_showroom_output_root()
	var manifest_path := out + "/" + GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME
	var manifest_global := ProjectSettings.globalize_path(manifest_path)
	if FileAccess.file_exists(manifest_global):
		DirAccess.remove_absolute(manifest_global)
	var batch_opts := {
		"output_root": out,
		"draw_size": draw_sz,
		"sample_count": int(_analysis_sample_spin.value),
		"max_trace_bounces": int(_showroom_bounces_spin.value) if _showroom_bounces_spin != null else 12,
		"skip_stylize": not (_showroom_stylize_checkbox != null and _showroom_stylize_checkbox.button_pressed),
	}
	job.progress_updated.connect(_on_showroom_bake_progress)
	var result: Dictionary = await job.run_explicit_request_batch_async(self, raw, draw_sz, batch_opts)
	job.progress_updated.disconnect(_on_showroom_bake_progress)
	_bake_in_progress = false
	_bake_btn.disabled = false
	_bake_progress.visible = false
	_bake_progress_label.visible = false
	var entries: Array = result.get("entries", [])
	_load_showroom_entries(entries)
	_status.text = "Showroom bake: %s (%d entries)" % [String(result.get("status", "?")), entries.size()]


func _on_showroom_bake_progress(p: Dictionary) -> void:
	var stage := String(p.get("stage", ""))
	var completed := int(p.get("completed", 0))
	var total := int(p.get("total", 0))
	if total > 0:
		_bake_progress.value = float(completed) / float(total)
	if stage == "baked" or stage == "complete":
		_bake_progress_label.text = "%d / %d views" % [completed, total]
		_status.text = "Baking… %d/%d" % [completed, total]
	elif stage == "queued":
		_bake_progress_label.text = "Queued %d views" % total
	elif stage == "baking":
		_bake_progress_label.text = "Tracing %d / %d…" % [completed + 1, total]


func _load_showroom_entries(entries: Array) -> void:
	var showroom_entries: Array = []
	var has_orbit := false
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String(e.get("variant_type", "")) != "showroom":
			continue
		showroom_entries.append(e)
		if String(e.get("showroom_frame_type", "")) == "orbit":
			has_orbit = true
	if GemVisualRegistry != null:
		GemVisualRegistry.set_showroom_bake_session(SESSION_TILE_ID, showroom_entries)
	_has_showroom_bake = not showroom_entries.is_empty()
	_has_orbit_bake = has_orbit
	_update_free_orbit_availability()
	_orientation = Quaternion.IDENTITY
	_zoom = 1.0
	_axis_angle_deg = 0.0
	_analysis_viewport.rotation = 0.0
	_update_showroom_display()


func _update_free_orbit_availability() -> void:
	if _free_orbit_btn == null:
		return
	_free_orbit_btn.disabled = not _has_orbit_bake
	# If Free Orbit was selected but orbit data is gone, switch to Pitch.
	if _showroom_interaction_mode == 0 and not _has_orbit_bake:
		_showroom_interaction_mode = 1
		if _showroom_mode_row != null:
			for c in _showroom_mode_row.get_children():
				if c is Button:
					var m := int(c.get_meta("showroom_mode", -1))
					(c as Button).set_pressed_no_signal(m == 1)


func _on_analysis_gui_input(event: InputEvent) -> void:
	const ZOOM_MIN := 0.25
	const ZOOM_MAX := 4.0
	const ZOOM_STEP := 0.1
	const ORBIT_SENSITIVITY := 0.007
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_update_showroom_display()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_update_showroom_display()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_active = true
				_last_drag = mb.position
			else:
				_drag_active = false
				_snap_orientation_to_best_frame()
				_update_showroom_display()
	elif event is InputEventMouseMotion and _drag_active:
		var mm := event as InputEventMouseMotion
		var center := _analysis_viewport.size * 0.5
		var _radius := minf(center.x, center.y) * 0.95
		if _showroom_interaction_mode != 0:
			# Use whichever mouse axis has the larger delta for smooth diagonal drags.
			var dx := mm.relative.x * 0.35
			var dy := -mm.relative.y * 0.35
			if _invert_x:
				dx = -dx
			if _invert_y:
				dy = -dy
			var axis_delta := dx if absf(dx) >= absf(dy) else dy
			_axis_angle_deg = wrapf(_axis_angle_deg - axis_delta, 0.0, 360.0)
			_last_drag = mm.position
			_update_showroom_display()
			return
		if mm.shift_pressed:
			var roll_delta := mm.relative.x * 0.01
			if _invert_x:
				roll_delta = -roll_delta
			var view_axis := (_orientation * Vector3.BACK).normalized()
			_orientation = (Quaternion(view_axis, roll_delta) * _orientation).normalized()
		else:
			# Relative-motion orbit: unlimited rotation, no 90-degree stall.
			# Rotate around VIEW-SPACE axes (screen up / screen right) so drag
			# direction always matches visual rotation regardless of current tilt.
			var dx := mm.relative.x * ORBIT_SENSITIVITY
			var dy := mm.relative.y * ORBIT_SENSITIVITY
			if _invert_x:
				dx = -dx
			if _invert_y:
				dy = -dy
			var screen_up := (_orientation * Vector3.UP).normalized()
			var screen_right := (_orientation * Vector3.RIGHT).normalized()
			var qy := Quaternion(screen_up, -dx)
			var qx := Quaternion(screen_right, dy)
			_orientation = (qy * qx * _orientation).normalized()
		_last_drag = mm.position
		_update_showroom_display()
