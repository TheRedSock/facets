extends Control

## Runtime gem designer: edit visual + cut spec, live traced preview, Fibonacci analysis bake + orbit viewer.

const SESSION_TILE_ID := &"gem_designer_session"
const PREVIEW_SIZE := Vector2i(128, 128)
const DEBOUNCE_SEC := 0.55

const GemDesignSessionScript = preload("res://scenes/design/gem_design_session.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const GemCutModelModifierScript = preload("res://resources/visuals/gem_cut_model_modifier.gd")

var _session: GemDesignSessionScript

var _gem_dropdown: OptionButton
var _preview_tex: TextureRect
var _preview_timer: Timer
var _preview_gen := 0
var _preview_thread: Thread

var _visual_scroll: VBoxContainer
var _cut_edit: TextEdit
var _analysis_tex: TextureRect
var _analysis_debug_checkbox: CheckBox
var _analysis_debug_label: RichTextLabel
var _theta_spin: SpinBox
var _analysis_draw_spin: SpinBox
var _analysis_sample_spin: SpinBox
var _analysis_output: LineEdit
var _status: Label

var _analysis_entries: Array[Dictionary] = []
var _analysis_dirs: PackedVector3Array = PackedVector3Array()
var _analysis_textures: Array[Texture2D] = []
var _analysis_view_bases: Array[Basis] = []
var _analysis_selected_index := -1

var _orbit_basis := Basis.IDENTITY
var _drag_active := false
var _last_drag: Vector2

var _bake_in_progress := false
var _bake_btn: Button
var _bake_progress: ProgressBar
var _bake_progress_label: Label


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
	_visual_scroll.add_theme_constant_override("separation", 6)
	visual_panel.add_child(_visual_scroll)

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

	var analysis_panel := VBoxContainer.new()
	analysis_panel.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.add_child(analysis_panel)
	tabs.set_tab_title(analysis_panel.get_index(), "Analysis (Fibonacci)")

	analysis_panel.add_child(_labeled("Angular resolution θ (°)", _make_theta_spinbox()))
	analysis_panel.add_child(_labeled("Bake draw size (px)", _make_analysis_draw_spinbox()))
	analysis_panel.add_child(_labeled("Samples", _make_analysis_sample_spinbox()))
	analysis_panel.add_child(_labeled("Output folder", _analysis_output_line()))

	_bake_btn = Button.new()
	_bake_btn.text = "Run full Fibonacci bake"
	_bake_btn.pressed.connect(_on_run_fibonacci_bake)
	analysis_panel.add_child(_bake_btn)

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
	hint.text = "Drag the preview below to orbit (nearest baked direction)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.72))
	analysis_panel.add_child(hint)

	_analysis_tex = TextureRect.new()
	_analysis_tex.custom_minimum_size = Vector2(320, 320)
	_analysis_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_analysis_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_analysis_tex.gui_input.connect(_on_analysis_gui_input)
	analysis_panel.add_child(_analysis_tex)

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


func _make_theta_spinbox() -> SpinBox:
	_theta_spin = SpinBox.new()
	_theta_spin.min_value = 4.0
	_theta_spin.max_value = 45.0
	_theta_spin.step = 0.5
	_theta_spin.value = 12.0
	_theta_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	return _theta_spin


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


func _analysis_output_line() -> LineEdit:
	_analysis_output = LineEdit.new()
	_analysis_output.text = "user://gem_designer_analysis"
	_analysis_output.size_flags_horizontal = SIZE_EXPAND_FILL
	return _analysis_output


func _update_analysis_debug_visibility() -> void:
	var visible := _analysis_debug_checkbox != null and _analysis_debug_checkbox.button_pressed
	if _analysis_debug_label != null:
		_analysis_debug_label.visible = visible


func _make_preview_panel() -> Control:
	var box := VBoxContainer.new()
	_preview_tex = TextureRect.new()
	_preview_tex.custom_minimum_size = Vector2(128, 128)
	_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_preview_tex)
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
		_status.text = "Loaded %s" % String(id)


func _on_load_file_pressed() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; GemVisualResource"])
	dlg.file_selected.connect(func(p: String):
		if _session.load_from_visual_path(p):
			_refresh_all()
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
	_schedule_preview()


func _refresh_cut_json_text() -> void:
	if _session.working_cut_spec == null:
		_cut_edit.text = "{}"
		return
	var d := _session.working_cut_spec.build_contract_dict()
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


func _rebuild_visual_inspector() -> void:
	for c in _visual_scroll.get_children():
		c.queue_free()
	if _session.working_visual == null:
		return
	var vis: GemVisualResource = _session.working_visual
	for prop in vis.get_property_list():
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
			_visual_scroll.add_child(lbl)
			continue
		var val = vis.get(n)
		var row := _make_property_row(n, prop, val, vis)
		if row:
			_visual_scroll.add_child(row)


func _make_property_row(n: String, prop: Dictionary, val, vis: GemVisualResource) -> Control:
	var t: int = prop.type
	if t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_DICTIONARY:
		return null
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var name_l := Label.new()
	name_l.text = n
	name_l.custom_minimum_size = Vector2(200, 0)
	name_l.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	h.add_child(name_l)

	if t == TYPE_FLOAT:
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
		var sb2 := SpinBox.new()
		sb2.step = 1.0
		sb2.rounded = true
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
	var pack := {
		"gen": gen,
		"mesh": mesh,
		"visual": vis_snap,
		"request": req,
		"weak_self": weakref(self),
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
	req["sample_count"] = 1
	req["skip_stylize"] = true
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


func _on_run_fibonacci_bake() -> void:
	if _bake_in_progress:
		return
	_session.compile_geometry(true)
	var model = _session.get_cached_model()
	var cut = _session.get_cached_projected_cut()
	var vis_snap: GemVisualResource = _session.working_visual.duplicate(true)
	if model == null or cut == null:
		_status.text = "Analysis: invalid geometry"
		return
	var draw_sz := Vector2i(int(_analysis_draw_spin.value), int(_analysis_draw_spin.value))
	var opts := {
		"include_lighting": false,
		"include_rotation_suite": false,
		"include_view_sphere_fibonacci": true,
		"fibonacci_theta_degrees": float(_theta_spin.value),
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
		_status.text = "Analysis: no requests"
		return
	_bake_in_progress = true
	_bake_btn.disabled = true
	_bake_progress.visible = true
	_bake_progress_label.visible = true
	_bake_progress.value = 0.0
	_bake_progress_label.text = "Preparing %d views…" % raw.size()
	_status.text = "Baking %d views…" % raw.size()
	var job := OfflineGemBakeJobScript.new()
	var out := String(_analysis_output.text).strip_edges()
	if out.is_empty():
		out = "user://gem_designer_analysis"
	# Remove existing manifest so old entries from a prior gem/resolution
	# are not merged into this bake's results.
	var manifest_path := out + "/" + GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME
	var manifest_global := ProjectSettings.globalize_path(manifest_path)
	if FileAccess.file_exists(manifest_global):
		DirAccess.remove_absolute(manifest_global)
	var batch_opts := {
		"output_root": out,
		"draw_size": draw_sz,
		"sample_count": int(_analysis_sample_spin.value),
		"skip_stylize": false,
	}
	job.progress_updated.connect(_on_fibonacci_progress)
	var result: Dictionary = await job.run_explicit_request_batch_async(self, raw, draw_sz, batch_opts)
	job.progress_updated.disconnect(_on_fibonacci_progress)
	_bake_in_progress = false
	_bake_btn.disabled = false
	_bake_progress.visible = false
	_bake_progress_label.visible = false
	var entries: Array = result.get("entries", [])
	_load_analysis_entries(entries)
	_status.text = "Analysis bake: %s (%d entries)" % [String(result.get("status", "?")), entries.size()]


func _on_fibonacci_progress(p: Dictionary) -> void:
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


func _load_analysis_entries(entries: Array) -> void:
	_analysis_entries.clear()
	_analysis_dirs = PackedVector3Array()
	_analysis_textures.clear()
	_analysis_view_bases.clear()
	_analysis_selected_index = -1
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String(e.get("variant_type", "")) != "view_sphere":
			continue
		_analysis_entries.append(e)
	var sorted: Array = _analysis_entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rotation_bin", 0)) < int(b.get("rotation_bin", 0))
	)
	_analysis_entries.clear()
	for item in sorted:
		_analysis_entries.append(item)
	for e in _analysis_entries:
		var vd = e.get("view_dir_model", null)
		var dir := Vector3.BACK
		if vd is Array and (vd as Array).size() >= 3:
			var arr: Array = vd
			dir = Vector3(float(arr[0]), float(arr[1]), float(arr[2])).normalized()
		_analysis_dirs.append(dir)
		var path := String(e.get("texture_path", ""))
		var tex: Texture2D = null
		if path != "":
			var gpath := ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(gpath):
				var img := Image.load_from_file(gpath)
				if img != null:
					tex = ImageTexture.create_from_image(img)
		_analysis_textures.append(tex)
		var pitch_d := float(e.get("view_pitch_degrees", 0.0))
		var yaw_d := float(e.get("view_yaw_degrees", 0.0))
		var roll_d := float(e.get("view_roll_degrees", 0.0))
		_analysis_view_bases.append(_build_analysis_view_basis(pitch_d, yaw_d, roll_d))
	_orbit_basis = Basis.IDENTITY
	_update_analysis_texture()


func _on_analysis_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_active = mb.pressed
			_last_drag = mb.position
	elif event is InputEventMouseMotion and _drag_active:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _last_drag
		_last_drag = mm.position
		var sensitivity := 0.01
		var orbit_up := (_orbit_basis * Vector3.UP).normalized()
		var orbit_right := (_orbit_basis * Vector3.RIGHT).normalized()
		var orbit_view_dir := _desired_view_direction()
		var drag_basis := Basis(orbit_up, -d.x * sensitivity)
		drag_basis = drag_basis * Basis(orbit_right, -d.y * sensitivity)
		var dragged_view_dir := (drag_basis * orbit_view_dir).normalized()
		var dragged_up_hint := (drag_basis * orbit_up).normalized()
		_orbit_basis = _build_orbit_basis_for_view_dir(dragged_view_dir, dragged_up_hint)
		_update_analysis_texture()


func _desired_view_direction() -> Vector3:
	return (_orbit_basis * Vector3(0, 0, 1)).normalized()


func _build_analysis_camera_basis(pitch_d: float, yaw_d: float, roll_d: float) -> Basis:
	var cam_basis := Basis(Vector3.RIGHT, deg_to_rad(pitch_d))
	cam_basis = Basis(Vector3.UP, deg_to_rad(yaw_d)) * cam_basis
	if not is_zero_approx(roll_d):
		cam_basis = Basis(Vector3.BACK, deg_to_rad(roll_d)) * cam_basis
	return cam_basis.orthonormalized()


func _build_analysis_view_basis(pitch_d: float, yaw_d: float, roll_d: float) -> Basis:
	return _build_analysis_camera_basis(pitch_d, yaw_d, roll_d).inverse().orthonormalized()


func _build_orbit_basis_for_view_dir(view_dir: Vector3, up_hint: Vector3 = Vector3.UP) -> Basis:
	var back := view_dir.normalized()
	if back.is_zero_approx():
		back = Vector3.BACK
	var up := _project_onto_view_plane(Vector3.UP, back)
	if up.length_squared() < 0.001:
		up = _project_onto_view_plane(up_hint, back)
	if up.length_squared() < 0.001:
		up = _project_onto_view_plane(Vector3.BACK, back)
	if up.length_squared() < 0.001:
		up = _project_onto_view_plane(Vector3.RIGHT, back)
	up = up.normalized()
	var right := up.cross(back).normalized()
	up = back.cross(right).normalized()
	return Basis(right, up, back).orthonormalized()


func _project_onto_view_plane(v: Vector3, plane_normal: Vector3) -> Vector3:
	return v - v.dot(plane_normal) * plane_normal


func _unwrap_angle_near(current_angle: float, target_angle: float) -> float:
	return current_angle + wrapf(target_angle - current_angle, -PI, PI)


func _format_debug_vector(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _refresh_analysis_debug_text(
	want: Vector3,
	orbit_up: Vector3,
	orbit_right: Vector3,
	candidates: Array[Dictionary],
	selected: Dictionary,
	proj_up_len_sq: float,
	target_rotation: float,
	rotation_updated: bool
) -> void:
	if _analysis_debug_label == null:
		return
	if _analysis_debug_checkbox == null or not _analysis_debug_checkbox.button_pressed:
		return
	var lines := PackedStringArray()
	lines.append("want=%s" % _format_debug_vector(want))
	lines.append("up=%s" % _format_debug_vector(orbit_up))
	lines.append("right=%s" % _format_debug_vector(orbit_right))
	if selected.is_empty():
		lines.append("selected=<none>")
	else:
		lines.append("selected=%d %s  score=%.4f  dir=%.4f  up=%.4f  right=%.4f" % [
			int(selected.get("index", -1)),
			String(selected.get("label", "")),
			float(selected.get("score", 0.0)),
			float(selected.get("view_dot", 0.0)),
			float(selected.get("up_bonus", 0.0)),
			float(selected.get("right_bonus", 0.0)),
		])
		lines.append("selected_dir=%s" % _format_debug_vector(selected.get("view_dir", Vector3.ZERO)))
		lines.append("pitch=%.2f yaw=%.2f roll=%.2f" % [
			float(selected.get("pitch_d", 0.0)),
			float(selected.get("yaw_d", 0.0)),
			float(selected.get("roll_d", 0.0)),
		])
	lines.append("proj_up_len_sq=%.6f  target_rot=%.2fdeg  current_rot=%.2fdeg  updated=%s" % [
		proj_up_len_sq,
		rad_to_deg(target_rotation),
		rad_to_deg(_analysis_tex.rotation),
		"yes" if rotation_updated else "no",
	])
	if candidates.size() > 1:
		lines.append("top candidates:")
		for i in mini(candidates.size(), 4):
			var c: Dictionary = candidates[i]
			lines.append("  %d) #%d %s score=%.4f dir=%.4f up=%.4f right=%.4f" % [
				i + 1,
				int(c.get("index", -1)),
				String(c.get("label", "")),
				float(c.get("score", 0.0)),
				float(c.get("view_dot", 0.0)),
				float(c.get("up_bonus", 0.0)),
				float(c.get("right_bonus", 0.0)),
			])
	_analysis_debug_label.text = "\n".join(lines)


func _update_analysis_texture() -> void:
	if _analysis_dirs.is_empty():
		_refresh_analysis_debug_text(
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3.ZERO,
			[],
			{},
			0.0,
			0.0,
			false
		)
		return
	var want := _desired_view_direction()
	var orbit_up := (_orbit_basis * Vector3.UP).normalized()
	var orbit_right := (_orbit_basis * Vector3.RIGHT).normalized()
	# --- Frame selection: view direction + orientation tiebreaker -----------
	var best_i := 0
	var best_score := -999.0
	var scored_candidates: Array[Dictionary] = []
	for i in _analysis_dirs.size():
		var view_dot := _analysis_dirs[i].dot(want)
		var up_bonus := 0.0
		var right_bonus := 0.0
		var pitch_d := 0.0
		var yaw_d := 0.0
		var roll_d := 0.0
		var label := ""
		if i < _analysis_view_bases.size():
			var bake_basis: Basis = _analysis_view_bases[i]
			var bake_view_dir := bake_basis * Vector3.BACK
			var proj_up := _project_onto_view_plane(orbit_up, bake_view_dir)
			if proj_up.length_squared() > 0.001:
				up_bonus = (bake_basis * Vector3.UP).dot(proj_up.normalized())
			var proj_right := _project_onto_view_plane(orbit_right, bake_view_dir)
			if proj_right.length_squared() > 0.001:
				right_bonus = (bake_basis * Vector3.RIGHT).dot(proj_right.normalized())
		if i < _analysis_entries.size():
			var entry: Dictionary = _analysis_entries[i]
			pitch_d = float(entry.get("view_pitch_degrees", 0.0))
			yaw_d = float(entry.get("view_yaw_degrees", 0.0))
			roll_d = float(entry.get("view_roll_degrees", 0.0))
			label = String(entry.get("rotation_label", ""))
		var score := view_dot * 4.0 + up_bonus + right_bonus
		if i == _analysis_selected_index:
			score += 0.02
		scored_candidates.append({
			"index": i,
			"label": label,
			"score": score,
			"view_dot": view_dot,
			"up_bonus": up_bonus,
			"right_bonus": right_bonus,
			"view_dir": _analysis_dirs[i],
			"pitch_d": pitch_d,
			"yaw_d": yaw_d,
			"roll_d": roll_d,
		})
		if score > best_score:
			best_score = score
			best_i = i
	scored_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	_analysis_selected_index = best_i
	if best_i < _analysis_textures.size() and _analysis_textures[best_i] != null:
		_analysis_tex.texture = _analysis_textures[best_i]
	# --- Orbit-relative correction ------------------------------------------
	# Rebuild the selected frame's camera basis and compute the 2D rotation
	# that aligns the frame's camera-up with the orbit's expected up on screen.
	_analysis_tex.pivot_offset = _analysis_tex.size * 0.5
	if best_i >= _analysis_entries.size():
		_analysis_tex.rotation = 0.0
		_refresh_analysis_debug_text(
			want,
			orbit_up,
			orbit_right,
			scored_candidates,
			{},
			0.0,
			0.0,
			true
		)
		return
	var e := _analysis_entries[best_i]
	var pitch_d := float(e.get("view_pitch_degrees", 0.0))
	var yaw_d := float(e.get("view_yaw_degrees", 0.0))
	var roll_d := float(e.get("view_roll_degrees", 0.0))
	var bake_basis := _build_analysis_view_basis(pitch_d, yaw_d, roll_d)
	var bake_up := bake_basis * Vector3.UP
	var bake_right := bake_basis * Vector3.RIGHT
	var bake_view_dir := bake_basis * Vector3.BACK
	# Project the orbit's up onto the bake frame's view plane.
	var proj_up := _project_onto_view_plane(orbit_up, bake_view_dir)
	var proj_up_len_sq := proj_up.length_squared()
	if proj_up.length_squared() < 0.001:
		# Near the pole the canonical up becomes ambiguous, so preserve the
		# previous visual angle instead of injecting a discontinuous 180 deg turn.
		_refresh_analysis_debug_text(
			want,
			orbit_up,
			orbit_right,
			scored_candidates,
			scored_candidates[0] if not scored_candidates.is_empty() else {},
			proj_up_len_sq,
			_analysis_tex.rotation,
			false
		)
		return
	if proj_up.length_squared() < 0.0001:
		_refresh_analysis_debug_text(
			want,
			orbit_up,
			orbit_right,
			scored_candidates,
			scored_candidates[0] if not scored_candidates.is_empty() else {},
			proj_up_len_sq,
			_analysis_tex.rotation,
			false
		)
		return
	proj_up = proj_up.normalized()
	# Angle from bake camera-up to the orbit's expected up, in screen space.
	var target_rotation := -atan2(proj_up.dot(bake_right), proj_up.dot(bake_up))
	_analysis_tex.rotation = _unwrap_angle_near(_analysis_tex.rotation, target_rotation)
	_refresh_analysis_debug_text(
		want,
		orbit_up,
		orbit_right,
		scored_candidates,
		scored_candidates[0] if not scored_candidates.is_empty() else {},
		proj_up_len_sq,
		target_rotation,
		true
	)
