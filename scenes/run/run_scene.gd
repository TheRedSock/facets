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
@export var room_mode := false
var _room_panel: RoomPanel
var _hud_model: Dictionary = {}
var _selected_tool := ""
var _tool_cells: Array[Vector2i] = []
var _preview_command: RoomCommand
var _inspection := Vector2i(-1,-1)
var _work_surface: WorkSurface
var _audio: RoomAudio
var _mute_button: Button

func _ready() -> void:
	TranslationServer.add_translation(preload("res://data/localization/en.tres"))
	_audio = RoomAudio.new(); add_child(_audio)
	board_scene.presentation_cue.connect(func(cue: String) -> void:
		if run_controller.run_state != null and run_controller.run_state.room != null: _audio.play(cue))
	_work_surface = WorkSurface.new(); _work_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_work_surface); move_child(_work_surface,0); _work_surface.visible = false
	run_controller.board_changed.connect(_on_board_changed)
	run_controller.run_state_changed.connect(_on_run_state_changed)
	board_scene.swap_requested.connect(_on_swap_requested)
	board_scene.cell_pressed.connect(_on_cell_pressed)
	board_scene.selection_canceled.connect(_cancel_selection)
	board_scene.delivery_failed.connect(_show_delivery_error)
	_debug_panel = DebugPanel.new()
	_debug_panel.anchor_right = 1.0; _debug_panel.anchor_bottom = 1.0
	_debug_panel.offset_left = 16; _debug_panel.offset_top = 40; _debug_panel.offset_right = -16; _debug_panel.offset_bottom = -16
	add_child(_debug_panel)
	_debug_panel.visibility_changed.connect(func() -> void: board_scene.set_input_gate("modal",_debug_panel.visible))
	_back_button = _button("Menu",8,_on_back_pressed)
	_restart_button = _button("Restart",96,_on_restart_pressed)
	_skip_button = _button("Skip",184,skip_playback)
	_mute_button = _button("Sound",272,_toggle_sound)
	_mute_button.disabled = _audio.streams.is_empty()
	_mute_button.tooltip_text = "Sound candidates await listening review." if _audio.streams.is_empty() else "Mute game sounds"
	var volume := HSlider.new(); volume.position = Vector2(364,10); volume.size = Vector2(110,24)
	volume.min_value = 0; volume.max_value = 1; volume.step = 0.05; volume.value = RoomAudio.volume
	volume.tooltip_text = "Sound volume"; volume.editable = not _audio.streams.is_empty()
	volume.value_changed.connect(_audio.set_volume); add_child(volume)
	_room_panel = RoomPanel.new()
	_room_panel.anchor_left = 1.0; _room_panel.anchor_right = 1.0; _room_panel.anchor_bottom = 1.0
	_room_panel.offset_left = -376; _room_panel.offset_right = -16; _room_panel.offset_top = 88; _room_panel.offset_bottom = -16
	add_child(_room_panel)
	_room_panel.begin_requested.connect(_begin_room)
	_room_panel.tool_selected.connect(_select_tool)
	_room_panel.confirm_requested.connect(_confirm_target)
	_room_panel.cancel_requested.connect(_cancel_selection)
	_room_panel.hint_requested.connect(_show_hint)
	_room_panel.preview("",false,false)
	call_deferred("_start_run")

func _button(label: String,x: float,callback: Callable) -> Button:
	var button := Button.new(); button.text = label; button.position = Vector2(x,4)
	button.custom_minimum_size = Vector2(80,32); button.pressed.connect(callback); add_child(button)
	return button

func _on_board_changed(board: BoardState) -> void:
	_audio.cancel()
	_delivery_generation += 1; var generation := _delivery_generation
	_playback_generation += 1
	board_scene.cancel_action_playback(false)
	_cancel_selection(); _hud_model = {}
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
	var state := run_controller.run_state
	var command: Variant = RoomCommand.exchange(state,a,b) if state.room != null else SwapCommand.new(a,b)
	await _submit_command(command)

func _submit_command(command: Variant, begin: bool = false) -> void:
	if board_scene.input_is_locked() and not (begin and board_scene._input_gates.keys().all(func(key: String) -> bool: return key == "briefing")): return
	_playback_generation += 1; var token := _playback_generation
	board_scene.set_input_gate("playback",true,token)
	_audio.cancel()
	_update_hud()
	var started := Time.get_ticks_usec()
	var result := run_controller.apply_action(command)
	_last_sim_ms = (Time.get_ticks_usec() - started) / 1000.0
	if not result.ok:
		_audio.play("ui_reject")
		if result.status == "failed":
			_resolution_error = result.code; board_scene.set_input_gate("error",true)
		elif command.to_dict().has("origin"): await board_scene.play_rejected_swap(command.to_dict().origin,command.to_dict().destination)
		if token != _playback_generation or not is_inside_tree(): return
		board_scene.set_input_gate("playback",false,token); _update_hud(); return
	# State/cost/RNG/checkpoints are already committed before the first await.
	if command is RoomCommand and command.data.kind != "swap": _audio.play("ui_accept")
	_cancel_selection()
	started = Time.get_ticks_usec()
	await board_scene.play_committed_action(result,instant_playback)
	if token != _playback_generation or not is_inside_tree(): return
	_last_anim_ms = (Time.get_ticks_usec() - started) / 1000.0
	_last_cascade_steps = result.timeline.cascade_depth
	run_controller.acknowledge(result.action_id,result.generation)
	board_scene.set_input_gate("playback",false,token)
	_update_hud()
	if run_controller.run_state.phase in ["complete","failed"]: _audio.play("room_success" if run_controller.run_state.phase == "complete" else "room_failure")
	if begin: board_scene.grab_focus()

func _begin_room() -> void:
	await _submit_command(RoomCommand.begin(run_controller.run_state.revision),true)

func _select_tool(kind: String) -> void:
	if board_scene.input_is_locked(): return
	_audio.play("ui_nav")
	_cancel_selection(); _selected_tool = kind; board_scene.target_mode = true
	_room_panel.preview(RoomPanel.HELP[kind]+" Select a target, then confirm.",false,true)
	board_scene.grab_focus()

func _cancel_selection() -> void:
	_selected_tool = ""; _tool_cells.clear(); _preview_command = null
	if is_instance_valid(board_scene):
		board_scene.target_mode = false; board_scene._deselect(); board_scene.set_targets([])
	if is_instance_valid(_room_panel): _room_panel.preview("",false,false)

func _on_cell_pressed(cell: Vector2i) -> void:
	_inspection = cell; _update_hud()
	if _selected_tool.is_empty(): return
	var state := run_controller.run_state
	if _selected_tool == "action.exchange":
		if _tool_cells.size() >= 2: _tool_cells.clear()
		_tool_cells.append(cell); board_scene.set_targets(_tool_cells)
		if _tool_cells.size() < 2:
			_room_panel.preview("Select an adjacent gem to exchange with this one.",false,true); return
		_preview_command = RoomCommand.exchange(state,_tool_cells[0],_tool_cells[1],true)
	else:
		_tool_cells.assign([cell]); board_scene.set_targets(_tool_cells)
		var layer := "gem"
		if _selected_tool == "action.clear_target":
			if not state.board.obstacle_at(cell).is_empty(): layer = "obstacle"
			elif not state.board.get_cell(cell).lock.is_empty(): layer = "lock"
		_preview_command = RoomCommand.target(state,_selected_tool,cell,layer)
	var legal := run_controller.can_apply_action(_preview_command)
	var text := "%s · %d Craft · no Work\n%s" % [RoomPanel.NAMES[_selected_tool],RoomActionLegality.cost(_selected_tool,state.rules),
		"Exchange these two gems." if _selected_tool == "action.exchange" else ("Target: "+_preview_command.data.layer)]
	if not legal.ok: text += "\n"+_target_reason(legal.code)
	_room_panel.preview(text,legal.ok,true)

func _target_reason(code: String) -> String:
	match code:
		"not_adjacent": return "Choose two adjacent gems."
		"clear_tier_limit": return "Chisel removes only tier 1–3 gems."
		"promote_tier_limit": return "Refine targets only tier 1–4 gems."
		"insufficient_craft": return "Not enough Craft."
		"movement_locked": return "That gem cannot move."
	return "Choose a legal target for this tool."

func _confirm_target() -> void:
	if _preview_command == null: return
	await _submit_command(_preview_command)

func _show_hint() -> void:
	if board_scene.input_is_locked(): return
	_cancel_selection()
	var swaps := run_controller.enumerate_legal_swaps()
	if swaps.is_empty():
		_room_panel.preview("No matching swap. Use an available tool to change the board.",false,false); return
	board_scene.set_targets([swaps[0].origin,swaps[0].destination])
	_room_panel.preview("These two gems can make a match. Try choosing which one should survive.",false,false)
	board_scene.cursor_cell = swaps[0].origin; board_scene.grab_focus()

func skip_playback() -> void:
	_audio.cancel()
	var prior := _playback_generation; _playback_generation += 1
	board_scene.cancel_action_playback()
	board_scene.set_input_gate("playback",false,prior)
	_update_hud()

func _toggle_sound() -> void:
	_audio.set_muted(not RoomAudio.muted)
	_mute_button.text = "Muted" if RoomAudio.muted else "Sound"
	if not RoomAudio.muted: _audio.play("ui_nav")

func _update_hud() -> void:
	if hud_label == null: return
	if not _delivery_error.is_empty(): hud_label.text = "Cannot load gem assets: " + _delivery_error; return
	if not _resolution_error.is_empty(): hud_label.text = "Action failed: " + _resolution_error + " — Restart or Menu"; return
	if _delivery_loading: hud_label.text = "Preparing gem assets…"; return
	var state := run_controller.get_run_state()
	if state == null: return
	var is_room := state.room != null
	_room_panel.visible = is_room
	board_scene.offset_right = -392 if is_room else 0
	board_scene.offset_top = 88 if is_room else 36
	board_scene.offset_bottom = -16 if is_room else 0
	if is_room:
		theme = preload("res://assets/ui/themes/workshop.tres")
		_work_surface.visible = true; get_node("Background").visible = false
		var playing := board_scene._input_gates.has("playback")
		if not playing or _hud_model.is_empty(): _hud_model = RoomHudModel.build(state,_inspection)
		_room_panel.present(_hud_model,playing or _delivery_loading)
		hud_label.text = tr("hud.resources").format({"work":_hud_model.work,"craft":_hud_model.craft,"capacity":_hud_model.capacity})
		hud_label.offset_top = 42; hud_label.offset_bottom = 80
		board_scene.set_input_gate("briefing",state.phase == "briefing")
		board_scene.set_input_gate("terminal",state.phase in ["complete","failed"])
		return
	board_scene.set_input_gate("briefing",false); board_scene.set_input_gate("terminal",false)
	_work_surface.visible = false; get_node("Background").visible = true
	hud_label.offset_top = 4; hud_label.offset_bottom = 32
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
	_audio.cancel()
	_delivery_error = message; _delivery_loading = false
	_playback_generation += 1
	board_scene.set_input_gate("error",true)
	board_scene.cancel_action_playback(false)
	board_scene.visible = false
	_update_hud()

func _start_run() -> void:
	var started := run_controller.start_room(null,7) if room_mode else run_controller.start_new_run({"seed":randi_range(1,999999)})
	if not started:
		_resolution_error = run_controller.last_error
		board_scene.set_input_gate("error",true)
		_update_hud()

func _exit_tree() -> void:
	_delivery_generation += 1; _playback_generation += 1
	if is_instance_valid(board_scene): board_scene.cancel_action_playback(false)
