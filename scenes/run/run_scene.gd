class_name RunScene
extends Control

@onready var board_scene: BoardScene = %BoardScene
@onready var hud_label: Label = %HudLabel

var run_controller := RunController.new()
var _debug_panel: DebugPanel
var _back_button: Button

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

	call_deferred("_start_run")


func _exit_tree() -> void:
	# GemForge owns clip memory for now; nothing to release per-run.
	pass



func _process(_delta: float) -> void:
	_update_hud()


func _on_board_changed(board: BoardState) -> void:
	board_scene.set_board_state(board)
	_ensure_forge_clips()


func _on_run_state_changed(_run_state: RunState) -> void:
	_update_hud()


func _on_swap_requested(cell_a: Vector2i, cell_b: Vector2i) -> void:
	board_scene._input_locked = true

	# ---- Validate swap (fast: swap + find_matches, <1ms) ----
	var validate_start_usec := Time.get_ticks_usec()
	var valid := run_controller.begin_swap(cell_a, cell_b)
	_last_sim_ms = (Time.get_ticks_usec() - validate_start_usec) / 1000.0

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
	var resolve_start_usec := Time.get_ticks_usec()
	var timeline := run_controller.resolve_remaining_cascades()
	var total_sim_ms := (Time.get_ticks_usec() - resolve_start_usec) / 1000.0
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
	var fps := "%d FPS" % Engine.get_frames_per_second()
	var perf_detail := ""
	if _last_sim_ms > 0.0:
		perf_detail = "  |  sim %.1fms/%d  anim %.0fms" % [
			_last_sim_ms, _last_cascade_steps, _last_anim_ms]
	hud_label.text = "Moves: %d  |  Seed: %d  |  %s%s" % [
		rs.moves_remaining, rs.run_seed, fps, perf_detail]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


## Queues background baking for any of the run's gems whose clips are not
## cached yet. GemForge is lazy and non-blocking; cache hits are skipped.
## Resolved by path, not identifier: compile-time autoload identifiers break
## --script tool mode and headless tests.
func _ensure_forge_clips() -> void:
	var forge := get_node_or_null("/root/GemForge")
	if forge == null:
		return
	var rs := run_controller.get_run_state()
	var ids: Array = []
	for tier_key in rs.tier_tile_ids:
		var tid: StringName = rs.tier_tile_ids[tier_key]
		if tid != &"":
			ids.append(tid)
	forge.ensure_required(ids)


func _start_run() -> void:
	var run_config := GameConfig.default_run_config()
	run_config["seed"] = randi_range(1, 999999)
	if TileRegistry != null:
		TileRegistry.preload_runtime_assets()
	run_controller.start_new_run(run_config)
