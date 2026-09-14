class_name RunScene
extends Control
@onready var board_scene: BoardScene = %BoardScene
@onready var hud_label: Label = %HudLabel
var run_controller := RunController.new()
var _debug_panel: DebugPanel
var _back_button: Button
var _skip_button: Button
var _restart_button: Button
var _last_sim_ms := 0.0
var _last_anim_ms := 0.0
var _last_cascade_steps := 0
var _delivery_error := ""
var _delivery_loading := false
var _delivery_generation := 0
var _playback_generation := 0
var _resolution_error := ""
var instant_playback := false

func _ready() -> void:
	run_controller.board_changed.connect(_on_board_changed)
	run_controller.run_state_changed.connect(_on_run_state_changed)
	board_scene.swap_requested.connect(_on_swap_requested)
	board_scene.delivery_failed.connect(_show_delivery_error)
	_debug_panel = DebugPanel.new()
	_debug_panel.anchor_right = 1.0; _debug_panel.anchor_bottom = 1.0
	_debug_panel.offset_left = 16; _debug_panel.offset_top = 40; _debug_panel.offset_right = -16; _debug_panel.offset_bottom = -16
	add_child(_debug_panel)
	_debug_panel.visibility_changed.connect(func() -> void: board_scene.set_input_gate("modal",_debug_panel.visible))
	_back_button = _button("Menu",8,_on_back_pressed)
	_restart_button = _button("Restart",96,_on_restart_pressed)
	_skip_button = _button("Skip",184,skip_playback)
	call_deferred("_start_run")

func _button(label: String,x: float,callback: Callable) -> Button:
	var button := Button.new(); button.text = label; button.position = Vector2(x,4)
	button.custom_minimum_size = Vector2(80,32); button.pressed.connect(callback); add_child(button)
	return button

func _on_board_changed(board: BoardState) -> void:
	_delivery_generation += 1; var generation := _delivery_generation
	_playback_generation += 1
	board_scene.cancel_action_playback(false)
	board_scene.reset_input_gates()
	board_scene.set_input_gate("modal",_debug_panel != null and _debug_panel.visible)
	_delivery_error = ""; _resolution_error = ""; _delivery_loading = true
	board_scene.visible = false; board_scene.set_input_gate("loading",true,generation)
	_update_hud()
	var prepared := await _prepare_forge_clips()
	if generation != _delivery_generation or not is_inside_tree(): return
	_delivery_loading = false
	if not prepared:
		var forge := get_node_or_null("/root/GemForge")
		_show_delivery_error(forge.last_error if forge != null else "Gem delivery service is unavailable")
		return
	board_scene.set_board_state(board.duplicate_board())
	await get_tree().process_frame
	if generation != _delivery_generation or not is_inside_tree() or not _delivery_error.is_empty(): return
	board_scene.visible = true; board_scene.set_input_gate("loading",false,generation)
	_update_hud()

func _on_run_state_changed(_state: RunState) -> void:
	_update_hud()

func _on_swap_requested(a: Vector2i,b: Vector2i) -> void:
	if board_scene.input_is_locked(): return
	_playback_generation += 1; var token := _playback_generation
	board_scene.set_input_gate("playback",true,token)
	var started := Time.get_ticks_usec()
	var result := run_controller.apply_action(SwapCommand.new(a,b))
	_last_sim_ms = (Time.get_ticks_usec() - started) / 1000.0
	if not result.ok:
		if result.status == "failed":
			_resolution_error = result.code; board_scene.set_input_gate("error",true)
		else: await board_scene.play_rejected_swap(a,b)
		if token != _playback_generation or not is_inside_tree(): return
		board_scene.set_input_gate("playback",false,token); _update_hud(); return
	# State/cost/RNG/checkpoints are already committed before the first await.
	started = Time.get_ticks_usec()
	await board_scene.play_committed_action(result,instant_playback)
	if token != _playback_generation or not is_inside_tree(): return
	_last_anim_ms = (Time.get_ticks_usec() - started) / 1000.0
	_last_cascade_steps = result.timeline.cascade_depth
	run_controller.acknowledge(result.action_id,result.generation)
	board_scene.set_input_gate("playback",false,token)
	_update_hud()

func skip_playback() -> void:
	var prior := _playback_generation; _playback_generation += 1
	board_scene.cancel_action_playback()
	board_scene.set_input_gate("playback",false,prior)
	_update_hud()

func _update_hud() -> void:
	if hud_label == null: return
	if not _delivery_error.is_empty(): hud_label.text = "Cannot load gem assets: " + _delivery_error; return
	if not _resolution_error.is_empty(): hud_label.text = "Action failed: " + _resolution_error + " — Restart or Menu"; return
	if _delivery_loading: hud_label.text = "Preparing gem assets…"; return
	var state := run_controller.get_run_state()
	if state == null: return
	var status := ""
	if state.phase == "budget_exhausted": status = " | No moves remaining — Restart"
	elif state.phase == "no_legal_swaps": status = " | No legal swaps — Restart"
	hud_label.text = "Moves: %d | Seed: %d%s | sim %.1fms / anim %.0fms" % [state.moves_remaining,state.run_seed,status,_last_sim_ms,_last_anim_ms]

func _on_back_pressed() -> void:
	_delivery_generation += 1; _playback_generation += 1
	board_scene.cancel_action_playback(false)
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

func _on_restart_pressed() -> void:
	if not run_controller.restart():
		_resolution_error = run_controller.last_error; _update_hud()

func _prepare_forge_clips() -> bool:
	var forge := get_node_or_null("/root/GemForge")
	var state := run_controller.get_run_state()
	if forge == null or state == null: return false
	return await forge.prepare_required(state.catalog.roster())

func _show_delivery_error(message: String) -> void:
	_delivery_error = message; _delivery_loading = false
	_playback_generation += 1
	board_scene.set_input_gate("error",true)
	board_scene.cancel_action_playback(false)
	board_scene.visible = false
	_update_hud()

func _start_run() -> void:
	if not run_controller.start_new_run({"seed":randi_range(1,999999)}):
		_resolution_error = run_controller.last_error
		board_scene.set_input_gate("error",true)
		_update_hud()

func _exit_tree() -> void:
	_delivery_generation += 1; _playback_generation += 1
	if is_instance_valid(board_scene): board_scene.cancel_action_playback(false)
