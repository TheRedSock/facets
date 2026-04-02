class_name RunScene
extends Control

@onready var board_scene: BoardScene = %BoardScene
@onready var hud_label: Label = %HudLabel

var run_controller := RunController.new()
var _debug_panel: DebugPanel
var _back_button: Button
var _loading_overlay: Control
var _loading_title: Label
var _loading_status: Label
var _loading_progress: ProgressBar
var _pending_run_config: Dictionary = {}
var _runtime_preload_active := false

## Tracks the last swap's timing breakdown for the HUD perf line.
var _last_sim_ms := 0.0
var _last_anim_ms := 0.0
var _last_cascade_steps := 0


func _ready() -> void:
	run_controller.board_changed.connect(_on_board_changed)
	run_controller.run_state_changed.connect(_on_run_state_changed)

	board_scene.swap_requested.connect(_on_swap_requested)

	# Debug panel — toggle with F1 (full-screen overlay)
	_debug_panel = DebugPanel.new()
	_debug_panel.anchor_right = 1.0
	_debug_panel.anchor_bottom = 1.0
	_debug_panel.offset_left = 16.0
	_debug_panel.offset_top = 40.0
	_debug_panel.offset_right = -16.0
	_debug_panel.offset_bottom = -16.0
	add_child(_debug_panel)

	# Back to Menu button — top-left corner
	_back_button = Button.new()
	_back_button.text = "Menu"
	_back_button.custom_minimum_size = Vector2(80, 32)
	_back_button.position = Vector2(8, 4)
	_back_button.add_theme_font_size_override("font_size", 14)
	_back_button.pressed.connect(_on_back_pressed)
	add_child(_back_button)

	_build_loading_overlay()
	board_scene.visible = false
	call_deferred("_begin_runtime_preload")


func _exit_tree() -> void:
	if GemVisualRegistry != null and GemVisualRegistry.gameplay_texture_bake_progress.is_connected(_on_gameplay_texture_bake_progress):
		GemVisualRegistry.gameplay_texture_bake_progress.disconnect(_on_gameplay_texture_bake_progress)


func _process(_delta: float) -> void:
	_update_hud()


func _on_board_changed(board: BoardState) -> void:
	board_scene.set_board_state(board)


func _on_run_state_changed(_run_state: RunState) -> void:
	_update_hud()


func _on_swap_requested(cell_a: Vector2i, cell_b: Vector2i) -> void:
	board_scene._input_locked = true

	# ---- Validate swap (fast: swap + find_matches, <1ms) ----
	PerfMonitor.begin_span("swap_validate")
	var valid := run_controller.begin_swap(cell_a, cell_b)
	PerfMonitor.end_span("swap_validate")

	if not valid:
		await board_scene.animate_invalid_swap(cell_a, cell_b)
		board_scene._input_locked = false
		return

	var anim_start := Time.get_ticks_usec()
	await board_scene.animate_swap(cell_a, cell_b)
	_update_hud()

	# Let the swap settle visually, then spend the first simulation burst while
	# the board is static instead of before the swap movement begins.
	await get_tree().process_frame

	# Resolve the full authoritative timeline up front so the renderer can
	# opportunistically overlap independent regions without changing outcomes.
	PerfMonitor.begin_span("resolve_authoritative_timeline")
	var timeline := run_controller.resolve_remaining_cascades()
	var total_sim_ms := PerfMonitor.end_span("resolve_authoritative_timeline")
	var step_count := timeline.cascade_depth if timeline != null else 0

	await board_scene.play_authoritative_async_timeline(timeline)
	_last_sim_ms = total_sim_ms
	_last_anim_ms = (Time.get_ticks_usec() - anim_start) / 1000.0
	_last_cascade_steps = step_count

	run_controller.finalize_swap()
	board_scene._input_locked = false


func _update_hud() -> void:
	if hud_label == null:
		return
	var rs := run_controller.get_run_state()
	var fps := PerfMonitor.fps_text if PerfMonitor != null else ""
	var perf_detail := ""
	if _last_sim_ms > 0.0:
		perf_detail = "  |  sim %.1fms/%d  anim %.0fms" % [
			_last_sim_ms, _last_cascade_steps, _last_anim_ms]
	hud_label.text = "Moves: %d  |  Seed: %d  |  %s%s" % [
		rs.moves_remaining, rs.run_seed, fps, perf_detail]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _begin_runtime_preload() -> void:
	_runtime_preload_active = true
	_pending_run_config = GameConfig.default_run_config()
	_pending_run_config["seed"] = randi_range(1, 999999)
	var preload_cell_size := GameConfig.DEFAULT_CELL_SIZE
	if board_scene != null:
		preload_cell_size = board_scene.estimate_cell_size(
			_pending_run_config.get("board_size", GameConfig.DEFAULT_BOARD_SIZE)
		)
	_set_loading_state("Loading offline gem textures...", "Scanning baked gem manifest", 0.02)
	if GemVisualRegistry != null and not GemVisualRegistry.gameplay_texture_bake_progress.is_connected(_on_gameplay_texture_bake_progress):
		GemVisualRegistry.gameplay_texture_bake_progress.connect(_on_gameplay_texture_bake_progress)
	PerfMonitor.begin_span("runtime_preload")
	if TileRegistry != null:
		TileRegistry.preload_runtime_assets()
	if GemVisualRegistry != null:
		GemVisualRegistry.set_gameplay_bake_backend_preference(
			GemVisualRegistry.GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED
		)
		GemVisualRegistry.set_gameplay_runtime_bake_fallback_enabled(false)
		GemVisualRegistry.preload_runtime_assets([preload_cell_size])
		if not GemVisualRegistry.is_gameplay_texture_cache_current(preload_cell_size):
			GemVisualRegistry.gameplay_texture_cache_rebuilt.connect(
				_on_runtime_preload_ready,
				CONNECT_ONE_SHOT
			)
			GemVisualRegistry.ensure_gameplay_texture_cache(preload_cell_size)
			return
	_finish_runtime_preload()


func _on_runtime_preload_ready(_profile: Dictionary) -> void:
	_finish_runtime_preload()


func _finish_runtime_preload() -> void:
	_set_loading_state("Starting run...", "Offline gem textures ready", 1.0)
	PerfMonitor.end_span("runtime_preload")
	get_tree().process_frame.connect(_start_run_after_preload, CONNECT_ONE_SHOT)


func _start_run_after_preload() -> void:
	run_controller.start_new_run(_pending_run_config)
	board_scene.visible = true
	_runtime_preload_active = false
	if _loading_overlay != null:
		_loading_overlay.visible = false


func _build_loading_overlay() -> void:
	_loading_overlay = Control.new()
	_loading_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(_loading_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.06, 0.92)
	shade.mouse_filter = MOUSE_FILTER_STOP
	_loading_overlay.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 180)
	center.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.18, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.32, 0.44, 0.64, 0.9)
	style.set_corner_radius_all(14)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	_loading_title = Label.new()
	_loading_title.text = "Loading Run"
	_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title.add_theme_font_size_override("font_size", 28)
	content.add_child(_loading_title)

	_loading_status = Label.new()
	_loading_status.text = "Loading offline gem textures"
	_loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_status.add_theme_font_size_override("font_size", 16)
	content.add_child(_loading_status)

	_loading_progress = ProgressBar.new()
	_loading_progress.min_value = 0.0
	_loading_progress.max_value = 1.0
	_loading_progress.step = 0.001
	_loading_progress.show_percentage = true
	_loading_progress.value = 0.0
	_loading_progress.custom_minimum_size = Vector2(0, 28)
	content.add_child(_loading_progress)


func _set_loading_state(title: String, status: String, progress: float) -> void:
	if _loading_overlay == null:
		return
	_loading_overlay.visible = true
	if _loading_title != null:
		_loading_title.text = title
	if _loading_status != null:
		_loading_status.text = status
	if _loading_progress != null:
		_loading_progress.value = clampf(progress, 0.0, 1.0)


func _on_gameplay_texture_bake_progress(progress_info: Dictionary) -> void:
	if not _runtime_preload_active:
		return
	var total := maxi(int(progress_info.get("total", 0)), 1)
	var completed := maxi(int(progress_info.get("completed", 0)), 0)
	var tile_id := String(progress_info.get("tile_id", &"")).replace("_", " ").capitalize()
	var stage := String(progress_info.get("stage", "baking"))
	var progress := float(progress_info.get("progress", 0.0))
	var status := "Loading offline gem textures %d/%d" % [completed, total]
	if not tile_id.is_empty():
		status += "  |  %s" % tile_id
	if stage == "complete":
		status = "Offline gem textures ready"
	_set_loading_state("Loading Run", status, progress)
