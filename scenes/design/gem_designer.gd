extends Control

## Runtime gem designer: edit visual + cut spec, live traced preview, showroom bake + arcball viewer.

const SESSION_TILE_ID := &"gem_designer_session"
const ANALYSIS_PREVIEW_BASE_PX := 320.0
const GAMEPLAY_BLEND_SHADER := preload("res://scenes/tile/gameplay_sprite_blend.gdshader")
const PREVIEW_SIZE := Vector2i(256, 256)
const DEBOUNCE_SEC := 1.0

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemBakeStylizerScript = preload("res://core/visuals/gem_bake_stylizer.gd")
const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const GemViewSphereSamplingScript = preload("res://core/visuals/gem_view_sphere_sampling.gd")
const GemCutModelModifierScript = preload("res://resources/visuals/gem_cut_model_modifier.gd")
const SpectrumCurveEditorScript = preload("res://scenes/design/spectrum_curve_editor.gd")
const CutProfileCanvasScript = preload("res://scenes/design/cut_profile_canvas.gd")
const ProductionBakeProfileScript = preload("res://tools/production_bake_profile.gd")

const GAMEPLAY_BAKE_PROFILE_PATH := "res://config/bake_profiles/gameplay.json"
const CUT_SPECS_DIR := "res://data/visuals/cut_specs"

var _session: GemDesignSession

var _gem_dropdown: OptionButton
var _preview_tex: TextureRect
var _preview_timer: Timer
var _preview_gen := 0
## Generation of the trace currently running in `_preview_thread` (-1 = none). Used to chain
## a new bake when edits supersede during an in-flight trace (native trace cannot be cancelled).
var _preview_inflight_gen: int = -1
var _preview_thread: Thread
var _preview_activity_label: Label
var _preview_activity_bar: ProgressBar
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
## Shared trace controls (preview + showroom + debounced trace enrichment).
var _trace_spp_spin: SpinBox
var _trace_samples_spin: SpinBox
var _trace_stylize_checkbox: CheckBox
var _trace_match_gameplay_checkbox: CheckBox
var _trace_adaptive_spp_checkbox: CheckBox
var _trace_production_profile_checkbox: CheckBox
var _spectrum_editor: Control
var _spectrum_y_max_spin: SpinBox
var _gauss_center_spin: SpinBox
var _gauss_sigma_spin: SpinBox
var _gauss_strength_spin: SpinBox
var _absorption_edit_mode: OptionButton
var _mineral_path_edit: LineEdit
var _cut_spec_dropdown: OptionButton
var _cut_restore_btn: Button
var _cut_use_btn: Button
var _cut_edit_status: Label
var _cut_ring_option: OptionButton
var _cut_profile_canvas: Control
var _cut_height_spin: SpinBox
var _cut_rose_spin: SpinBox
var _cut_symm_check: CheckBox
var _cut_sector_label: Label
var _updating_cut_metrics: bool = false
var _save_mineral_btn: Button
var _restore_mineral_btn: Button
var _spectrum_source_label: Label
var _visual_tab_root: VBoxContainer
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

## Tracks all property row Controls keyed by property name (for dependency dimming).
var _prop_row_controls: Dictionary = {}

# ---------------------------------------------------------------------------
# Dependency rules: property -> { requires: { prop: condition }, reason: String }
# Condition strings: "> 0", "!= 0"
# ---------------------------------------------------------------------------
const _DEPENDENCY_RULES := {
	&"gradient_mode": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"gradient_angle_degrees": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"gradient_color": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"gradient_zone_spectrum": { "requires": { &"gradient_strength": "> 0" }, "reason": "Requires gradient strength > 0" },
	&"phenomenon_angle_degrees": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
	&"phenomenon_sharpness": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
	&"phenomenon_color": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
	&"phenomenon_zone_spectrum": { "requires": { &"phenomenon_strength": "> 0" }, "reason": "Requires phenomenon strength > 0" },
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
	&"stylize_visual_quality": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_haze": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_brilliance": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_shadow_lift": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_contrast": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_vibrance": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_clarity": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_specular_punch": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_edge_definition": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_bloom_gain": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_bloom_threshold": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_warmth": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_hue_shift": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_lift_r": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_lift_g": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_lift_b": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_gamma_r": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_gamma_g": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_gamma_b": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_gain_r": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_gain_g": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
	&"stylize_gain_b": { "requires": { &"stylize_mix": "> 0" }, "reason": "Requires stylize mix > 0" },
}

const _PERCENTAGE_EXCLUSIONS := [
	&"stylize_shadow_lift", &"stylize_bloom_threshold",
	&"stylize_warmth", &"stylize_hue_shift",
]
const _ALPHA_EDIT_PROPERTIES := [
	&"gradient_color", &"phenomenon_color", &"edge_color",
	&"material_secondary_color",
	&"material_tertiary_color", &"reactive_color", &"reactive_secondary_color",
]
const _DEFAULT_COLLAPSED_GROUPS := [
	"Traced Optics", "Stylization", "Color Grading (Advanced)", "Detailing",
	"Denoising", "Cut Quality", "Surface Quality",
]
const _GROUP_PREFIX_MAP := {
	"Surface Field": "surface_pattern_",
	"Volume Field": "volume_pattern_",
	"Angle Reactive": "reactive_",
	"Traced Optics": "optics_",
	"Camera": "optics_",
	"Environment": "optics_",
	"Stylization": "stylize_",
	"Gradient": "gradient_",
	"Phenomenon": "phenomenon_",
	"Edge Rendering": "edge_",
}

## Dim when material_mode is faceted transparent (pattern / opaque controls).
const _MATERIAL_MODE_PATTERN_ONLY_PROPS: Array[StringName] = [
	&"material_secondary_color", &"material_tertiary_color", &"use_texture", &"color_texture",
	&"texture_blend", &"texture_zoom", &"texture_offset", &"texture_facet_warp",
	&"surface_pattern_type", &"surface_pattern_mix", &"surface_pattern_scale",
	&"surface_pattern_rotation_degrees", &"surface_pattern_density", &"surface_pattern_contrast",
	&"surface_pattern_warp_strength", &"surface_pattern_warp_scale",
	&"surface_pattern_specular_variation", &"surface_pattern_roughness_variation",
	&"volume_pattern_type", &"volume_pattern_mix", &"volume_pattern_scale", &"volume_pattern_axis",
	&"volume_pattern_density", &"volume_pattern_contrast", &"volume_pattern_warp_strength",
	&"volume_pattern_warp_scale", &"volume_absorption_variation", &"volume_scattering_variation",
	&"reactive_effect_type", &"reactive_strength", &"reactive_color", &"reactive_secondary_color",
	&"reactive_sharpness", &"reactive_density", &"reactive_scale", &"reactive_axis",
]

## Dim when NOT faceted transparent (zoning / angle phenomenon — tracer uses spectra or legacy RGB).
const _MATERIAL_MODE_FACETED_TRANSPARENT_ONLY_PROPS: Array[StringName] = [
	&"gradient_color", &"gradient_zone_spectrum", &"gradient_strength", &"gradient_mode", &"gradient_angle_degrees",
	&"phenomenon_color", &"phenomenon_zone_spectrum", &"phenomenon_strength", &"phenomenon_angle_degrees",
	&"phenomenon_sharpness",
]

const SPECTRUM_TARGET_MINERAL_ABSORPTION := 0
const SPECTRUM_TARGET_GEM_ABSORPTION_OVERRIDE := 1
const SPECTRUM_TARGET_GRADIENT_ZONE := 2
const SPECTRUM_TARGET_PHENOMENON_ZONE := 3


func _ready() -> void:
	_session = GemDesignSession.new()
	_session.geometry_changed.connect(_on_session_geometry_changed)
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

	left.add_child(_labeled("Trace settings (preview + showroom)", _make_shared_trace_settings_group()))

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

	_visual_tab_root = VBoxContainer.new()
	_visual_tab_root.size_flags_vertical = SIZE_EXPAND_FILL
	_visual_tab_root.size_flags_horizontal = SIZE_EXPAND_FILL
	_visual_tab_root.add_theme_constant_override("separation", 8)
	tabs.add_child(_visual_tab_root)
	tabs.set_tab_title(_visual_tab_root.get_index(), "Visual")

	_build_mineral_and_spectrum_block(_visual_tab_root)

	var visual_panel := ScrollContainer.new()
	visual_panel.size_flags_vertical = SIZE_EXPAND_FILL
	visual_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	visual_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_visual_tab_root.add_child(visual_panel)

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
	tabs.set_tab_title(cut_panel.get_index(), "Cut")

	_build_cut_tab_header(cut_panel)

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
	var trace_hint := Label.new()
	trace_hint.text = "SPP, MSAA, and stylization use Trace settings in the left column."
	trace_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trace_hint.add_theme_font_size_override("font_size", 11)
	trace_hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	analysis_panel.add_child(trace_hint)
	analysis_panel.add_child(_labeled("Output folder", _analysis_output_line()))

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
	_showroom_axis_steps_spin.min_value = 1.0
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


func _analysis_output_line() -> LineEdit:
	_analysis_output = LineEdit.new()
	_analysis_output.text = "user://gem_designer_analysis"
	_analysis_output.size_flags_horizontal = SIZE_EXPAND_FILL
	return _analysis_output


func _update_analysis_debug_visibility() -> void:
	var debug_visible := _analysis_debug_checkbox != null and _analysis_debug_checkbox.button_pressed
	if _analysis_debug_label != null:
		_analysis_debug_label.visible = debug_visible


func _make_shared_trace_settings_group() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	var spp_l := Label.new()
	spp_l.text = "SPP"
	spp_l.add_theme_font_size_override("font_size", 12)
	spp_l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	row1.add_child(spp_l)
	_trace_spp_spin = SpinBox.new()
	_trace_spp_spin.min_value = 16.0
	_trace_spp_spin.max_value = 512.0
	_trace_spp_spin.step = 1.0
	_trace_spp_spin.value = float(GemTracedBakeContractScript.DEFAULT_SAMPLES_PER_PIXEL)
	_trace_spp_spin.custom_minimum_size = Vector2(72, 0)
	_trace_spp_spin.value_changed.connect(func(_v: float) -> void:
		_sync_trace_spin_aliases()
		_schedule_preview()
	)
	row1.add_child(_trace_spp_spin)
	var samp_l := Label.new()
	samp_l.text = "MSAA samples"
	samp_l.add_theme_font_size_override("font_size", 12)
	samp_l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	row1.add_child(samp_l)
	_trace_samples_spin = SpinBox.new()
	_trace_samples_spin.min_value = 1.0
	_trace_samples_spin.max_value = 5.0
	_trace_samples_spin.step = 1.0
	_trace_samples_spin.value = 1.0
	_trace_samples_spin.custom_minimum_size = Vector2(56, 0)
	_trace_samples_spin.value_changed.connect(func(_v: float) -> void:
		_sync_trace_spin_aliases()
		_schedule_preview()
	)
	row1.add_child(_trace_samples_spin)
	box.add_child(row1)
	_trace_stylize_checkbox = CheckBox.new()
	_trace_stylize_checkbox.text = "Apply stylization"
	_trace_stylize_checkbox.button_pressed = false
	_trace_stylize_checkbox.toggled.connect(func(_on: bool) -> void:
		_sync_trace_spin_aliases()
		_schedule_preview()
	)
	box.add_child(_trace_stylize_checkbox)
	_trace_match_gameplay_checkbox = CheckBox.new()
	_trace_match_gameplay_checkbox.text = "Match gameplay variant settings"
	_trace_match_gameplay_checkbox.button_pressed = false
	_trace_match_gameplay_checkbox.toggled.connect(func(_on: bool) -> void: _schedule_preview())
	box.add_child(_trace_match_gameplay_checkbox)
	_trace_adaptive_spp_checkbox = CheckBox.new()
	_trace_adaptive_spp_checkbox.text = "Adaptive SPP (material-aware)"
	_trace_adaptive_spp_checkbox.button_pressed = false
	_trace_adaptive_spp_checkbox.toggled.connect(func(_on: bool) -> void:
		_update_adaptive_spp_enabled()
		_schedule_preview()
	)
	box.add_child(_trace_adaptive_spp_checkbox)
	_trace_production_profile_checkbox = CheckBox.new()
	_trace_production_profile_checkbox.text = "Load gameplay.json trace defaults once"
	_trace_production_profile_checkbox.button_pressed = false
	_trace_production_profile_checkbox.toggled.connect(_on_trace_production_profile_toggled)
	box.add_child(_trace_production_profile_checkbox)
	_preview_bounces_spin = _trace_spp_spin
	_preview_samples_spin = _trace_samples_spin
	_preview_stylize_checkbox = _trace_stylize_checkbox
	_showroom_bounces_spin = _trace_spp_spin
	_analysis_sample_spin = _trace_samples_spin
	_showroom_stylize_checkbox = _trace_stylize_checkbox
	_update_adaptive_spp_enabled()
	return box


func _sync_trace_spin_aliases() -> void:
	pass


func _update_adaptive_spp_enabled() -> void:
	if _trace_spp_spin == null:
		return
	var use_adaptive := _trace_adaptive_spp_checkbox != null and _trace_adaptive_spp_checkbox.button_pressed
	_trace_spp_spin.editable = not use_adaptive


func _make_preview_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_preview_tex = TextureRect.new()
	_preview_tex.custom_minimum_size = Vector2(256, 256)
	_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_preview_tex)

	var activity := VBoxContainer.new()
	activity.add_theme_constant_override("separation", 4)
	_preview_activity_label = Label.new()
	_preview_activity_label.text = ""
	_preview_activity_label.add_theme_font_size_override("font_size", 12)
	_preview_activity_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	_preview_activity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activity.add_child(_preview_activity_label)

	_preview_activity_bar = ProgressBar.new()
	_preview_activity_bar.custom_minimum_size = Vector2(0, 8)
	_preview_activity_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_activity_bar.show_percentage = false
	_preview_activity_bar.visible = false
	_preview_activity_bar.indeterminate = true
	_preview_activity_bar.min_value = 0.0
	_preview_activity_bar.max_value = 1.0
	activity.add_child(_preview_activity_bar)
	box.add_child(activity)

	var hint := Label.new()
	hint.text = "Uses Trace settings above."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	box.add_child(hint)
	return box


func _set_preview_activity(message: String, show_loading_bar: bool) -> void:
	if _preview_activity_label != null:
		_preview_activity_label.text = message
		if not message.is_empty() and message.begins_with("Preview updated"):
			_preview_activity_label.add_theme_color_override("font_color", Color(0.62, 0.88, 0.72))
		elif not message.is_empty():
			_preview_activity_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	if _preview_activity_bar != null:
		_preview_activity_bar.visible = show_loading_bar and not message.is_empty()
	if _preview_tex != null:
		_preview_tex.modulate = Color(0.72, 0.74, 0.78, 1.0) if show_loading_bar else Color.WHITE


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


func _on_session_geometry_changed() -> void:
	_refresh_cut_ring_selector()


func _build_mineral_and_spectrum_block(parent: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Physical source & spectrum"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_mineral_path_edit = LineEdit.new()
	_mineral_path_edit.placeholder_text = "Mineral template .tres"
	_mineral_path_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_mineral_path_edit.text_changed.connect(func(_t: String) -> void: pass)
	var pick_min := Button.new()
	pick_min.text = "Pick…"
	pick_min.pressed.connect(_on_pick_mineral_template)
	row.add_child(_mineral_path_edit)
	row.add_child(pick_min)
	box.add_child(_labeled("Mineral template", row))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_restore_mineral_btn = Button.new()
	_restore_mineral_btn.text = "Restore mineral from file"
	_restore_mineral_btn.pressed.connect(_on_restore_mineral_template)
	_save_mineral_btn = Button.new()
	_save_mineral_btn.text = "Save mineral as…"
	_save_mineral_btn.pressed.connect(_on_save_mineral_template_pressed)
	btn_row.add_child(_restore_mineral_btn)
	btn_row.add_child(_save_mineral_btn)
	box.add_child(btn_row)

	var env_row := HBoxContainer.new()
	env_row.add_theme_constant_override("separation", 6)
	var env_edit := LineEdit.new()
	env_edit.placeholder_text = "Bake environment .tres"
	env_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	env_edit.name = "_bake_env_path_edit"
	var env_btn := Button.new()
	env_btn.text = "Pick…"
	env_btn.pressed.connect(_on_pick_bake_environment.bind(env_edit))
	env_row.add_child(env_edit)
	env_row.add_child(env_btn)
	box.add_child(_labeled("Bake environment", env_row))

	var tex_row := HBoxContainer.new()
	tex_row.add_theme_constant_override("separation", 6)
	var tex_edit := LineEdit.new()
	tex_edit.placeholder_text = "Color texture (optional)"
	tex_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	tex_edit.name = "_color_tex_path_edit"
	var tex_btn := Button.new()
	tex_btn.text = "Pick…"
	tex_btn.pressed.connect(_on_pick_color_texture.bind(tex_edit))
	tex_row.add_child(tex_edit)
	tex_row.add_child(tex_btn)
	tex_row.name = "_designer_color_texture_row"
	box.add_child(_labeled("Color texture", tex_row))

	_absorption_edit_mode = OptionButton.new()
	_absorption_edit_mode.add_item("Edit mineral absorption spectrum", SPECTRUM_TARGET_MINERAL_ABSORPTION)
	_absorption_edit_mode.add_item("Edit per-gem absorption override", SPECTRUM_TARGET_GEM_ABSORPTION_OVERRIDE)
	_absorption_edit_mode.add_item("Edit gradient zone absorption", SPECTRUM_TARGET_GRADIENT_ZONE)
	_absorption_edit_mode.add_item("Edit phenomenon zone absorption", SPECTRUM_TARGET_PHENOMENON_ZONE)
	_absorption_edit_mode.name = "_designer_spectrum_target_mode"
	_absorption_edit_mode.item_selected.connect(_on_absorption_edit_mode_changed)
	box.add_child(_labeled("Spectrum edit target", _absorption_edit_mode))

	_spectrum_source_label = Label.new()
	_spectrum_source_label.add_theme_font_size_override("font_size", 11)
	_spectrum_source_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	_spectrum_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_spectrum_source_label)

	_spectrum_editor = SpectrumCurveEditorScript.new()
	_spectrum_editor.name = "_designer_spectrum_editor"
	_spectrum_editor.samples_changed.connect(_on_spectrum_samples_changed)
	box.add_child(_spectrum_editor)

	var y_row := HBoxContainer.new()
	y_row.add_theme_constant_override("separation", 8)
	y_row.name = "_designer_spectrum_y_row"
	var y_lbl := Label.new()
	y_lbl.text = "Plot Y max (0 = auto)"
	y_lbl.custom_minimum_size = Vector2(140, 0)
	_spectrum_y_max_spin = SpinBox.new()
	_spectrum_y_max_spin.min_value = 0.0
	_spectrum_y_max_spin.max_value = 500.0
	_spectrum_y_max_spin.step = 0.5
	_spectrum_y_max_spin.value = 0.0
	_spectrum_y_max_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_spectrum_y_max_spin.value_changed.connect(func(v: float) -> void:
		if _spectrum_editor:
			_spectrum_editor.set_y_axis_max(v)
	)
	y_row.add_child(y_lbl)
	y_row.add_child(_spectrum_y_max_spin)
	box.add_child(y_row)

	var g_row := HBoxContainer.new()
	g_row.add_theme_constant_override("separation", 6)
	g_row.name = "_designer_spectrum_gaussian_row"
	var g_lbl := Label.new()
	g_lbl.text = "Gaussian λ σ strength"
	g_lbl.custom_minimum_size = Vector2(120, 0)
	_gauss_center_spin = SpinBox.new()
	_gauss_center_spin.min_value = 380.0
	_gauss_center_spin.max_value = 780.0
	_gauss_center_spin.value = 550.0
	_gauss_center_spin.prefix = "nm"
	_gauss_sigma_spin = SpinBox.new()
	_gauss_sigma_spin.min_value = 5.0
	_gauss_sigma_spin.max_value = 200.0
	_gauss_sigma_spin.value = 40.0
	_gauss_sigma_spin.prefix = "σ"
	_gauss_strength_spin = SpinBox.new()
	_gauss_strength_spin.min_value = 0.0
	_gauss_strength_spin.max_value = 50.0
	_gauss_strength_spin.step = 0.05
	_gauss_strength_spin.value = 1.0
	var gauss_btn := Button.new()
	gauss_btn.text = "Add band"
	gauss_btn.pressed.connect(_on_add_gaussian_band_to_spectrum)
	g_row.add_child(g_lbl)
	g_row.add_child(_gauss_center_spin)
	g_row.add_child(_gauss_sigma_spin)
	g_row.add_child(_gauss_strength_spin)
	g_row.add_child(gauss_btn)
	box.add_child(g_row)

	parent.add_child(box)
	# Path edits stored by name — resolved in refresh.
	set_meta("_bake_env_edit", env_edit)
	set_meta("_color_tex_edit", tex_edit)


func _on_pick_mineral_template() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; GemMineralTemplate"])
	dlg.file_selected.connect(func(p: String) -> void:
		var res = load(p)
		if res is GemMineralTemplate:
			_session.working_visual.mineral_template = (res as GemMineralTemplate).duplicate(true)
			_session.mineral_template_source_path = p
			_refresh_mineral_paths_and_spectrum()
			_rebuild_visual_inspector()
			_schedule_preview()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _on_restore_mineral_template() -> void:
	if _session.mineral_template_source_path.is_empty():
		_status.text = "No mineral template path on disk"
		return
	var disk = load(_session.mineral_template_source_path)
	if disk is GemMineralTemplate:
		_session.working_visual.mineral_template = (disk as GemMineralTemplate).duplicate(true)
		_refresh_mineral_paths_and_spectrum()
		_rebuild_visual_inspector()
		_schedule_preview()
		_status.text = "Restored mineral from %s" % _session.mineral_template_source_path


func _on_save_mineral_template_pressed() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; GemMineralTemplate"])
	dlg.file_selected.connect(func(p: String) -> void:
		var err := _session.save_mineral_template_to_path(p)
		_status.text = "Save mineral %s" % ("ok" if err == OK else str(err))
		_refresh_mineral_paths_and_spectrum()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _on_pick_bake_environment(env_edit: LineEdit) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres"])
	dlg.file_selected.connect(func(p: String) -> void:
		var res = load(p)
		if res != null:
			_session.working_visual.bake_environment = res
			env_edit.text = p
			_session.mark_visual_dirty()
			_schedule_preview()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _on_pick_color_texture(tex_edit: LineEdit) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.png, *.webp, *.jpg ; Images"])
	dlg.file_selected.connect(func(p: String) -> void:
		var tex: Texture2D = load(p) as Texture2D
		if tex != null:
			_session.working_visual.color_texture = tex
			tex_edit.text = p
			_session.mark_visual_dirty()
			_schedule_preview()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _refresh_mineral_paths_and_spectrum() -> void:
	if _mineral_path_edit and _session.working_visual:
		_mineral_path_edit.text = _session.mineral_template_source_path
		var env_edit: LineEdit = get_meta("_bake_env_edit", null) as LineEdit
		if env_edit and _session.working_visual.bake_environment != null:
			var bp: String = _session.working_visual.bake_environment.resource_path
			env_edit.text = bp
		var tex_edit: LineEdit = get_meta("_color_tex_edit", null) as LineEdit
		if tex_edit and _session.working_visual.color_texture != null:
			tex_edit.text = _session.working_visual.color_texture.resource_path
	_refresh_spectrum_editor_from_session()
	_refresh_spectrum_source_readout()


func _current_spectrum_target_id() -> int:
	if _absorption_edit_mode == null or _absorption_edit_mode.selected < 0:
		return SPECTRUM_TARGET_MINERAL_ABSORPTION
	return _absorption_edit_mode.get_item_id(_absorption_edit_mode.selected)


func _set_spectrum_target_id(target_id: int) -> void:
	if _absorption_edit_mode == null:
		return
	for i in _absorption_edit_mode.item_count:
		if _absorption_edit_mode.get_item_id(i) == target_id:
			_absorption_edit_mode.select(i)
			return


func _get_active_body_absorption_source() -> String:
	if _session.working_visual == null:
		return "none"
	if _session.working_visual.absorption_spectrum_override.size() == 81:
		return "per-gem absorption override"
	var mt: GemMineralTemplate = _session.working_visual.mineral_template as GemMineralTemplate
	if mt != null and mt.absorption_spectrum.size() == 81:
		return "mineral template absorption"
	return "no authored body absorption"


func _get_active_body_absorption_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _session.working_visual == null:
		return out
	if _session.working_visual.absorption_spectrum_override.size() == 81:
		return _session.working_visual.absorption_spectrum_override
	var mt: GemMineralTemplate = _session.working_visual.mineral_template as GemMineralTemplate
	if mt != null:
		return mt.absorption_spectrum
	return out


func _spectrum_target_requires_faceted(target_id: int) -> bool:
	return target_id in [SPECTRUM_TARGET_GRADIENT_ZONE, SPECTRUM_TARGET_PHENOMENON_ZONE]


func _refresh_spectrum_source_readout() -> void:
	if _spectrum_source_label == null or _session.working_visual == null:
		return
	var edit_target := "mineral absorption"
	match _current_spectrum_target_id():
		SPECTRUM_TARGET_GEM_ABSORPTION_OVERRIDE:
			edit_target = "per-gem absorption override"
		SPECTRUM_TARGET_GRADIENT_ZONE:
			edit_target = "gradient zone absorption"
		SPECTRUM_TARGET_PHENOMENON_ZONE:
			edit_target = "phenomenon zone absorption"
	_spectrum_source_label.text = "Editing: %s. Tracer body source: %s." % [
		edit_target,
		_get_active_body_absorption_source(),
	]


func _on_absorption_edit_mode_changed(_idx: int) -> void:
	_refresh_spectrum_editor_from_session()
	_refresh_spectrum_source_readout()


func _refresh_spectrum_editor_from_session() -> void:
	if _spectrum_editor == null or _session.working_visual == null:
		return
	var s := PackedFloat32Array()
	var overlay := PackedFloat32Array()
	match _current_spectrum_target_id():
		SPECTRUM_TARGET_GEM_ABSORPTION_OVERRIDE:
			s = _session.working_visual.absorption_spectrum_override
			var mt_override: GemMineralTemplate = _session.working_visual.mineral_template as GemMineralTemplate
			if mt_override != null:
				overlay = mt_override.absorption_spectrum
		SPECTRUM_TARGET_GRADIENT_ZONE:
			s = _session.working_visual.gradient_zone_spectrum
			overlay = _get_active_body_absorption_samples()
		SPECTRUM_TARGET_PHENOMENON_ZONE:
			s = _session.working_visual.phenomenon_zone_spectrum
			overlay = _get_active_body_absorption_samples()
		_:
			var mt: GemMineralTemplate = _session.working_visual.mineral_template as GemMineralTemplate
			if mt != null:
				s = mt.absorption_spectrum
				if mt.pleochroism_absorption_spectrum.size() == 81:
					overlay = mt.pleochroism_absorption_spectrum
	_spectrum_editor.set_samples(s)
	_spectrum_editor.set_overlay_samples(overlay)


func _on_add_gaussian_band_to_spectrum() -> void:
	if _spectrum_editor == null:
		return
	_spectrum_editor.add_gaussian_band(
		_gauss_center_spin.value,
		_gauss_sigma_spin.value,
		_gauss_strength_spin.value,
	)


func _on_spectrum_samples_changed(new_samples: PackedFloat32Array) -> void:
	if _session.working_visual == null:
		return
	match _current_spectrum_target_id():
		SPECTRUM_TARGET_GEM_ABSORPTION_OVERRIDE:
			_session.working_visual.absorption_spectrum_override = new_samples.duplicate()
		SPECTRUM_TARGET_GRADIENT_ZONE:
			_session.working_visual.gradient_zone_spectrum = new_samples.duplicate()
		SPECTRUM_TARGET_PHENOMENON_ZONE:
			_session.working_visual.phenomenon_zone_spectrum = new_samples.duplicate()
		_:
			if _session.working_visual.mineral_template is GemMineralTemplate:
				(_session.working_visual.mineral_template as GemMineralTemplate).absorption_spectrum = new_samples.duplicate()
	_session.mark_visual_dirty()
	_refresh_spectrum_source_readout()
	_schedule_preview()


func _build_cut_tab_header(cut_panel: VBoxContainer) -> void:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	_cut_spec_dropdown = OptionButton.new()
	_cut_spec_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	_cut_spec_dropdown.item_selected.connect(_on_cut_template_item_selected)
	row1.add_child(_cut_spec_dropdown)
	_cut_use_btn = Button.new()
	_cut_use_btn.text = "Use selected as base"
	_cut_use_btn.pressed.connect(_on_use_selected_cut_template)
	_cut_restore_btn = Button.new()
	_cut_restore_btn.text = "Restore to base template"
	_cut_restore_btn.pressed.connect(_on_restore_cut_to_template)
	row1.add_child(_cut_use_btn)
	row1.add_child(_cut_restore_btn)
	header.add_child(_labeled("Cut template", row1))
	_cut_edit_status = Label.new()
	_cut_edit_status.add_theme_font_size_override("font_size", 11)
	_cut_edit_status.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	header.add_child(_cut_edit_status)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_cut_ring_option = OptionButton.new()
	_cut_ring_option.custom_minimum_size = Vector2(140, 0)
	_cut_ring_option.item_selected.connect(_on_cut_ring_selected)
	row2.add_child(_labeled("Ring", _cut_ring_option))
	var add_ring_btn := Button.new()
	add_ring_btn.text = "Add"
	add_ring_btn.pressed.connect(_on_add_cut_ring_pressed)
	row2.add_child(add_ring_btn)
	var dup_ring_btn := Button.new()
	dup_ring_btn.text = "Duplicate"
	dup_ring_btn.pressed.connect(_on_duplicate_cut_ring_pressed)
	row2.add_child(dup_ring_btn)
	var remove_ring_btn := Button.new()
	remove_ring_btn.text = "Remove"
	remove_ring_btn.pressed.connect(_on_remove_cut_ring_pressed)
	row2.add_child(remove_ring_btn)
	header.add_child(row2)

	var row_h := HBoxContainer.new()
	row_h.add_theme_constant_override("separation", 8)
	var hl := Label.new()
	hl.text = "height_ratio"
	hl.custom_minimum_size = Vector2(88, 0)
	_cut_height_spin = SpinBox.new()
	_cut_height_spin.min_value = 0.0
	_cut_height_spin.max_value = 1.0
	_cut_height_spin.step = 0.001
	_cut_height_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_cut_height_spin.value_changed.connect(_on_cut_ring_metrics_spin_changed)
	var rl := Label.new()
	rl.text = "rose_h"
	rl.custom_minimum_size = Vector2(48, 0)
	_cut_rose_spin = SpinBox.new()
	_cut_rose_spin.min_value = 0.0
	_cut_rose_spin.max_value = 2.0
	_cut_rose_spin.step = 0.001
	_cut_rose_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_cut_rose_spin.value_changed.connect(_on_cut_ring_metrics_spin_changed)
	row_h.add_child(hl)
	row_h.add_child(_cut_height_spin)
	row_h.add_child(rl)
	row_h.add_child(_cut_rose_spin)
	header.add_child(row_h)

	var row_sym := HBoxContainer.new()
	row_sym.add_theme_constant_override("separation", 8)
	_cut_symm_check = CheckBox.new()
	_cut_symm_check.text = "Propagate dragged vertex across symmetry sectors"
	_cut_symm_check.tooltip_text = "When point count matches sector symmetry, dragging one vertex updates the corresponding point in each sector."
	_cut_symm_check.toggled.connect(_on_cut_symmetry_toggled)
	_cut_sector_label = Label.new()
	_cut_sector_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	row_sym.add_child(_cut_symm_check)
	row_sym.add_child(_cut_sector_label)
	header.add_child(row_sym)

	_cut_profile_canvas = CutProfileCanvasScript.new()
	_cut_profile_canvas.polygon_committed.connect(_on_cut_polygon_committed)
	header.add_child(_cut_profile_canvas)
	cut_panel.add_child(header)
	_refresh_cut_template_dropdown()


func _collect_tres_paths(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and fn.ends_with(".tres"):
			out.append("%s/%s" % [String(dir_path).trim_suffix("/"), fn])
		fn = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _refresh_cut_template_dropdown() -> void:
	if _cut_spec_dropdown == null:
		return
	_cut_spec_dropdown.clear()
	var paths := _collect_tres_paths(CUT_SPECS_DIR)
	for p in paths:
		_cut_spec_dropdown.add_item(p.get_file())
		_cut_spec_dropdown.set_item_metadata(_cut_spec_dropdown.item_count - 1, p)
	# Select current base if present
	if _session.base_cut_template_path:
		for i in _cut_spec_dropdown.item_count:
			if _cut_spec_dropdown.get_item_metadata(i) == _session.base_cut_template_path:
				_cut_spec_dropdown.select(i)
				break
	_update_cut_status_label()
	_refresh_cut_ring_selector()


func _on_cut_template_item_selected(_idx: int) -> void:
	pass


func _on_use_selected_cut_template() -> void:
	if _cut_spec_dropdown == null or _cut_spec_dropdown.selected < 0:
		return
	var path: String = _cut_spec_dropdown.get_item_metadata(_cut_spec_dropdown.selected)
	if _session.apply_cut_template_path(path):
		_refresh_cut_json_text()
		_schedule_preview()
		_status.text = "Cut base: %s" % path


func _on_restore_cut_to_template() -> void:
	_session.restore_cut_to_baseline()
	_refresh_cut_json_text()
	_refresh_cut_ring_selector()
	_schedule_preview()
	_status.text = "Cut restored to base template"


func _update_cut_status_label() -> void:
	if _cut_edit_status == null:
		return
	if _session.base_cut_template_path.is_empty():
		_cut_edit_status.text = "Embedded / non-template cut (saves as full cut_spec)."
	elif _session.has_cut_local_edits():
		_cut_edit_status.text = "Local edits vs %s (save writes cut_overrides)." % _session.base_cut_template_path.get_file()
	else:
		_cut_edit_status.text = "Matches base template %s" % _session.base_cut_template_path.get_file()


func _refresh_cut_ring_selector(select_ring_i: int = 0) -> void:
	if _cut_ring_option == null or _session.working_cut_spec == null:
		return
	_cut_ring_option.clear()
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings = contract.get("rings", [])
	if typeof(rings) != TYPE_ARRAY:
		return
	var i := 0
	for r in rings:
		_cut_ring_option.add_item("Ring %d" % i)
		_cut_ring_option.set_item_metadata(_cut_ring_option.item_count - 1, i)
		i += 1
	if _cut_ring_option.item_count > 0:
		_cut_ring_option.select(clampi(select_ring_i, 0, _cut_ring_option.item_count - 1))
	_on_cut_ring_selected(_cut_ring_option.selected if _cut_ring_option.item_count > 0 else -1)


func _selected_cut_ring_index() -> int:
	if _cut_ring_option == null or _cut_ring_option.selected < 0:
		return -1
	return int(_cut_ring_option.get_item_metadata(_cut_ring_option.selected))


func _scale_ring_points(points: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var center := Vector2(0.5, 0.5)
	for p in points:
		out.append(center + (p - center) * factor)
	return out


func _build_new_ring_from_reference(ref_ring: Dictionary, default_name: String, scale_factor: float) -> Dictionary:
	var ring := ref_ring.duplicate(true)
	ring["name"] = default_name
	var pts: PackedVector2Array = ring.get("points", PackedVector2Array()) as PackedVector2Array
	if pts.size() > 0:
		ring["points"] = _scale_ring_points(pts, scale_factor)
	ring["height_ratio"] = clampf(float(ring.get("height_ratio", 0.0)), 0.0, 1.0)
	ring["rose_height_ratio"] = maxf(float(ring.get("rose_height_ratio", 0.0)), 0.0)
	return ring


func _apply_cut_rings_contract(contract: Dictionary, select_ring_i: int) -> void:
	_session.working_cut_spec.apply_full_contract(contract)
	_session.sync_cut_to_visual()
	_session.mark_geometry_dirty()
	_update_cut_status_label()
	_refresh_cut_json_text()
	_refresh_cut_ring_selector(select_ring_i)
	_schedule_preview()


func _on_add_cut_ring_pressed() -> void:
	if _session.working_cut_spec == null:
		return
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings_raw = contract.get("rings", [])
	if typeof(rings_raw) != TYPE_ARRAY:
		return
	var rings: Array = rings_raw.duplicate(true)
	var ref_i := maxi(_selected_cut_ring_index(), 0)
	var ref_ring: Dictionary = rings[ref_i] if not rings.is_empty() else {
		"name": "ring_00",
		"points": PackedVector2Array([Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.7, 0.7), Vector2(0.3, 0.7)]),
		"height_ratio": 0.0,
		"rose_height_ratio": 0.0,
		"zone": "custom",
	}
	var insert_i := ref_i + 1
	rings.insert(insert_i, _build_new_ring_from_reference(ref_ring, "ring_%02d" % insert_i, 0.92))
	contract["rings"] = rings
	_apply_cut_rings_contract(contract, insert_i)


func _on_duplicate_cut_ring_pressed() -> void:
	if _session.working_cut_spec == null:
		return
	var ring_i := _selected_cut_ring_index()
	if ring_i < 0:
		return
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings_raw = contract.get("rings", [])
	if typeof(rings_raw) != TYPE_ARRAY:
		return
	var rings: Array = rings_raw.duplicate(true)
	var ring: Dictionary = (rings[ring_i] as Dictionary).duplicate(true)
	ring["name"] = "%s_copy" % String(ring.get("name", "ring_%02d" % ring_i))
	rings.insert(ring_i + 1, ring)
	contract["rings"] = rings
	_apply_cut_rings_contract(contract, ring_i + 1)


func _on_remove_cut_ring_pressed() -> void:
	if _session.working_cut_spec == null:
		return
	var ring_i := _selected_cut_ring_index()
	if ring_i < 0:
		return
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings_raw = contract.get("rings", [])
	if typeof(rings_raw) != TYPE_ARRAY:
		return
	var rings: Array = rings_raw.duplicate(true)
	if rings.size() <= 1:
		_status.text = "Cannot remove the last ring"
		return
	rings.remove_at(ring_i)
	contract["rings"] = rings
	_apply_cut_rings_contract(contract, maxi(0, ring_i - 1))


func _on_cut_symmetry_toggled(on: bool) -> void:
	if _cut_profile_canvas:
		_cut_profile_canvas.symmetry_rotation_enabled = on
		_cut_profile_canvas.queue_redraw()


func _on_cut_ring_metrics_spin_changed() -> void:
	if _updating_cut_metrics:
		return
	_commit_ring_metrics_from_ui()


func _commit_ring_metrics_from_ui() -> void:
	if _session.working_cut_spec == null or _cut_ring_option == null:
		return
	if _cut_ring_option.selected < 0:
		return
	var ring_i: int = int(_cut_ring_option.get_item_metadata(_cut_ring_option.selected))
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings_raw = contract.get("rings", [])
	if typeof(rings_raw) != TYPE_ARRAY:
		return
	var rings: Array = rings_raw.duplicate(true)
	if ring_i < 0 or ring_i >= rings.size():
		return
	var ring: Dictionary = (rings[ring_i] as Dictionary).duplicate(true)
	ring["height_ratio"] = _cut_height_spin.value
	ring["rose_height_ratio"] = _cut_rose_spin.value
	rings[ring_i] = ring
	contract["rings"] = rings
	_session.working_cut_spec.apply_full_contract(contract)
	_session.sync_cut_to_visual()
	_session.mark_geometry_dirty()
	_update_cut_status_label()
	_refresh_cut_json_text()
	_schedule_preview()


func _refresh_cut_ring_ghosts() -> void:
	if _cut_profile_canvas == null or _session.working_cut_spec == null or _cut_ring_option == null:
		return
	if _cut_ring_option.selected < 0:
		return
	var sel_i: int = int(_cut_ring_option.get_item_metadata(_cut_ring_option.selected))
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings = contract.get("rings", [])
	if typeof(rings) != TYPE_ARRAY:
		return
	var ghosts: Array = []
	for i in rings.size():
		if i == sel_i:
			continue
		var r: Dictionary = rings[i]
		var pts: PackedVector2Array = r.get("points", PackedVector2Array()) as PackedVector2Array
		if pts.size() > 1:
			ghosts.append(pts)
	_cut_profile_canvas.set_ghost_polygons(ghosts)


func _on_cut_ring_selected(_idx: int) -> void:
	if _cut_ring_option == null or _session.working_cut_spec == null:
		return
	if _cut_ring_option.selected < 0:
		return
	var ring_i: int = int(_cut_ring_option.get_item_metadata(_cut_ring_option.selected))
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings = contract.get("rings", [])
	if ring_i < 0 or ring_i >= rings.size():
		return
	var ring: Dictionary = rings[ring_i]
	var pts: PackedVector2Array = ring.get("points", PackedVector2Array()) as PackedVector2Array
	_updating_cut_metrics = true
	_cut_height_spin.value = float(ring.get("height_ratio", 0.0))
	_cut_rose_spin.value = float(ring.get("rose_height_ratio", 0.0))
	_updating_cut_metrics = false
	var sym: Dictionary = contract.get("symmetry", {})
	var sc := int(sym.get("sector_count", 0))
	_cut_sector_label.text = "sector_count=%d" % sc if sc > 0 else "sector_count=—"
	if _cut_profile_canvas:
		_cut_profile_canvas.sector_count = sc
		_cut_profile_canvas.sector_rotation_radians = float(sym.get("rotation", 0.0))
	if _cut_profile_canvas:
		_cut_profile_canvas.set_polygon(pts)
	_refresh_cut_ring_ghosts()


func _on_cut_polygon_committed(pts: PackedVector2Array) -> void:
	if _session.working_cut_spec == null or _cut_ring_option == null:
		return
	if _cut_ring_option.selected < 0:
		return
	var ring_i: int = int(_cut_ring_option.get_item_metadata(_cut_ring_option.selected))
	var contract: Dictionary = _session.working_cut_spec.build_contract_dict()
	var rings_raw = contract.get("rings", [])
	if typeof(rings_raw) != TYPE_ARRAY:
		return
	var rings: Array = rings_raw.duplicate(true)
	if ring_i < 0 or ring_i >= rings.size():
		return
	var ring: Dictionary = (rings[ring_i] as Dictionary).duplicate(true)
	ring["points"] = pts
	rings[ring_i] = ring
	contract["rings"] = rings
	_apply_cut_rings_contract(contract, ring_i)


func _build_trace_variant_options() -> Dictionary:
	if _trace_match_gameplay_checkbox == null or not _trace_match_gameplay_checkbox.button_pressed:
		return {}
	var prof: Dictionary = ProductionBakeProfileScript.load_profile_file(GAMEPLAY_BAKE_PROFILE_PATH)
	if prof.is_empty():
		return {}
	var bake_opts: Dictionary = ProductionBakeProfileScript.profile_to_bake_options(
		prof, GAMEPLAY_BAKE_PROFILE_PATH
	)
	return GemTracedBakeContractScript.build_manifest_variant_settings(bake_opts)


func _on_trace_production_profile_toggled(pressed: bool) -> void:
	if not pressed:
		return
	var prof: Dictionary = ProductionBakeProfileScript.load_profile_file(GAMEPLAY_BAKE_PROFILE_PATH)
	if prof.is_empty():
		_status.text = "Could not load gameplay bake profile"
		return
	var opts: Dictionary = ProductionBakeProfileScript.profile_to_bake_options(
		prof, GAMEPLAY_BAKE_PROFILE_PATH
	)
	if _trace_spp_spin:
		_trace_spp_spin.value = float(opts.get("samples_per_pixel", GemTracedBakeContractScript.DEFAULT_SAMPLES_PER_PIXEL))
	if _trace_samples_spin:
		_trace_samples_spin.value = float(opts.get("sample_count", 1))
	if _trace_stylize_checkbox:
		_trace_stylize_checkbox.button_pressed = not bool(opts.get("skip_stylize", false))
	if _trace_production_profile_checkbox:
		_trace_production_profile_checkbox.button_pressed = false
	_schedule_preview()


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
	_refresh_mineral_paths_and_spectrum()
	_refresh_cut_template_dropdown()
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
	var d: Dictionary = _session.build_cut_json_export_dict()
	_cut_edit.text = JSON.stringify(d, "\t")
	_update_cut_status_label()


func _on_apply_cut_json() -> void:
	var parsed = JSON.parse_string(_cut_edit.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status.text = "Cut JSON: expected object"
		return
	var data: Dictionary = parsed
	if data.has("cut_json_schema_version"):
		_session.apply_cut_json_export_dict(data)
	else:
		_session.apply_contract_dict_to_cut(data)
	_refresh_cut_json_text()
	_rebuild_visual_inspector()
	_refresh_cut_ring_selector()
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
	_refresh_mineral_paths_and_spectrum()
	_rebuild_visual_inspector()
	_refresh_visual_json_text()
	_schedule_preview()
	_status.text = "Visual JSON applied"


func _rebuild_visual_inspector() -> void:
	for c in _visual_scroll.get_children():
		c.queue_free()
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
	if n in [
		&"mineral_template",
		&"bake_environment",
		&"color_texture",
		&"absorption_spectrum_override",
		&"gradient_zone_spectrum",
		&"phenomenon_zone_spectrum",
	]:
		return null
	if t == TYPE_ARRAY or t == TYPE_DICTIONARY:
		return null

	# Sentinel float/color properties removed (environment presets no longer exist).

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

	if t == TYPE_OBJECT:
		var le := LineEdit.new()
		if val is Resource:
			le.text = (val as Resource).resource_path if (val as Resource).resource_path else "<embedded resource>"
		else:
			le.text = "<null>"
		le.editable = false
		le.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(le)
		return h

	if t == TYPE_PACKED_FLOAT32_ARRAY:
		var arr: PackedFloat32Array = val
		var lbl := Label.new()
		lbl.text = "%d floats (use Visual JSON for bulk edit)" % arr.size()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
		lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(lbl)
		return h

	return null


func _add_float_slider_row(h: HBoxContainer, n: String, val, vis: GemVisualResource, range_info: Dictionary) -> void:
	var is_pct := _is_percentage_property(n, range_info)
	var is_degrees := n.ends_with("_degrees")

	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(100, 0)

	var sb := SpinBox.new()
	sb.custom_minimum_size = Vector2(90, 0)
	sb.allow_greater = false
	sb.allow_lesser = false

	if is_pct:
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
		if is_pct:
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
		if is_pct:
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
# Dependency dimming
# ---------------------------------------------------------------------------

func _evaluate_prop_condition(vis: GemVisualResource, prop_name: StringName, condition: String) -> bool:
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
		var sn := StringName(prop_name)
		var dep_active := true
		if sn in _DEPENDENCY_RULES:
			var rule: Dictionary = _DEPENDENCY_RULES[sn]
			var requires: Dictionary = rule.requires
			for req_prop in requires:
				if not _evaluate_prop_condition(vis, req_prop, requires[req_prop]):
					dep_active = false
					break
		var material_dim := _material_mode_dims_prop(vis, sn)
		if dep_active and not material_dim:
			row.modulate.a = 1.0
			row.tooltip_text = ""
			_apply_row_interactive(row, true)
		else:
			row.modulate.a = 0.4
			if not dep_active and sn in _DEPENDENCY_RULES:
				row.tooltip_text = _DEPENDENCY_RULES[sn].reason
			elif material_dim:
				if sn in _MATERIAL_MODE_PATTERN_ONLY_PROPS:
					row.tooltip_text = "Patterned materials: texture and field controls. Disabled for faceted transparent."
				elif sn in _MATERIAL_MODE_FACETED_TRANSPARENT_ONLY_PROPS:
					row.tooltip_text = "Faceted transparent only (use gradient / phenomenon spectra or legacy RGB)."
				else:
					row.tooltip_text = "Not used for current material mode"
			else:
				row.tooltip_text = ""
			_apply_row_interactive(row, false)

	_update_physical_source_panel_state()


func _apply_row_interactive(row: Control, interactive: bool) -> void:
	if row == null:
		return
	_propagate_interactive(row, interactive)


func _propagate_interactive(n: Node, interactive: bool) -> void:
	if n is BaseButton:
		(n as BaseButton).disabled = not interactive
	elif n is SpinBox:
		(n as SpinBox).editable = interactive
	elif n is Slider:
		(n as Slider).editable = interactive
	elif n is LineEdit:
		(n as LineEdit).editable = interactive
	elif n is TextEdit:
		(n as TextEdit).editable = interactive
	elif n is ColorPickerButton:
		(n as ColorPickerButton).disabled = not interactive
	for c in n.get_children():
		_propagate_interactive(c, interactive)


func _update_physical_source_panel_state() -> void:
	if _session.working_visual == null:
		return
	var ft := _session.working_visual.material_mode == GemVisualResource.MATERIAL_MODE_FACETED_TRANSPARENT
	if _absorption_edit_mode != null:
		for i in _absorption_edit_mode.item_count:
			var target_id := _absorption_edit_mode.get_item_id(i)
			_absorption_edit_mode.set_item_disabled(i, _spectrum_target_requires_faceted(target_id) and not ft)
		if _spectrum_target_requires_faceted(_current_spectrum_target_id()) and not ft:
			_set_spectrum_target_id(SPECTRUM_TARGET_MINERAL_ABSORPTION)
			_refresh_spectrum_editor_from_session()
			_refresh_spectrum_source_readout()
	var tex_row = find_child("_designer_color_texture_row", true, false)
	if tex_row is Control:
		var tr := tex_row as Control
		tr.modulate.a = 0.45 if ft else 1.0
		tr.tooltip_text = "Faceted transparent gems use traced spectra; color texture applies to patterned materials." if ft else ""
		_apply_row_interactive(tr, not ft)
	var target_row = find_child("_designer_spectrum_target_mode", true, false)
	if target_row is Control:
		(target_row as Control).tooltip_text = "Gradient and phenomenon zone spectra are faceted-transparent authoring targets."
	var spectrum_ui_active := ft or not _spectrum_target_requires_faceted(_current_spectrum_target_id())
	for node_name in ["_designer_spectrum_editor", "_designer_spectrum_y_row", "_designer_spectrum_gaussian_row"]:
		var n = find_child(node_name, true, false)
		if n is Control:
			var c := n as Control
			c.modulate.a = 1.0 if spectrum_ui_active else 0.45
			c.tooltip_text = "" if spectrum_ui_active else "Gradient and phenomenon zone spectra are disabled outside faceted transparent mode."
			_apply_row_interactive(c, spectrum_ui_active)


func _material_mode_dims_prop(vis: GemVisualResource, prop_name: StringName) -> bool:
	var mode: int = vis.material_mode
	if prop_name in _MATERIAL_MODE_PATTERN_ONLY_PROPS:
		return mode == GemVisualResource.MATERIAL_MODE_FACETED_TRANSPARENT
	if prop_name in _MATERIAL_MODE_FACETED_TRANSPARENT_ONLY_PROPS:
		return mode != GemVisualResource.MATERIAL_MODE_FACETED_TRANSPARENT
	return false


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
	_update_dependency_states()
	_schedule_preview()


func _schedule_preview() -> void:
	_preview_gen += 1
	_preview_timer.stop()
	_preview_timer.start()
	_set_preview_activity("Preview · queued (~%.1fs debounce)…" % DEBOUNCE_SEC, true)
	if _status != null:
		_status.text = "Preview · waiting for debounce…"


func _on_preview_timer_timeout() -> void:
	_set_preview_activity("Preview · ray tracing…", true)
	if _status != null:
		_status.text = "Preview · baking…"
	_attempt_preview_trace()


## Starts a debounced preview trace for the current `_preview_gen`, or no-ops if a trace is
## already running (a new bake is chained in `_process` when the worker finishes if gen moved on).
func _attempt_preview_trace() -> void:
	if _preview_thread != null and _preview_thread.is_started():
		_set_preview_activity("Preview · finishing previous trace, then updating…", true)
		if _status != null:
			_status.text = "Preview · queued behind in-flight trace…"
		return
	var gen := _preview_gen
	_session.compile_geometry(false)
	var model = _session.get_cached_model()
	var cut = _session.get_cached_projected_cut()
	var vis_snap: GemVisualResource = _session.working_visual.duplicate(true)
	if model == null or cut == null or vis_snap == null:
		_set_preview_activity("Preview · invalid geometry", false)
		if _status != null:
			_status.text = "Preview: invalid geometry"
		_preview_stop_process_if_no_worker()
		return
	var mesh = GemMeshGeneratorsScript.generate_from_model(model)
	if mesh == null:
		_set_preview_activity("Preview · mesh build failed", false)
		if _status != null:
			_status.text = "Preview: mesh failed"
		_preview_stop_process_if_no_worker()
		return
	## Edits during compile/mesh build: skip this start; deferred retry picks up latest gen.
	if gen != _preview_gen:
		_preview_stop_process_if_no_worker()
		call_deferred("_attempt_preview_trace")
		return
	var variant_opts := _build_trace_variant_options()
	var use_adaptive := _trace_adaptive_spp_checkbox != null and _trace_adaptive_spp_checkbox.button_pressed
	var spp_arg := -1 if use_adaptive else clampi(int(_trace_spp_spin.value), 16, 512)
	var base_req := GemVisualRegistry.build_designer_preview_crown_request(
		SESSION_TILE_ID,
		vis_snap,
		model,
		cut,
		PREVIEW_SIZE,
		PREVIEW_SIZE,
		variant_opts,
		spp_arg
	)
	base_req["mesh_includes_cut_rotation"] = true
	var enrich_opts := {
		"skip_stylize": not (_trace_stylize_checkbox != null and _trace_stylize_checkbox.button_pressed),
	}
	if not use_adaptive:
		enrich_opts["samples_per_pixel"] = clampi(int(_trace_spp_spin.value), 16, 512)
	var sample_count := clampi(int(_trace_samples_spin.value), 1, OfflineGemBakeJobScript.max_supported_sample_count())
	var bake_job := OfflineGemBakeJobScript.new()
	var req := bake_job.build_designer_enriched_request(
		base_req,
		vis_snap,
		mesh,
		sample_count,
		enrich_opts
	)
	var preview_mesh: GemMeshResource = req.get("mesh_resource", null)
	if preview_mesh == null:
		_set_preview_activity("Preview · enriched mesh failed", false)
		if _status != null:
			_status.text = "Preview: enriched mesh failed"
		_preview_stop_process_if_no_worker()
		return
	var pack := {
		"gen": gen,
		"mesh": preview_mesh,
		"visual": vis_snap,
		"request": req,
		"weak_self": weakref(self),
	}
	_preview_thread = Thread.new()
	var err := _preview_thread.start(Callable(self, "_preview_thread_body").bind(pack))
	if err != OK:
		_preview_thread = null
		_preview_inflight_gen = -1
		_set_preview_activity("Preview · thread start failed", false)
		if _status != null:
			_status.text = "Preview thread start failed"
		set_process(false)
		return
	_preview_inflight_gen = gen
	set_process(true)


func _preview_stop_process_if_no_worker() -> void:
	if _preview_thread == null or not _preview_thread.is_started():
		set_process(false)


func _process(_delta: float) -> void:
	if _preview_thread == null or not _preview_thread.is_started():
		return
	if not _preview_thread.is_alive():
		var finished_gen := _preview_inflight_gen
		_preview_thread.wait_to_finish()
		_preview_thread = null
		_preview_inflight_gen = -1
		var need_fresh_trace := finished_gen >= 0 and _preview_gen != finished_gen
		if need_fresh_trace:
			_attempt_preview_trace()
		if _preview_thread == null or not _preview_thread.is_started():
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
	var img: Image = tracer.trace_to_image(mesh, visual, req)
	if img != null and not bool(req.get("skip_stylize", false)):
		img = GemBakeStylizerScript.apply(img, visual, req)
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
		_set_preview_activity("Preview · trace failed", false)
		if _status != null:
			_status.text = "Preview trace failed"
		return
	var tex := ImageTexture.create_from_image(img)
	_preview_tex.texture = tex
	_set_preview_activity("Preview updated", false)
	if _status != null:
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
	if _trace_match_gameplay_checkbox != null and _trace_match_gameplay_checkbox.button_pressed:
		opts["variant_settings"] = _build_trace_variant_options()
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
		"samples_per_pixel": int(_showroom_bounces_spin.value) if _showroom_bounces_spin != null else GemTracedBakeContractScript.DEFAULT_SAMPLES_PER_PIXEL,
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
