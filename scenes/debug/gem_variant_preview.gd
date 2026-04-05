extends Control

## Deprecated legacy variant preview.
## This debug scene predates the active workbench and should not be treated as
## the current gem preview/bake workflow.

const TILE_VIEW_SCENE := preload("res://scenes/tile/tile_view.tscn")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const DEFAULT_PREVIEW_TILE_ID := &"quartz"
const DEFAULT_PREVIEW_TIER := 1
const MOVER_LIGHTING_PATH := [
	Vector2(0.0, 0.0),
	Vector2(0.25, 0.0),
	Vector2(0.5, 0.25),
	Vector2(0.75, 0.5),
	Vector2(1.0, 0.75),
	Vector2(1.0, 1.0),
	Vector2(0.5, 1.0),
	Vector2(0.0, 0.5),
	Vector2(0.5, 0.5),
	Vector2(0.0, 0.0),
]
const STATIC_PREVIEW_COUNT := 10
const STATIC_COLUMNS := 5
const STATIC_ROWS := 2
const STATIC_TILE_SIZE := Vector2(112, 112)
const ACTIVE_TILE_SIZE := Vector2(144, 144)

var _preset_dropdown: OptionButton
var _generate_traced_button: Button
var _generate_all_button: Button
var _status_label: Label
var _report_label: Label
var _loading_progress: ProgressBar
var _job_metrics_label: Label
var _preview_stage: Control
var _movement_caption: Label
var _movement_info: Label
var _rotation_caption: Label
var _rotation_info: Label
var _static_tiles: Array = []
var _mover = null
var _spinner = null
var _mover_tween: Tween
var _mover_lighting_uv := Vector2.ZERO
var _rotation_timer: Timer
var _offline_job_running := false
var _preview_presets: Array[Dictionary] = []
var _current_preview_tile_id: StringName = DEFAULT_PREVIEW_TILE_ID
var _current_preview_tier := DEFAULT_PREVIEW_TIER


func _ready() -> void:
	_build_preview_presets()
	_build_ui()
	_sync_preset_dropdown()
	if GemVisualRegistry != null:
		GemVisualRegistry.set_gameplay_bake_backend_preference(
			GemVisualRegistry.GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED
		)
		GemVisualRegistry.set_gameplay_runtime_bake_fallback_enabled(false)
		if not GemVisualRegistry.gameplay_texture_bake_progress.is_connected(_on_bake_progress):
			GemVisualRegistry.gameplay_texture_bake_progress.connect(_on_bake_progress)
		if not GemVisualRegistry.gameplay_texture_cache_rebuilt.is_connected(_on_cache_rebuilt):
			GemVisualRegistry.gameplay_texture_cache_rebuilt.connect(_on_cache_rebuilt)
	set_process(true)
	call_deferred("_ensure_preview_cache")


func _exit_tree() -> void:
	if GemVisualRegistry != null:
		if GemVisualRegistry.gameplay_texture_bake_progress.is_connected(_on_bake_progress):
			GemVisualRegistry.gameplay_texture_bake_progress.disconnect(_on_bake_progress)
		if GemVisualRegistry.gameplay_texture_cache_rebuilt.is_connected(_on_cache_rebuilt):
			GemVisualRegistry.gameplay_texture_cache_rebuilt.disconnect(_on_cache_rebuilt)


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
	title.text = "Offline Bake Variant Preview"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	_status_label = Label.new()
	_status_label.text = "Preparing preview cache..."
	_status_label.add_theme_font_size_override("font_size", 15)
	root.add_child(_status_label)

	_report_label = Label.new()
	_report_label.text = "Reviewing offline traced lighting and rotation variants."
	_report_label.add_theme_font_size_override("font_size", 14)
	_report_label.add_theme_color_override("font_color", Color(0.72, 0.77, 0.87))
	root.add_child(_report_label)

	_loading_progress = ProgressBar.new()
	_loading_progress.min_value = 0.0
	_loading_progress.max_value = 1.0
	_loading_progress.step = 0.001
	_loading_progress.custom_minimum_size = Vector2(0, 24)
	_loading_progress.show_percentage = true
	root.add_child(_loading_progress)

	_job_metrics_label = Label.new()
	_job_metrics_label.text = "No traced bake running"
	_job_metrics_label.add_theme_font_size_override("font_size", 13)
	_job_metrics_label.add_theme_color_override("font_color", Color(0.66, 0.71, 0.82))
	root.add_child(_job_metrics_label)

	var stage_panel := PanelContainer.new()
	stage_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	stage_panel.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(stage_panel)

	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color(0.08, 0.09, 0.13)
	stage_style.border_width_left = 1
	stage_style.border_width_top = 1
	stage_style.border_width_right = 1
	stage_style.border_width_bottom = 1
	stage_style.border_color = Color(0.22, 0.29, 0.42)
	stage_style.set_corner_radius_all(12)
	stage_style.content_margin_left = 14
	stage_style.content_margin_right = 14
	stage_style.content_margin_top = 14
	stage_style.content_margin_bottom = 14
	stage_panel.add_theme_stylebox_override("panel", stage_style)

	_preview_stage = Control.new()
	_preview_stage.custom_minimum_size = Vector2(0, 720)
	_preview_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_preview_stage.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_stage.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_stage.draw.connect(_draw_preview_stage)
	_preview_stage.resized.connect(_on_preview_stage_resized)
	stage_panel.add_child(_preview_stage)

	_rotation_timer = Timer.new()
	_rotation_timer.wait_time = 1.35
	_rotation_timer.autostart = false
	_rotation_timer.timeout.connect(_on_rotation_timer_timeout)
	add_child(_rotation_timer)


func _build_top_bar(parent: VBoxContainer) -> void:
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	parent.add_child(top_bar)

	var menu_btn := Button.new()
	menu_btn.text = "< Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn"))
	top_bar.add_child(menu_btn)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	top_bar.add_child(play_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var preset_label := Label.new()
	preset_label.text = "Preset"
	top_bar.add_child(preset_label)

	_preset_dropdown = OptionButton.new()
	_preset_dropdown.item_selected.connect(_on_preset_selected)
	top_bar.add_child(_preset_dropdown)

	var rebake_btn := Button.new()
	rebake_btn.text = "Rebake"
	rebake_btn.pressed.connect(_on_rebake_pressed)
	top_bar.add_child(rebake_btn)

	_generate_traced_button = Button.new()
	_generate_traced_button.text = "Trace Preset"
	_generate_traced_button.pressed.connect(_on_generate_traced_pressed)
	top_bar.add_child(_generate_traced_button)

	_generate_all_button = Button.new()
	_generate_all_button.text = "Trace All"
	_generate_all_button.pressed.connect(_on_generate_all_traced_pressed)
	top_bar.add_child(_generate_all_button)


func _build_preview_presets() -> void:
	_preview_presets.clear()
	if GemVisualRegistry != null:
		for tile_id in GemVisualRegistry.get_visual_ids():
			var visual: GemVisualResource = GemVisualRegistry.get_visual(tile_id)
			if visual == null:
				continue
			var tier := _resolve_preview_tier(tile_id)
			_preview_presets.append({
				"tile_id": tile_id,
				"tier": tier,
				"cut_id": visual.cut_id,
				"label": _format_preset_label(tile_id, tier, visual.cut_id),
			})
	if _preview_presets.is_empty():
		_preview_presets.append({
			"tile_id": DEFAULT_PREVIEW_TILE_ID,
			"tier": DEFAULT_PREVIEW_TIER,
			"cut_id": &"",
			"label": _format_preset_label(DEFAULT_PREVIEW_TILE_ID, DEFAULT_PREVIEW_TIER, &""),
		})
	_select_preview_preset_by_tile_id(DEFAULT_PREVIEW_TILE_ID)


func _sync_preset_dropdown() -> void:
	if _preset_dropdown == null:
		return
	_preset_dropdown.clear()
	for preset in _preview_presets:
		var index := _preset_dropdown.item_count
		_preset_dropdown.add_item(String(preset.get("label", "Gem")))
		_preset_dropdown.set_item_metadata(index, preset.get("tile_id", &""))
	for index in _preset_dropdown.item_count:
		if _preset_dropdown.get_item_metadata(index) == _current_preview_tile_id:
			_preset_dropdown.select(index)
			break
	_update_generate_button_labels()


func _select_preview_preset_by_tile_id(tile_id: StringName) -> void:
	for preset in _preview_presets:
		if preset.get("tile_id", &"") == tile_id:
			_current_preview_tile_id = preset.get("tile_id", DEFAULT_PREVIEW_TILE_ID)
			_current_preview_tier = int(preset.get("tier", DEFAULT_PREVIEW_TIER))
			return
	_current_preview_tile_id = DEFAULT_PREVIEW_TILE_ID
	_current_preview_tier = DEFAULT_PREVIEW_TIER


func _ensure_preview_cache(force_rebuild: bool = false) -> void:
	if GemVisualRegistry == null:
		return
	_status_label.text = "Preparing %s preview cache..." % _get_current_preview_name()
	if force_rebuild:
		_loading_progress.value = 0.0
	if force_rebuild or not GemVisualRegistry.is_gameplay_texture_cache_current(
		GameConfig.DEFAULT_CELL_SIZE,
		_get_current_preview_scope()
	):
		GemVisualRegistry.ensure_gameplay_texture_cache(
			GameConfig.DEFAULT_CELL_SIZE,
			_get_current_preview_scope()
		)
		return
	_loading_progress.value = 1.0
	_create_preview_tiles()
	_refresh_report_label()


func _on_preset_selected(index: int) -> void:
	if _preset_dropdown == null:
		return
	var tile_id: StringName = _preset_dropdown.get_item_metadata(index)
	_select_preview_preset_by_tile_id(tile_id)
	_update_generate_button_labels()
	_ensure_preview_cache(true)


func _on_rebake_pressed() -> void:
	_ensure_preview_cache(true)


func _on_generate_traced_pressed() -> void:
	await _run_offline_bake_for_tile_ids(
		[_current_preview_tile_id],
		"Generating offline traced %s variants..." % _get_current_preview_name()
	)


func _on_generate_all_traced_pressed() -> void:
	if GemVisualRegistry == null:
		return
	await _run_offline_bake_for_tile_ids(
		GemVisualRegistry.get_visual_ids(),
		"Generating offline traced variants for all gems..."
	)


func _run_offline_bake_for_tile_ids(tile_ids: Array, status_text: String) -> void:
	if GemVisualRegistry == null:
		return
	if _offline_job_running:
		return
	_offline_job_running = true
	_loading_progress.value = 0.0
	_status_label.text = status_text
	_job_metrics_label.text = "Queued traced bake..."
	var job = OfflineGemBakeJobScript.new()
	job.progress_updated.connect(_on_offline_job_progress)
	var result: Dictionary = await job.run_batch_async(
		self,
		GemVisualRegistry,
		tile_ids,
		GameConfig.DEFAULT_CELL_SIZE,
		{
			"output_root": "user://traced_bakes",
			"draw_size": GameConfig.DEFAULT_CELL_SIZE,
			"sample_count": 2,
		}
	)
	if job.progress_updated.is_connected(_on_offline_job_progress):
		job.progress_updated.disconnect(_on_offline_job_progress)
	_offline_job_running = false
	_status_label.text = "Generated traced manifest at %s" % String(result.get("manifest_path", ""))
	_job_metrics_label.text = "Saved %d entries in %s" % [
		int(result.get("entry_count", 0)),
		String(result.get("manifest_path", "")),
	]
	_ensure_preview_cache(true)


func _on_bake_progress(progress_info: Dictionary) -> void:
	if _loading_progress == null or _status_label == null:
		return
	var total := maxi(int(progress_info.get("total", 0)), 1)
	var completed := maxi(int(progress_info.get("completed", 0)), 0)
	var tile_name := String(progress_info.get("tile_id", &"")).replace("_", " ").capitalize()
	var stage := String(progress_info.get("stage", "baking"))
	var progress := clampf(float(progress_info.get("progress", 0.0)), 0.0, 1.0)
	_loading_progress.value = progress
	if stage == "complete":
		_status_label.text = "Preview cache ready"
		return
	_status_label.text = "Loading offline variants %d/%d" % [completed, total]
	if not tile_name.is_empty():
		_status_label.text += "  |  %s" % tile_name
	if _job_metrics_label != null:
		_job_metrics_label.text = "Offline cache load: %d/%d (%.1f%%)" % [
			completed,
			total,
			progress * 100.0,
		]


func _on_cache_rebuilt(profile: Dictionary) -> void:
	if profile.get("cell_size", Vector2i.ZERO) != GameConfig.DEFAULT_CELL_SIZE:
		return
	_loading_progress.value = 1.0
	_status_label.text = "Preview cache ready"
	if _job_metrics_label != null and not _offline_job_running:
		_job_metrics_label.text = "Runtime cache ready"
	_create_preview_tiles()
	_refresh_report_label()


func _refresh_report_label() -> void:
	if GemVisualRegistry == null or _report_label == null:
		return
	var report := GemVisualRegistry.get_last_gameplay_bake_report()
	var backend_counts: Dictionary = report.get("backend_counts", {})
	var texture_count := int(report.get("variant_texture_count", 0))
	var total_ms := snappedf(float(report.get("total_elapsed_ms", 0.0)), 0.1)
	var current_visual: GemVisualResource = GemVisualRegistry.get_visual(_current_preview_tile_id)
	var cut_name := _format_display_name(current_visual.cut_id) if current_visual != null else "Unknown Cut"
	_report_label.text = "%s preview  |  Cut: %s  |  Cached variants: %d  |  Offline traced loads: %d  |  %.1f ms" % [
		_get_current_preview_name(),
		cut_name,
		texture_count,
		int(backend_counts.get(&"offline_traced", 0)),
		total_ms,
	]


func _create_preview_tiles() -> void:
	if _preview_stage == null:
		return
	if _static_tiles.is_empty():
		for _i in STATIC_PREVIEW_COUNT:
			var tile = TILE_VIEW_SCENE.instantiate()
			tile.use_gameplay_texture_cache = true
			tile.custom_minimum_size = STATIC_TILE_SIZE
			tile.size = STATIC_TILE_SIZE
			_preview_stage.add_child(tile)
			_static_tiles.append(tile)

		_mover = TILE_VIEW_SCENE.instantiate()
		_mover.use_gameplay_texture_cache = true
		_mover.custom_minimum_size = ACTIVE_TILE_SIZE
		_mover.size = ACTIVE_TILE_SIZE
		_preview_stage.add_child(_mover)

		_spinner = TILE_VIEW_SCENE.instantiate()
		_spinner.use_gameplay_texture_cache = true
		_spinner.custom_minimum_size = ACTIVE_TILE_SIZE
		_spinner.size = ACTIVE_TILE_SIZE
		_preview_stage.add_child(_spinner)

		_movement_caption = Label.new()
		_movement_caption.text = "Movement blend"
		_movement_caption.add_theme_font_size_override("font_size", 18)
		_preview_stage.add_child(_movement_caption)

		_movement_info = Label.new()
		_movement_info.add_theme_font_size_override("font_size", 13)
		_movement_info.add_theme_color_override("font_color", Color(0.72, 0.77, 0.87))
		_preview_stage.add_child(_movement_info)

		_rotation_caption = Label.new()
		_rotation_caption.text = "Rotation-bin animation"
		_rotation_caption.add_theme_font_size_override("font_size", 18)
		_preview_stage.add_child(_rotation_caption)

		_rotation_info = Label.new()
		_rotation_info.add_theme_font_size_override("font_size", 13)
		_rotation_info.add_theme_color_override("font_color", Color(0.72, 0.77, 0.87))
		_preview_stage.add_child(_rotation_info)

	for tile in _static_tiles:
		tile.configure_from_data(_current_preview_tile_id, _current_preview_tier, Vector2i.ZERO)
	if _mover != null:
		_mover.configure_from_data(_current_preview_tile_id, _current_preview_tier, Vector2i(1, 1))
	if _spinner != null:
		_spinner.configure_from_data(_current_preview_tile_id, _current_preview_tier, Vector2i(2, 2))

	_layout_preview_tiles()
	_start_preview_motion()
	if _rotation_timer != null and _rotation_timer.is_stopped():
		_rotation_timer.start()
	if _spinner != null:
		_spinner.play_special_rotation_animation(0.95, 1.5)


func _layout_preview_tiles() -> void:
	if _preview_stage == null:
		return
	var stage_size := _preview_stage.size
	if stage_size.x < 200.0 or stage_size.y < 200.0:
		return

	var top_left := Vector2(46, 46)
	var usable_width := maxf(stage_size.x - top_left.x * 2.0 - STATIC_TILE_SIZE.x, 1.0)
	var usable_height := maxf(stage_size.y * 0.42 - top_left.y - STATIC_TILE_SIZE.y, 1.0)
	for index in _static_tiles.size():
		var tile = _static_tiles[index]
		var column := index % STATIC_COLUMNS
		var row := index / STATIC_COLUMNS
		var x_ratio := float(column) / float(maxi(STATIC_COLUMNS - 1, 1))
		var y_ratio := float(row) / float(maxi(STATIC_ROWS - 1, 1))
		tile.position = Vector2(
			top_left.x + usable_width * x_ratio,
			top_left.y + usable_height * y_ratio
		)

	if _mover != null:
		_apply_mover_preview_uv(_mover_lighting_uv)
	if _spinner != null:
		_spinner.position = Vector2(stage_size.x - ACTIVE_TILE_SIZE.x - 120, stage_size.y * 0.58)
	if _movement_caption != null and _mover != null:
		_movement_caption.position = _mover.position + Vector2(0, -34)
	if _movement_info != null and _mover != null:
		_movement_info.position = _mover.position + Vector2(0, ACTIVE_TILE_SIZE.y + 8)
	if _rotation_caption != null and _spinner != null:
		_rotation_caption.position = _spinner.position + Vector2(-10, -34)
	if _rotation_info != null and _spinner != null:
		_rotation_info.position = _spinner.position + Vector2(-10, ACTIVE_TILE_SIZE.y + 8)


func _start_preview_motion() -> void:
	if _preview_stage == null or _mover == null:
		return
	var stage_size := _preview_stage.size
	if stage_size.x < 200.0 or stage_size.y < 200.0:
		return
	if _mover_tween != null:
		_mover_tween.kill()
	_apply_mover_preview_uv(MOVER_LIGHTING_PATH[0])
	_mover_tween = create_tween()
	_mover_tween.set_loops()
	for point_index in MOVER_LIGHTING_PATH.size() - 1:
		var from_uv: Vector2 = MOVER_LIGHTING_PATH[point_index]
		var to_uv: Vector2 = MOVER_LIGHTING_PATH[point_index + 1]
		_mover_tween.tween_method(
			_apply_mover_preview_uv,
			from_uv,
			to_uv,
			0.9
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_rotation_timer_timeout() -> void:
	if _spinner != null:
		_spinner.play_special_rotation_animation(0.95, 1.5)


func _on_preview_stage_resized() -> void:
	if _preview_stage != null:
		_preview_stage.queue_redraw()
	_layout_preview_tiles()
	_start_preview_motion()


func _process(_delta: float) -> void:
	_update_debug_readouts()


func _draw_preview_stage() -> void:
	if _preview_stage == null:
		return
	var rect := Rect2(Vector2.ZERO, _preview_stage.size)
	_preview_stage.draw_rect(rect, Color(0.04, 0.05, 0.08), true)
	var cols := 8
	var rows := 5
	for x in cols + 1:
		var px := rect.size.x * float(x) / float(cols)
		_preview_stage.draw_line(Vector2(px, 0.0), Vector2(px, rect.size.y), Color(0.12, 0.15, 0.22), 1.0, true)
	for y in rows + 1:
		var py := rect.size.y * float(y) / float(rows)
		_preview_stage.draw_line(Vector2(0.0, py), Vector2(rect.size.x, py), Color(0.12, 0.15, 0.22), 1.0, true)


func _update_debug_readouts() -> void:
	if _movement_info != null and _mover != null:
		_movement_info.text = _format_variant_state(_mover.get_debug_gameplay_variant_state())
	if _rotation_info != null and _spinner != null:
		_rotation_info.text = _format_variant_state(_spinner.get_debug_gameplay_variant_state())


func _format_variant_state(state: Dictionary) -> String:
	var entries: Array = state.get("entries", [])
	var parts: Array[String] = []
	var lighting_uv: Vector2 = state.get("lighting_uv", Vector2(-1.0, -1.0))
	if lighting_uv.x >= 0.0 and lighting_uv.y >= 0.0:
		parts.append("uv=(%.2f, %.2f)" % [lighting_uv.x, lighting_uv.y])
	if entries.is_empty():
		parts.append("No active variant entries")
		return "\n".join(parts)
	for entry in entries:
		var metadata: Dictionary = entry.get("metadata", {})
		var variant_key := String(metadata.get("variant_key", ""))
		var backend_id := String(metadata.get("backend_id", ""))
		var weight := float(entry.get("weight", 0.0))
		if variant_key.is_empty():
			variant_key = String(metadata.get("variant_cache_key", ""))
		parts.append("%s  %.2f [%s]" % [variant_key, weight, backend_id])
	return "\n".join(parts)


func _apply_mover_preview_uv(uv: Vector2) -> void:
	_mover_lighting_uv = Vector2(
		clampf(uv.x, 0.0, 1.0),
		clampf(uv.y, 0.0, 1.0)
	)
	if _mover == null:
		return
	_mover.set_debug_lighting_uv_override(_mover_lighting_uv)
	_mover.position = _lighting_uv_to_preview_position(_mover_lighting_uv)
	if _movement_caption != null:
		_movement_caption.position = _mover.position + Vector2(0, -34)
	if _movement_info != null:
		_movement_info.position = _mover.position + Vector2(0, ACTIVE_TILE_SIZE.y + 8)


func _lighting_uv_to_preview_position(uv: Vector2) -> Vector2:
	if _preview_stage == null:
		return Vector2.ZERO
	var rect := Rect2(
		Vector2(80.0, _preview_stage.size.y * 0.56),
		Vector2(
			maxf(_preview_stage.size.x - ACTIVE_TILE_SIZE.x - 160.0, 1.0),
			maxf(_preview_stage.size.y * 0.3, 1.0)
		)
	)
	return Vector2(
		rect.position.x + rect.size.x * uv.x,
		rect.position.y + rect.size.y * uv.y
	)


func _get_current_preview_scope() -> Array:
	return [_current_preview_tile_id]


func _get_current_preview_name() -> String:
	return _format_display_name(_current_preview_tile_id)


func _resolve_preview_tier(tile_id: StringName) -> int:
	if TileRegistry == null or not TileRegistry.has_definitions():
		return DEFAULT_PREVIEW_TIER
	var tile_def := TileRegistry.get_definition(tile_id)
	if tile_def == null:
		return DEFAULT_PREVIEW_TIER
	return tile_def.tier


func _format_display_name(value) -> String:
	return String(value).replace("_", " ").capitalize()


func _format_preset_label(tile_id: StringName, tier: int, cut_id: StringName) -> String:
	var parts: Array[String] = [_format_display_name(tile_id)]
	if tier > 0:
		parts.append("T%d" % tier)
	if cut_id != &"":
		parts.append(_format_display_name(cut_id))
	return " | ".join(parts)


func _update_generate_button_labels() -> void:
	if _generate_traced_button != null:
		_generate_traced_button.text = "Trace %s" % _get_current_preview_name()


func _on_offline_job_progress(progress: Dictionary) -> void:
	if _loading_progress == null or _status_label == null:
		return
	var stage := String(progress.get("stage", ""))
	var completed := int(progress.get("completed", 0))
	var total := int(progress.get("total", 0))
	var progress_value := float(progress.get("progress", 0.0))
	var elapsed_ms := float(progress.get("elapsed_ms", 0.0))
	var variant_elapsed_ms := float(progress.get("variant_elapsed_ms", 0.0))
	var tile_id := String(progress.get("tile_id", &"")).replace("_", " ").capitalize()
	var variant_key := String(progress.get("variant_key", ""))
	_loading_progress.value = progress_value
	match stage:
		"queued":
			_status_label.text = "Queued %d traced variants" % total
			_job_metrics_label.text = "Output: %s" % String(progress.get("output_root", ""))
		"baking":
			_status_label.text = "Tracing variant %d/%d" % [completed + 1, maxi(total, 1)]
			if not tile_id.is_empty():
				_status_label.text += "  |  %s" % tile_id
			_job_metrics_label.text = "%s  |  elapsed %.1f ms" % [variant_key, elapsed_ms]
		"baked", "skipped":
			_status_label.text = "Processed %d/%d traced variants" % [completed, maxi(total, 1)]
			_job_metrics_label.text = "%s  |  last %.1f ms  |  total %.1f ms  |  status=%s" % [
				variant_key,
				variant_elapsed_ms,
				elapsed_ms,
				String(progress.get("status", stage)),
			]
		"complete":
			_status_label.text = "Offline traced bake complete"
			_job_metrics_label.text = "Saved %d entries in %.1f ms" % [
				int(progress.get("saved_entries", 0)),
				elapsed_ms,
			]
		"error":
			_status_label.text = "Offline traced bake failed"
			_job_metrics_label.text = String(progress.get("status", "error"))
