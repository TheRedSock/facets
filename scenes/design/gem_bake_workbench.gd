extends Control

## Active gem tooling surface: launches offline traced bake jobs in a separate
## headless process, polls job status without blocking the main thread, and
## previews the currently loaded gameplay-lighting/rotation variants.

const TILE_VIEW_SCENE := preload("res://scenes/tile/tile_view.tscn")
const RUNNER_SCRIPT_PATH := "res://tools/run_offline_gem_bake.gd"
const JOB_STATUS_DIR := "user://offline_bake_jobs"
const PREVIEW_BOARD_COLUMNS := 8
const PREVIEW_BOARD_ROWS := 8
const PREVIEW_TILE_SIZE := Vector2(120, 120)
const ROTATION_TILE_SIZE := Vector2(104, 104)
const POLL_INTERVAL_SECONDS := 0.4
const ROTATION_AXES := [&"pitch", &"yaw", &"roll"]
const LIGHTING_GRID_PRESET_ORDER := [&"performance", &"balanced", &"quality", &"ultra", &"custom"]
const QUALITY_PRESETS := [
	{"label": "Draft", "samples": 1, "draw_scale": 1.0},
	{"label": "Balanced", "samples": 2, "draw_scale": 1.5},
	{"label": "High", "samples": 4, "draw_scale": 2.0},
]

var _preview_gem_dropdown: OptionButton
var _selection_summary_label: Label
var _loaded_settings_label: Label
var _status_label: Label
var _job_detail_label: Label
var _job_progress_bar: ProgressBar
var _quality_dropdown: OptionButton
var _lighting_preset_dropdown: OptionButton
var _cell_size_spin: SpinBox
var _draw_size_spin: SpinBox
var _sample_count_spin: SpinBox
var _thread_count_spin: SpinBox
var _variant_worker_count_spin: SpinBox
var _lighting_x_spin: SpinBox
var _lighting_y_spin: SpinBox
var _runtime_lighting_x_spin: SpinBox
var _runtime_lighting_y_spin: SpinBox
var _include_orthographic_views_checkbox: CheckBox
var _rotation_steps_spin: SpinBox
var _rotation_step_degrees_spin: SpinBox
var _gem_checkbox_column: VBoxContainer
var _preview_board: Control
var _preview_info_label: Label
var _preview_tile: TileView
var _poll_timer: Timer

var _gem_ids: Array[StringName] = []
var _gem_checkboxes: Dictionary = {}
var _rotation_axis_checkboxes: Dictionary = {}
var _rotation_cards: Dictionary = {}
var _skip_lighting_checkbox: CheckBox
var _skip_rotations_checkbox: CheckBox
var _lighting_bins_filter_edit: LineEdit
var _rotation_bins_filter_edit: LineEdit
var _rotation_labels_filter_edit: LineEdit
var _include_showroom_checkbox: CheckBox
var _showroom_dirs_spin: SpinBox
var _showroom_roll_spin: SpinBox
var _preview_tile_id: StringName = &""
var _preview_tier := 1
var _preview_drag_active := false
var _preview_drag_offset := Vector2.ZERO
var _preview_board_uv := Vector2(0.5, 0.5)
var _job_pid := -1
var _job_running := false
var _job_status_path := ""
var _last_job_status: Dictionary = {}
var _syncing_settings_form := false


func _ready() -> void:
	_build_ui()
	_collect_visual_ids()
	_populate_preview_dropdown()
	_populate_gem_selection_list()
	_configure_registry()
	_sync_form_from_loaded_settings()
	_restore_preview_selection()
	_refresh_selection_summary()
	call_deferred("_ensure_preview_cache")


func _exit_tree() -> void:
	if GemVisualRegistry != null and GemVisualRegistry.gameplay_texture_cache_rebuilt.is_connected(_on_gameplay_texture_cache_rebuilt):
		GemVisualRegistry.gameplay_texture_cache_rebuilt.disconnect(_on_gameplay_texture_cache_rebuilt)


func _process(_delta: float) -> void:
	_update_preview_debug_labels()
	_update_rotation_preview_cards()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.09)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_build_top_bar(root)

	var title := Label.new()
	title.text = "Gem Bake Workbench"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Queue offline traced bake jobs, poll their progress asynchronously, and preview the loaded board textures."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.70, 0.75, 0.84))
	root.add_child(subtitle)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	_build_form_panel(body)
	_build_preview_panel(body)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_SECONDS
	_poll_timer.autostart = false
	_poll_timer.timeout.connect(_poll_bake_job_status)
	add_child(_poll_timer)


func _build_top_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	parent.add_child(bar)

	var menu_btn := Button.new()
	menu_btn.text = "< Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn"))
	bar.add_child(menu_btn)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	bar.add_child(play_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status_label = Label.new()
	_status_label.text = "Idle"
	_status_label.add_theme_color_override("font_color", Color(0.84, 0.87, 0.94))
	bar.add_child(_status_label)


func _build_form_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.14)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.27, 0.38)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	content.add_child(_make_section_title("Preview"))
	_preview_gem_dropdown = OptionButton.new()
	_preview_gem_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_gem_dropdown.item_selected.connect(_on_preview_gem_selected)
	content.add_child(_preview_gem_dropdown)

	_selection_summary_label = Label.new()
	_selection_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_summary_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.84))
	content.add_child(_selection_summary_label)

	content.add_child(_make_separator())
	content.add_child(_make_section_title("Bake Targets"))

	var target_actions := HBoxContainer.new()
	target_actions.add_theme_constant_override("separation", 8)
	content.add_child(target_actions)

	var select_all_btn := Button.new()
	select_all_btn.text = "All"
	select_all_btn.pressed.connect(func(): _set_all_gem_targets(true))
	target_actions.add_child(select_all_btn)

	var clear_btn := Button.new()
	clear_btn.text = "None"
	clear_btn.pressed.connect(func(): _set_all_gem_targets(false))
	target_actions.add_child(clear_btn)

	var preview_only_btn := Button.new()
	preview_only_btn.text = "Preview Gem"
	preview_only_btn.pressed.connect(_select_preview_gem_only)
	target_actions.add_child(preview_only_btn)

	var gem_scroll := ScrollContainer.new()
	gem_scroll.custom_minimum_size = Vector2(0, 260)
	gem_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	gem_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	gem_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(gem_scroll)

	_gem_checkbox_column = VBoxContainer.new()
	_gem_checkbox_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_gem_checkbox_column.add_theme_constant_override("separation", 6)
	gem_scroll.add_child(_gem_checkbox_column)

	content.add_child(_make_separator())
	content.add_child(_make_section_title("Bake Settings"))

	_quality_dropdown = OptionButton.new()
	_quality_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	for preset_index in QUALITY_PRESETS.size():
		_quality_dropdown.add_item(QUALITY_PRESETS[preset_index]["label"], preset_index)
	_quality_dropdown.item_selected.connect(_on_quality_preset_selected)
	content.add_child(_labeled_control("Quality Preset", _quality_dropdown))

	_lighting_preset_dropdown = OptionButton.new()
	_lighting_preset_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	_populate_lighting_preset_dropdown()
	_lighting_preset_dropdown.item_selected.connect(_on_lighting_preset_selected)
	content.add_child(_labeled_control("Lighting Grid Preset", _lighting_preset_dropdown))

	_cell_size_spin = _make_int_spinbox(48, 256, GameConfig.DEFAULT_CELL_SIZE.x)
	_cell_size_spin.value_changed.connect(_on_cell_size_changed)
	content.add_child(_labeled_control("Cell Size", _cell_size_spin))

	_draw_size_spin = _make_int_spinbox(48, 512, GameConfig.DEFAULT_CELL_SIZE.x)
	_draw_size_spin.value_changed.connect(func(_value: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Bake Draw Size", _draw_size_spin))

	_sample_count_spin = _make_int_spinbox(1, OfflineGemBakeJob.max_supported_sample_count(), 2)
	_sample_count_spin.value_changed.connect(func(_value: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Samples", _sample_count_spin))

	_thread_count_spin = _make_int_spinbox(0, maxi(OS.get_processor_count(), 1), 0)
	_thread_count_spin.value_changed.connect(func(_value: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Threads (0 = auto)", _thread_count_spin))

	_lighting_x_spin = _make_int_spinbox(0, 9, 5)
	_lighting_x_spin.value_changed.connect(_on_baked_lighting_grid_changed)
	content.add_child(_labeled_control("Baked Lighting Bins X", _lighting_x_spin))

	_lighting_y_spin = _make_int_spinbox(0, 9, 5)
	_lighting_y_spin.value_changed.connect(_on_baked_lighting_grid_changed)
	content.add_child(_labeled_control("Baked Lighting Bins Y", _lighting_y_spin))

	_runtime_lighting_x_spin = _make_int_spinbox(1, 9, 5)
	_runtime_lighting_x_spin.value_changed.connect(_on_runtime_lighting_grid_changed)
	content.add_child(_labeled_control("Runtime Lighting Regions X", _runtime_lighting_x_spin))

	_runtime_lighting_y_spin = _make_int_spinbox(1, 9, 5)
	_runtime_lighting_y_spin.value_changed.connect(_on_runtime_lighting_grid_changed)
	content.add_child(_labeled_control("Runtime Lighting Regions Y", _runtime_lighting_y_spin))

	_variant_worker_count_spin = _make_int_spinbox(0, maxi(OS.get_processor_count(), 1), 0)
	_variant_worker_count_spin.value_changed.connect(func(_value: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Variant Workers (0 = auto)", _variant_worker_count_spin))

	_include_orthographic_views_checkbox = CheckBox.new()
	_include_orthographic_views_checkbox.text = "Render the 6 orthographic baseline views"
	_include_orthographic_views_checkbox.button_pressed = true
	_include_orthographic_views_checkbox.toggled.connect(func(_pressed: bool): _refresh_selection_summary())
	content.add_child(_labeled_control("Orthographic Baseline", _include_orthographic_views_checkbox))

	_rotation_steps_spin = _make_int_spinbox(0, 6, 0)
	_rotation_steps_spin.value_changed.connect(func(_value: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Rotation Steps Per Axis Side", _rotation_steps_spin))

	_rotation_step_degrees_spin = _make_float_spinbox(5.0, 90.0, 18.0, 1.0)
	_rotation_step_degrees_spin.value_changed.connect(func(_value: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Rotation Step Degrees", _rotation_step_degrees_spin))

	var axis_box := VBoxContainer.new()
	axis_box.add_theme_constant_override("separation", 6)
	for axis in ROTATION_AXES:
		var checkbox := CheckBox.new()
		checkbox.text = String(axis).capitalize()
		checkbox.toggled.connect(func(_pressed: bool): _refresh_selection_summary())
		axis_box.add_child(checkbox)
		_rotation_axis_checkboxes[axis] = checkbox
	content.add_child(_labeled_control("Rotation Axis Sweeps", axis_box))

	content.add_child(_make_separator())
	content.add_child(_make_section_title("Showroom (optional)"))
	_include_showroom_checkbox = CheckBox.new()
	_include_showroom_checkbox.text = "Include showroom bake (Fibonacci directions × roll steps)"
	_include_showroom_checkbox.toggled.connect(func(_p: bool): _refresh_selection_summary())
	content.add_child(_labeled_control("Showroom", _include_showroom_checkbox))
	_showroom_dirs_spin = _make_int_spinbox(0, 2000, 0)
	_showroom_dirs_spin.value_changed.connect(func(_v: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Showroom Directions (0 = skip)", _showroom_dirs_spin))
	_showroom_roll_spin = _make_int_spinbox(1, 24, 6)
	_showroom_roll_spin.value_changed.connect(func(_v: float): _refresh_selection_summary())
	content.add_child(_labeled_control("Showroom Roll Steps", _showroom_roll_spin))

	content.add_child(_make_separator())
	content.add_child(_make_section_title("Selective Baking Filters"))

	_skip_lighting_checkbox = CheckBox.new()
	_skip_lighting_checkbox.text = "Skip all lighting variants"
	_skip_lighting_checkbox.toggled.connect(func(_pressed: bool): _refresh_selection_summary())
	content.add_child(_labeled_control("Skip Lighting", _skip_lighting_checkbox))

	_skip_rotations_checkbox = CheckBox.new()
	_skip_rotations_checkbox.text = "Skip all rotation variants"
	_skip_rotations_checkbox.toggled.connect(func(_pressed: bool): _refresh_selection_summary())
	content.add_child(_labeled_control("Skip Rotations", _skip_rotations_checkbox))

	_lighting_bins_filter_edit = LineEdit.new()
	_lighting_bins_filter_edit.placeholder_text = "e.g. 2x2;4x4 (empty = all)"
	_lighting_bins_filter_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(_labeled_control("Lighting Bin Filter", _lighting_bins_filter_edit))

	_rotation_bins_filter_edit = LineEdit.new()
	_rotation_bins_filter_edit.placeholder_text = "e.g. 0,3,7 (empty = all)"
	_rotation_bins_filter_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(_labeled_control("Rotation Bin Filter", _rotation_bins_filter_edit))

	_rotation_labels_filter_edit = LineEdit.new()
	_rotation_labels_filter_edit.placeholder_text = "e.g. pitch_pos_03,crown (empty = all)"
	_rotation_labels_filter_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(_labeled_control("Rotation Label Filter", _rotation_labels_filter_edit))

	content.add_child(_make_separator())
	content.add_child(_make_section_title("Run Job"))

	var start_btn := Button.new()
	start_btn.text = "Start Offline Bake Job"
	start_btn.custom_minimum_size = Vector2(0, 40)
	start_btn.pressed.connect(_start_bake_job)
	content.add_child(start_btn)

	_job_progress_bar = ProgressBar.new()
	_job_progress_bar.min_value = 0.0
	_job_progress_bar.max_value = 1.0
	_job_progress_bar.step = 0.001
	_job_progress_bar.show_percentage = true
	_job_progress_bar.custom_minimum_size = Vector2(0, 26)
	content.add_child(_job_progress_bar)

	_job_detail_label = Label.new()
	_job_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_detail_label.add_theme_color_override("font_color", Color(0.70, 0.75, 0.84))
	content.add_child(_job_detail_label)

	_loaded_settings_label = Label.new()
	_loaded_settings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loaded_settings_label.add_theme_color_override("font_color", Color(0.60, 0.67, 0.78))
	content.add_child(_loaded_settings_label)


func _build_preview_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.27, 0.38)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	var preview_title := Label.new()
	preview_title.text = "Loaded Texture Preview"
	preview_title.add_theme_font_size_override("font_size", 22)
	preview_title.add_theme_color_override("font_color", Color(0.90, 0.92, 0.97))
	content.add_child(preview_title)

	var preview_note := Label.new()
	preview_note.text = "Drag the selected gem inside the board-sized light grid. The three axis cards below animate only when the loaded bake contains those rotation bins."
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_note.add_theme_color_override("font_color", Color(0.70, 0.75, 0.84))
	content.add_child(preview_note)

	_preview_board = Control.new()
	_preview_board.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_board.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_board.custom_minimum_size = Vector2(0, 620)
	_preview_board.mouse_filter = MOUSE_FILTER_STOP
	_preview_board.draw.connect(_draw_preview_board)
	_preview_board.gui_input.connect(_on_preview_board_gui_input)
	_preview_board.resized.connect(_on_preview_board_resized)
	content.add_child(_preview_board)

	_preview_tile = TILE_VIEW_SCENE.instantiate()
	_preview_tile.use_gameplay_texture_cache = true
	_preview_tile.custom_minimum_size = PREVIEW_TILE_SIZE
	_preview_tile.size = PREVIEW_TILE_SIZE
	_preview_board.add_child(_preview_tile)

	_preview_info_label = Label.new()
	_preview_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_info_label.add_theme_color_override("font_color", Color(0.70, 0.75, 0.84))
	content.add_child(_preview_info_label)

	var cards := HBoxContainer.new()
	cards.size_flags_horizontal = SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 10)
	content.add_child(cards)

	for axis in ROTATION_AXES:
		var card := PanelContainer.new()
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		cards.add_child(card)

		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.07, 0.08, 0.11)
		card_style.set_corner_radius_all(10)
		card_style.content_margin_left = 10
		card_style.content_margin_right = 10
		card_style.content_margin_top = 10
		card_style.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", card_style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 8)
		card.add_child(vbox)

		var title := Label.new()
		title.text = "%s Axis" % String(axis).capitalize()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 17)
		vbox.add_child(title)

		var center := CenterContainer.new()
		vbox.add_child(center)

		var tile := TILE_VIEW_SCENE.instantiate()
		tile.use_gameplay_texture_cache = true
		tile.custom_minimum_size = ROTATION_TILE_SIZE
		tile.size = ROTATION_TILE_SIZE
		center.add_child(tile)

		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_color_override("font_color", Color(0.68, 0.73, 0.84))
		vbox.add_child(status)

		_rotation_cards[axis] = {
			"tile": tile,
			"status": status,
		}


func _make_section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.88, 0.91, 0.97))
	return label


func _make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 6)
	return separator


func _labeled_control(label_text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.70, 0.75, 0.84))
	box.add_child(label)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(control)
	return box


func _make_int_spinbox(min_value: int, max_value: int, default_value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.rounded = true
	spin.value = default_value
	return spin


func _make_float_spinbox(min_value: float, max_value: float, default_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = default_value
	return spin


func _populate_lighting_preset_dropdown() -> void:
	if _lighting_preset_dropdown == null:
		return
	_lighting_preset_dropdown.clear()
	for preset_name in LIGHTING_GRID_PRESET_ORDER:
		var label := _build_lighting_preset_label(preset_name)
		var item_index := _lighting_preset_dropdown.item_count
		_lighting_preset_dropdown.add_item(label, item_index)
		_lighting_preset_dropdown.set_item_metadata(item_index, preset_name)


func _build_lighting_preset_label(preset_name: StringName) -> String:
	if preset_name == &"custom":
		return "Custom"
	var grid := GemTracedBakeContract.resolve_lighting_grid_preset(preset_name)
	return "%s (%dx%d)" % [_titleize(preset_name), grid.x, grid.y]


func _collect_visual_ids() -> void:
	_gem_ids.clear()
	if GemVisualRegistry == null:
		return
	_gem_ids = GemVisualRegistry.get_visual_ids()
	if _gem_ids.is_empty():
		_gem_ids = [&"quartz"]


func _populate_preview_dropdown() -> void:
	if _preview_gem_dropdown == null:
		return
	_preview_gem_dropdown.clear()
	for tile_id in _gem_ids:
		var index := _preview_gem_dropdown.item_count
		_preview_gem_dropdown.add_item(_build_gem_label(tile_id))
		_preview_gem_dropdown.set_item_metadata(index, tile_id)


func _populate_gem_selection_list() -> void:
	if _gem_checkbox_column == null:
		return
	for child in _gem_checkbox_column.get_children():
		child.queue_free()
	_gem_checkboxes.clear()
	for tile_id in _gem_ids:
		var checkbox := CheckBox.new()
		checkbox.text = _build_gem_label(tile_id)
		checkbox.button_pressed = true
		checkbox.toggled.connect(func(_pressed: bool): _refresh_selection_summary())
		_gem_checkbox_column.add_child(checkbox)
		_gem_checkboxes[tile_id] = checkbox


func _configure_registry() -> void:
	if GemVisualRegistry == null:
		return
	GemVisualRegistry.reload_offline_traced_manifest(false)
	if not GemVisualRegistry.gameplay_texture_cache_rebuilt.is_connected(_on_gameplay_texture_cache_rebuilt):
		GemVisualRegistry.gameplay_texture_cache_rebuilt.connect(_on_gameplay_texture_cache_rebuilt)


func _sync_form_from_loaded_settings() -> void:
	if GemVisualRegistry == null:
		return
	_syncing_settings_form = true
	var settings: Dictionary = GemVisualRegistry.get_gameplay_variant_settings()
	var lighting_grid: Vector2i = settings.get("lighting_grid_size", Vector2i(5, 5))
	var runtime_lighting_grid: Vector2i = settings.get("lighting_runtime_grid_size", lighting_grid)
	_select_lighting_preset(settings.get("lighting_grid_preset", &"custom"))
	_lighting_x_spin.value = lighting_grid.x
	_lighting_y_spin.value = lighting_grid.y
	_update_runtime_lighting_grid_limits(lighting_grid)
	_runtime_lighting_x_spin.value = runtime_lighting_grid.x
	_runtime_lighting_y_spin.value = runtime_lighting_grid.y
	_include_orthographic_views_checkbox.button_pressed = int(
		settings.get("rotation_base_view_count", GemTracedBakeContract.DEFAULT_ROTATION_BASE_VIEW_COUNT)
	) > 0
	_rotation_steps_spin.value = int(settings.get("rotation_axis_steps", 0))
	_rotation_step_degrees_spin.value = float(settings.get("rotation_step_degrees", 18.0))
	var selected_axes: PackedStringArray = settings.get("rotation_axes", PackedStringArray())
	for axis in ROTATION_AXES:
		if _rotation_axis_checkboxes.has(axis):
			_rotation_axis_checkboxes[axis].button_pressed = selected_axes.has(String(axis))
	if _showroom_dirs_spin != null:
		_showroom_dirs_spin.value = int(settings.get("showroom_direction_count", 0))
	if _showroom_roll_spin != null:
		_showroom_roll_spin.value = int(settings.get("showroom_roll_steps", 6))
	if _include_showroom_checkbox != null:
		_include_showroom_checkbox.button_pressed = int(settings.get("showroom_direction_count", 0)) > 0
	_quality_dropdown.select(1)
	_on_quality_preset_selected(_quality_dropdown.selected)
	_syncing_settings_form = false
	_refresh_loaded_settings_label()
	_refresh_selection_summary()


func _restore_preview_selection() -> void:
	if _gem_ids.is_empty():
		return
	_preview_tile_id = _gem_ids[0]
	_preview_tier = _resolve_tier(_preview_tile_id)
	for index in _preview_gem_dropdown.item_count:
		if _preview_gem_dropdown.get_item_metadata(index) == _preview_tile_id:
			_preview_gem_dropdown.select(index)
			break
	_refresh_preview_tiles()


func _build_gem_label(tile_id: StringName) -> String:
	var tier := _resolve_tier(tile_id)
	var visual := GemVisualRegistry.get_visual(tile_id) if GemVisualRegistry != null else null
	var cut_id := visual.get_cut_spec_id() if visual != null else &""
	var parts := [_titleize(tile_id)]
	if tier > 0:
		parts.append("T%d" % tier)
	if cut_id != &"":
		parts.append(_titleize(cut_id))
	return " | ".join(parts)


func _resolve_tier(tile_id: StringName) -> int:
	if TileRegistry == null or not TileRegistry.has_definitions():
		return 1
	var definition = TileRegistry.get_definition(tile_id)
	if definition == null:
		return 1
	return int(definition.tier)


func _titleize(value) -> String:
	return String(value).replace("_", " ").capitalize()


func _on_preview_gem_selected(index: int) -> void:
	if _preview_gem_dropdown == null:
		return
	_preview_tile_id = _preview_gem_dropdown.get_item_metadata(index)
	_preview_tier = _resolve_tier(_preview_tile_id)
	_refresh_selection_summary()
	_ensure_preview_cache()


func _on_quality_preset_selected(index: int) -> void:
	if index < 0 or index >= QUALITY_PRESETS.size():
		return
	var preset: Dictionary = QUALITY_PRESETS[index]
	_sample_count_spin.value = int(preset.get("samples", 1))
	_draw_size_spin.value = int(round(_cell_size_spin.value * float(preset.get("draw_scale", 1.0))))
	_refresh_selection_summary()


func _on_lighting_preset_selected(index: int) -> void:
	if _syncing_settings_form or _lighting_preset_dropdown == null:
		return
	var preset_name := StringName(_lighting_preset_dropdown.get_item_metadata(index))
	if preset_name != &"custom":
		var grid := GemTracedBakeContract.resolve_lighting_grid_preset(preset_name)
		_lighting_x_spin.value = grid.x
		_lighting_y_spin.value = grid.y
	_update_runtime_lighting_grid_limits(_get_form_baked_lighting_grid())
	_refresh_selection_summary()


func _on_cell_size_changed(_value: float) -> void:
	if _quality_dropdown != null and _quality_dropdown.selected >= 0:
		_on_quality_preset_selected(_quality_dropdown.selected)
	_refresh_selection_summary()


func _on_baked_lighting_grid_changed(_value: float) -> void:
	if _syncing_settings_form:
		return
	_select_lighting_preset(GemTracedBakeContract.detect_lighting_grid_preset(_get_form_baked_lighting_grid()))
	_update_runtime_lighting_grid_limits(_get_form_baked_lighting_grid())
	_refresh_selection_summary()


func _on_runtime_lighting_grid_changed(_value: float) -> void:
	if _syncing_settings_form:
		return
	_update_runtime_lighting_grid_limits(_get_form_baked_lighting_grid())
	_refresh_selection_summary()
	_apply_runtime_lighting_preview()


func _set_all_gem_targets(enabled: bool) -> void:
	for checkbox in _gem_checkboxes.values():
		checkbox.button_pressed = enabled
	_refresh_selection_summary()


func _select_preview_gem_only() -> void:
	_set_all_gem_targets(false)
	if _gem_checkboxes.has(_preview_tile_id):
		var checkbox: CheckBox = _gem_checkboxes[_preview_tile_id]
		checkbox.button_pressed = true
	_refresh_selection_summary()


func _get_selected_gem_ids() -> Array[StringName]:
	var selected: Array[StringName] = []
	for tile_id in _gem_ids:
		if not _gem_checkboxes.has(tile_id):
			continue
		var checkbox: CheckBox = _gem_checkboxes[tile_id]
		if checkbox.button_pressed:
			selected.append(tile_id)
	return selected


func _get_selected_rotation_axes() -> PackedStringArray:
	var selected := PackedStringArray()
	for axis in ROTATION_AXES:
		if _rotation_axis_checkboxes.has(axis) and _rotation_axis_checkboxes[axis].button_pressed:
			selected.append(String(axis))
	return selected


func _estimate_rotation_bin_count() -> int:
	var base_view_count := GemTracedBakeContract.DEFAULT_ROTATION_BASE_VIEW_COUNT if _include_orthographic_views_checkbox.button_pressed else 0
	var sweep_count := _get_selected_rotation_axes().size() * int(_rotation_steps_spin.value) * 2
	return base_view_count + sweep_count


func _get_form_baked_lighting_grid() -> Vector2i:
	var lighting_grid := Vector2i(int(_lighting_x_spin.value), int(_lighting_y_spin.value))
	if lighting_grid.x <= 0 or lighting_grid.y <= 0:
		return Vector2i.ZERO
	return lighting_grid


func _get_form_runtime_lighting_grid() -> Vector2i:
	var baked_grid := _get_form_baked_lighting_grid()
	if baked_grid == Vector2i.ZERO:
		return Vector2i.ZERO
	return Vector2i(
		clampi(int(_runtime_lighting_x_spin.value), 1, baked_grid.x),
		clampi(int(_runtime_lighting_y_spin.value), 1, baked_grid.y)
	)


func _update_runtime_lighting_grid_limits(baked_grid: Vector2i) -> void:
	if _runtime_lighting_x_spin == null or _runtime_lighting_y_spin == null:
		return
	var min_value := 0.0 if baked_grid == Vector2i.ZERO else 1.0
	var max_x := maxf(float(baked_grid.x), min_value)
	var max_y := maxf(float(baked_grid.y), min_value)
	_runtime_lighting_x_spin.min_value = min_value
	_runtime_lighting_y_spin.min_value = min_value
	_runtime_lighting_x_spin.max_value = max_x
	_runtime_lighting_y_spin.max_value = max_y
	_runtime_lighting_x_spin.value = clampf(_runtime_lighting_x_spin.value, min_value, max_x)
	_runtime_lighting_y_spin.value = clampf(_runtime_lighting_y_spin.value, min_value, max_y)


func _get_selected_lighting_preset() -> StringName:
	if _lighting_preset_dropdown == null or _lighting_preset_dropdown.selected < 0:
		return &"custom"
	return StringName(_lighting_preset_dropdown.get_item_metadata(_lighting_preset_dropdown.selected))


func _select_lighting_preset(preset_name: StringName) -> void:
	if _lighting_preset_dropdown == null:
		return
	for item_index in _lighting_preset_dropdown.item_count:
		if StringName(_lighting_preset_dropdown.get_item_metadata(item_index)) != preset_name:
			continue
		_lighting_preset_dropdown.select(item_index)
		return


func _apply_runtime_lighting_preview() -> void:
	if GemVisualRegistry == null:
		return
	GemVisualRegistry.set_gameplay_virtual_lighting_grid_size(_get_form_runtime_lighting_grid(), true)


func _refresh_selection_summary() -> void:
	if _selection_summary_label == null:
		return
	var selected := _get_selected_gem_ids()
	var baked_grid := _get_form_baked_lighting_grid()
	var runtime_grid := _get_form_runtime_lighting_grid()
	var lighting_skipped := _skip_lighting_checkbox != null and _skip_lighting_checkbox.button_pressed
	var rotations_skipped := _skip_rotations_checkbox != null and _skip_rotations_checkbox.button_pressed
	var lighting_label := "SKIP" if lighting_skipped else "%s bake %dx%d" % [
		_titleize(_get_selected_lighting_preset()),
		baked_grid.x,
		baked_grid.y,
	]
	var rotation_label := "SKIP" if rotations_skipped else "%d rotation bins" % _estimate_rotation_bin_count()
	var filter_parts: PackedStringArray = []
	if _lighting_bins_filter_edit != null and not _lighting_bins_filter_edit.text.strip_edges().is_empty():
		filter_parts.append("light-filter")
	if _rotation_bins_filter_edit != null and not _rotation_bins_filter_edit.text.strip_edges().is_empty():
		filter_parts.append("rot-bin-filter")
	if _rotation_labels_filter_edit != null and not _rotation_labels_filter_edit.text.strip_edges().is_empty():
		filter_parts.append("rot-label-filter")
	var filter_note := "  |  filters: %s" % ",".join(filter_parts) if not filter_parts.is_empty() else ""
	var showroom_note := ""
	if _include_showroom_checkbox != null and _include_showroom_checkbox.button_pressed:
		var sd := int(_showroom_dirs_spin.value) if _showroom_dirs_spin != null else 0
		var sr := int(_showroom_roll_spin.value) if _showroom_roll_spin != null else 6
		if sd > 0:
			showroom_note = "  |  showroom %d×%d=%d" % [sd, sr, sd * sr]
		else:
			showroom_note = "  |  showroom (set directions > 0)"
	_selection_summary_label.text = "%d gems selected  |  %s  |  runtime %dx%d  |  %s  |  %d px cell  |  %d px bake  |  %d samples  |  threads %s  |  workers %s%s%s" % [
		selected.size(),
		lighting_label,
		runtime_grid.x,
		runtime_grid.y,
		rotation_label,
		int(_cell_size_spin.value),
		int(_draw_size_spin.value),
		int(_sample_count_spin.value),
		"auto" if int(_thread_count_spin.value) <= 0 else str(int(_thread_count_spin.value)),
		"auto" if int(_variant_worker_count_spin.value) <= 0 else str(int(_variant_worker_count_spin.value)),
		filter_note,
		showroom_note,
	]


func _refresh_loaded_settings_label() -> void:
	if _loaded_settings_label == null or GemVisualRegistry == null:
		return
	var settings: Dictionary = GemVisualRegistry.get_gameplay_variant_settings()
	var manifest_summary: Dictionary = GemVisualRegistry.get_offline_traced_manifest_summary()
	var manifest_cell_size: Vector2i = manifest_summary.get("cell_size", Vector2i.ZERO)
	var manifest_path := String(manifest_summary.get("manifest_path", ""))
	var lighting_grid: Vector2i = settings.get("lighting_grid_size", Vector2i.ZERO)
	var runtime_lighting_grid: Vector2i = settings.get("lighting_runtime_grid_size", lighting_grid)
	var axes: PackedStringArray = settings.get("rotation_axes", PackedStringArray())
	var orthographic_state := "on" if int(settings.get("rotation_base_view_count", 0)) > 0 else "off"
	_loaded_settings_label.text = "Loaded bake contract: preset=%s  baked=%dx%d  runtime=%dx%d  rotation=%d  ortho=%s  axes=%s  cache=%dx%d\nManifest: %s" % [
		String(settings.get("lighting_grid_preset", &"custom")),
		lighting_grid.x,
		lighting_grid.y,
		runtime_lighting_grid.x,
		runtime_lighting_grid.y,
		int(settings.get("rotation_bin_count", 0)),
		orthographic_state,
		",".join(axes),
		manifest_cell_size.x,
		manifest_cell_size.y,
		manifest_path if not manifest_path.is_empty() else "(none)",
	]


func _ensure_preview_cache() -> void:
	if GemVisualRegistry == null or _preview_tile_id == &"":
		return
	var preview_size := _get_preview_cache_size()
	GemVisualRegistry.ensure_gameplay_texture_cache(preview_size, [_preview_tile_id])
	_refresh_preview_tiles()


func _get_preview_cache_size() -> Vector2i:
	if GemVisualRegistry == null:
		return Vector2i(int(PREVIEW_TILE_SIZE.x), int(PREVIEW_TILE_SIZE.y))
	var manifest_summary: Dictionary = GemVisualRegistry.get_offline_traced_manifest_summary()
	var manifest_cell_size: Vector2i = manifest_summary.get("cell_size", Vector2i.ZERO)
	if manifest_cell_size.x > 0 and manifest_cell_size.y > 0:
		return manifest_cell_size
	return Vector2i(int(PREVIEW_TILE_SIZE.x), int(PREVIEW_TILE_SIZE.y))


func _refresh_preview_tiles() -> void:
	if _preview_tile == null or _preview_tile_id == &"":
		return
	_preview_tile.configure_from_data(_preview_tile_id, _preview_tier, Vector2i.ZERO)
	_preview_tile.set_debug_lighting_uv_override(_preview_board_uv)
	_layout_preview_tile()
	for axis in ROTATION_AXES:
		if not _rotation_cards.has(axis):
			continue
		var tile: TileView = _rotation_cards[axis]["tile"]
		tile.configure_from_data(_preview_tile_id, _preview_tier, Vector2i.ZERO)
	_update_rotation_preview_cards()


func _draw_preview_board() -> void:
	if _preview_board == null:
		return
	var rect := Rect2(Vector2.ZERO, _preview_board.size)
	_preview_board.draw_rect(rect, Color(0.05, 0.06, 0.09), true)
	var board_rect := _get_preview_board_inner_rect()
	var cell_size := Vector2(
		board_rect.size.x / float(PREVIEW_BOARD_COLUMNS),
		board_rect.size.y / float(PREVIEW_BOARD_ROWS)
	)
	for y in PREVIEW_BOARD_ROWS:
		for x in PREVIEW_BOARD_COLUMNS:
			var cell_rect := Rect2(
				board_rect.position + Vector2(x * cell_size.x, y * cell_size.y),
				cell_size
			)
			var shade := Color(0.14, 0.16, 0.21) if (x + y) % 2 == 0 else Color(0.18, 0.20, 0.26)
			_preview_board.draw_rect(cell_rect, shade, true)
	var outline_color := Color(0.30, 0.35, 0.46)
	_preview_board.draw_rect(board_rect, outline_color, false, 2.0)


func _get_preview_board_inner_rect() -> Rect2:
	var padding := 22.0
	var available := _preview_board.size - Vector2(padding * 2.0, padding * 2.0)
	var dimension := minf(available.x, available.y)
	dimension = maxf(dimension, 1.0)
	var size_v := Vector2(dimension, dimension)
	return Rect2((_preview_board.size - size_v) * 0.5, size_v)


func _layout_preview_tile() -> void:
	if _preview_board == null or _preview_tile == null:
		return
	var board_rect := _get_preview_board_inner_rect()
	var min_center := board_rect.position + PREVIEW_TILE_SIZE * 0.5
	var max_center := board_rect.end - PREVIEW_TILE_SIZE * 0.5
	var center := Vector2(
		lerpf(min_center.x, max_center.x, _preview_board_uv.x),
		lerpf(min_center.y, max_center.y, _preview_board_uv.y)
	)
	_preview_tile.position = center - PREVIEW_TILE_SIZE * 0.5


func _set_preview_board_uv(uv: Vector2) -> void:
	_preview_board_uv = Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
	if _preview_tile != null:
		_preview_tile.set_debug_lighting_uv_override(_preview_board_uv)
	_layout_preview_tile()


func _on_preview_board_resized() -> void:
	if _preview_board != null:
		_preview_board.queue_redraw()
	_layout_preview_tile()


func _on_preview_board_gui_input(event: InputEvent) -> void:
	if _preview_tile == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var tile_rect := Rect2(_preview_tile.position, PREVIEW_TILE_SIZE)
			if tile_rect.has_point(event.position):
				_preview_drag_active = true
				_preview_drag_offset = event.position - _preview_tile.position
		else:
			_preview_drag_active = false
		return
	if event is InputEventMouseMotion and _preview_drag_active:
		var mouse_motion := event as InputEventMouseMotion
		if mouse_motion == null:
			return
		var board_rect := _get_preview_board_inner_rect()
		var raw_position: Vector2 = mouse_motion.position - _preview_drag_offset
		var min_center := board_rect.position + PREVIEW_TILE_SIZE * 0.5
		var max_center := board_rect.end - PREVIEW_TILE_SIZE * 0.5
		var center: Vector2 = raw_position + PREVIEW_TILE_SIZE * 0.5
		center.x = clampf(center.x, min_center.x, max_center.x)
		center.y = clampf(center.y, min_center.y, max_center.y)
		var denom := max_center - min_center
		var uv := Vector2.ZERO
		if denom.x > 0.001:
			uv.x = (center.x - min_center.x) / denom.x
		if denom.y > 0.001:
			uv.y = (center.y - min_center.y) / denom.y
		_set_preview_board_uv(uv)


func _update_preview_debug_labels() -> void:
	if _preview_info_label == null or _preview_tile == null:
		return
	var state := _preview_tile.get_debug_gameplay_variant_state()
	_preview_info_label.text = "Lighting blend: %s" % _format_variant_state(state)


func _update_rotation_preview_cards() -> void:
	if GemVisualRegistry == null:
		return
	var now_seconds := Time.get_ticks_msec() / 1000.0
	for axis in ROTATION_AXES:
		if not _rotation_cards.has(axis):
			continue
		var card: Dictionary = _rotation_cards[axis]
		var tile: TileView = card["tile"]
		var status: Label = card["status"]
		var axis_descriptors := GemVisualRegistry.get_gameplay_rotation_view_descriptors_for_axis(axis)
		if axis_descriptors.is_empty():
			tile.visible = false
			status.text = "No %s rotation bins in the loaded bake." % String(axis)
			continue
		tile.visible = true
		var phase := fposmod(now_seconds * 0.18 + float(ROTATION_AXES.find(axis)) * 0.17, 1.0)
		tile.set_debug_rotation_axis_preview(axis, phase)
		status.text = _format_variant_state(tile.get_debug_gameplay_variant_state())


func _format_variant_state(state: Dictionary) -> String:
	var entries: Array = state.get("entries", [])
	if not entries.is_empty():
		var parts: Array[String] = []
		for entry in entries:
			var metadata: Dictionary = entry.get("metadata", {})
			var variant_key := String(metadata.get("variant_key", metadata.get("variant_cache_key", "")))
			var weight := float(entry.get("weight", 0.0))
			if not variant_key.is_empty():
				parts.append("%s %.2f" % [variant_key.get_file(), weight])
		if not parts.is_empty():
			return " | ".join(parts)
	var blend: Dictionary = state.get("sprite_blend", {})
	if blend.is_empty():
		return "waiting for cached variants"
	var w: Vector4 = blend.get("weights", Vector4.ZERO)
	var li: Vector4 = blend.get("layer_index", Vector4.ZERO)
	if w.length_squared() < 1e-10:
		return "active blend unavailable"
	return "atlas layers (%.0f,%.0f,%.0f,%.0f)  w(%.2f,%.2f,%.2f,%.2f)" % [
		li.x, li.y, li.z, li.w, w.x, w.y, w.z, w.w,
	]


func _build_job_settings() -> Dictionary:
	var rotation_steps := int(_rotation_steps_spin.value)
	var lighting_grid := _get_form_baked_lighting_grid()
	return {
		"tile_ids": _get_selected_gem_ids(),
		"cell_size": int(_cell_size_spin.value),
		"draw_size": int(_draw_size_spin.value),
		"sample_count": int(_sample_count_spin.value),
		"thread_count": int(_thread_count_spin.value),
		"variant_worker_count": int(_variant_worker_count_spin.value),
		"lighting_grid_preset": _get_selected_lighting_preset(),
		"lighting_grid_size": lighting_grid,
		"lighting_runtime_grid_size": _get_form_runtime_lighting_grid(),
		"rotation_base_view_count": GemTracedBakeContract.DEFAULT_ROTATION_BASE_VIEW_COUNT if _include_orthographic_views_checkbox.button_pressed else 0,
		"rotation_axis_steps": rotation_steps,
		"rotation_step_degrees": float(_rotation_step_degrees_spin.value),
		"rotation_axes": _get_selected_rotation_axes(),
		"skip_lighting": _skip_lighting_checkbox.button_pressed if _skip_lighting_checkbox != null else false,
		"skip_rotations": _skip_rotations_checkbox.button_pressed if _skip_rotations_checkbox != null else false,
		"lighting_bins_filter": _lighting_bins_filter_edit.text.strip_edges() if _lighting_bins_filter_edit != null else "",
		"rotation_bins_filter": _rotation_bins_filter_edit.text.strip_edges() if _rotation_bins_filter_edit != null else "",
		"rotation_labels_filter": _rotation_labels_filter_edit.text.strip_edges() if _rotation_labels_filter_edit != null else "",
		"include_showroom": _include_showroom_checkbox.button_pressed if _include_showroom_checkbox != null else false,
		"showroom_direction_count": int(_showroom_dirs_spin.value) if _showroom_dirs_spin != null else 0,
		"showroom_roll_steps": int(_showroom_roll_spin.value) if _showroom_roll_spin != null else 6,
	}


func _start_bake_job() -> void:
	if _job_running:
		_status_label.text = "Bake already running"
		return
	var settings := _build_job_settings()
	var tile_ids: Array[StringName] = settings["tile_ids"]
	if tile_ids.is_empty():
		tile_ids = [_preview_tile_id]
	var job_id := "job_%d" % Time.get_unix_time_from_system()
	_job_status_path = _make_global_job_status_path(job_id)
	var args := PackedStringArray([
		"--headless",
		"--path",
		_normalize_process_path(ProjectSettings.globalize_path("res://")),
		"--script",
		RUNNER_SCRIPT_PATH,
		"--",
		"--job_id=%s" % job_id,
		"--status_path=%s" % _normalize_process_path(_job_status_path),
		"--gems=%s" % _join_tile_ids(tile_ids),
		"--size=%d" % int(settings["cell_size"]),
		"--draw_size=%d" % int(settings["draw_size"]),
		"--samples=%d" % int(settings["sample_count"]),
		"--lighting_preset=%s" % String(settings["lighting_grid_preset"]),
		"--lighting_grid=%dx%d" % [
			settings["lighting_grid_size"].x,
			settings["lighting_grid_size"].y,
		],
		"--lighting_runtime_grid=%dx%d" % [
			settings["lighting_runtime_grid_size"].x,
			settings["lighting_runtime_grid_size"].y,
		],
		"--rotation_base_view_count=%d" % int(settings["rotation_base_view_count"]),
		"--rotation_axis_steps=%d" % int(settings["rotation_axis_steps"]),
		"--rotation_step_degrees=%.1f" % float(settings["rotation_step_degrees"]),
	])
	var rotation_axes: PackedStringArray = settings["rotation_axes"]
	if not rotation_axes.is_empty():
		args.append("--rotation_axes=%s" % ",".join(rotation_axes))
	if bool(settings.get("skip_lighting", false)):
		args.append("--skip_lighting")
	if bool(settings.get("skip_rotations", false)):
		args.append("--skip_rotations")
	var lighting_bins_filter := String(settings.get("lighting_bins_filter", ""))
	if not lighting_bins_filter.is_empty():
		args.append("--lighting_bins=%s" % lighting_bins_filter)
	var rotation_bins_filter := String(settings.get("rotation_bins_filter", ""))
	if not rotation_bins_filter.is_empty():
		args.append("--rotation_bins=%s" % rotation_bins_filter)
	var rotation_labels_filter := String(settings.get("rotation_labels_filter", ""))
	if not rotation_labels_filter.is_empty():
		args.append("--rotation_labels=%s" % rotation_labels_filter)
	if bool(settings.get("include_showroom", false)) and int(settings.get("showroom_direction_count", 0)) > 0:
		args.append("--showroom_directions=%d" % int(settings["showroom_direction_count"]))
		args.append("--showroom_roll_steps=%d" % int(settings.get("showroom_roll_steps", 6)))
	var thread_count := int(settings["thread_count"])
	if thread_count > 0:
		args.append("--threads=%d" % thread_count)
	var variant_worker_count := int(settings["variant_worker_count"])
	if variant_worker_count > 0:
		args.append("--variant_workers=%d" % variant_worker_count)
	var pid := OS.create_process(OS.get_executable_path(), args, false)
	if pid <= 0:
		_status_label.text = "Failed to launch bake job"
		_job_detail_label.text = "Godot could not start the headless bake process."
		return
	_job_pid = pid
	_job_running = true
	_last_job_status.clear()
	_job_progress_bar.value = 0.0
	_status_label.text = "Bake job running"
	_job_detail_label.text = "Polling %s" % _job_status_path
	_poll_timer.start()


func _poll_bake_job_status() -> void:
	if _job_status_path.is_empty():
		return
	var status := _read_status_file(_job_status_path)
	if not status.is_empty():
		_last_job_status = status
		_apply_job_status(status)
	var process_running := _job_pid > 0 and OS.is_process_running(_job_pid)
	if process_running:
		return
	_poll_timer.stop()
	_job_running = false
	var final_status := _last_job_status.duplicate(true)
	if final_status.is_empty():
		final_status = {
			"stage": "error",
			"status": "process_exited_without_status",
			"exit_code": OS.get_process_exit_code(_job_pid),
		}
	_apply_job_status(final_status)
	if final_status.get("stage", "") == "complete":
		if GemVisualRegistry != null:
			GemVisualRegistry.reload_offline_traced_manifest(true)
		_status_label.text = "Bake complete, reloading textures"
	else:
		_status_label.text = "Bake job failed"
	_job_pid = -1


func _apply_job_status(status: Dictionary) -> void:
	var stage := String(status.get("stage", ""))
	var progress := clampf(float(status.get("progress", 0.0)), 0.0, 1.0)
	var completed := int(status.get("completed", 0))
	var total := int(status.get("total", 0))
	var tile_id := String(status.get("tile_id", ""))
	var variant_key := String(status.get("variant_key", ""))
	_job_progress_bar.value = progress
	match stage:
		"starting":
			_job_detail_label.text = "Launching headless bake worker..."
		"queued":
			_job_detail_label.text = "Queued %d variants" % total
		"baking":
			_job_detail_label.text = "Tracing %d/%d  |  %s  |  %s" % [
				completed + 1,
				maxi(total, 1),
				_titleize(tile_id),
				variant_key,
			]
		"baked", "skipped":
			_job_detail_label.text = "Processed %d/%d  |  %s" % [completed, maxi(total, 1), variant_key]
		"complete":
			_job_detail_label.text = "Manifest: %s  |  entries=%d" % [
				String(status.get("manifest_path", "")),
				int(status.get("entry_count", 0)),
			]
		"error":
			_job_detail_label.text = String(status.get("status", "error"))
	if stage == "complete":
		_refresh_loaded_settings_label()


func _read_status_file(path: String) -> Dictionary:
	var resolved_path := _resolve_file_path(path)
	if not FileAccess.file_exists(resolved_path):
		return {}
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _join_tile_ids(tile_ids: Array[StringName]) -> String:
	var names := PackedStringArray()
	for tile_id in tile_ids:
		names.append(String(tile_id))
	return ",".join(names)


func _make_global_job_status_path(job_id: String) -> String:
	return _normalize_process_path(
		ProjectSettings.globalize_path("%s/%s.json" % [JOB_STATUS_DIR, job_id])
	)


func _normalize_process_path(path: String) -> String:
	return path.replace("\\", "/")


func _resolve_file_path(path: String) -> String:
	if path.contains("://"):
		return path
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path(path)


func _on_gameplay_texture_cache_rebuilt(profile: Dictionary) -> void:
	if profile.get("cell_size", Vector2i.ZERO) != _get_preview_cache_size():
		return
	if _preview_tile_id != &"":
		_refresh_preview_tiles()
	_refresh_loaded_settings_label()
	if not _job_running:
		_status_label.text = "Preview textures ready"
