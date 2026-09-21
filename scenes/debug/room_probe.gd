class_name RoomProbe
extends Node
## Opt-in real-executable room probe. Ordinary Play does not execute this code.
var failures: Array = []
var _frames: Array = []
var _active := false
var _previous := 0
var _input_us := 0
var _first_response := -1
var _watch: TileView
var _watch_position := Vector2.ZERO
var _watch_scale := Vector2.ONE
var _watched_board: BoardScene

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _active:
		_frames.append((now-_previous)/1000.0)
		if _first_response < 0 and ((is_instance_valid(_watch) and (_watch.position != _watch_position or _watch.scale != _watch_scale or _watch.modulate.a < 1.0)) or (is_instance_valid(_watched_board) and _watched_board.impact_alpha > 0)):
			_first_response = now-_input_us
	_previous = now

func run(path: String) -> void:
	var start := Time.get_ticks_usec()
	var scene: RunScene = load("res://scenes/run/run_scene.tscn").instantiate()
	scene.room_mode = true; get_tree().root.add_child(scene)
	for frame in 600:
		await get_tree().process_frame
		if scene.board_scene.visible and not scene._delivery_loading: break
	if not scene.board_scene.visible:
		failures.append("room_delivery/"+scene._delivery_error); _finish(path,{}); return
	var report := {"schema":"facets-room-probe-v1","godot":Engine.get_version_info().string,
		"executable":OS.get_executable_path(),"editor":OS.has_feature("editor"),"seed":7,
		"cpu":OS.get_processor_name(),"os":OS.get_name(),"fps_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),
		"mode":"atomic_concurrent","loading_ms":(Time.get_ticks_usec()-start)/1000.0,"actions":[]}
	var pictures := "--room-screenshots" in OS.get_cmdline_user_args()
	if pictures: await _picture(path,"briefing")
	await scene._begin_room()
	if pictures: await _picture(path,"ready")
	var initial_digest := scene.run_controller.run_state.digest()
	for frame in 30: await get_tree().process_frame
	var forge := get_node("/root/GemForge")
	var warm_loads: int = forge.delivery_report().page_loads
	report.memory = _memory(scene)
	var timings: Array = []; var queries: Array = []
	for turn in 40:
		var state := scene.run_controller.run_state
		if state.phase != "ready": break
		start = Time.get_ticks_usec()
		var tools := RoomActionLegality.tools(state)
		var swaps := scene.run_controller.enumerate_legal_swaps()
		queries.append((Time.get_ticks_usec()-start)/1000.0)
		var command: RoomCommand
		if not tools.is_empty() and (turn%3 == 0 or swaps.is_empty()): command = tools[(7+turn*17)%tools.size()]
		elif not swaps.is_empty():
			var swap := swaps[(7+turn*13)%swaps.size()]; command = RoomCommand.exchange(state,swap.origin,swap.destination)
		else: failures.append("ready_without_actions"); break
		_watch = scene.board_scene._tile_views.get(command.data.get("origin",command.data.get("cell",Vector2i(-1,-1))))
		if is_instance_valid(_watch): _watch_position = _watch.position; _watch_scale = _watch.scale
		_watched_board = scene.board_scene; _first_response = -1; _input_us = Time.get_ticks_usec(); _previous = _input_us; _active = true
		await scene._submit_command(command)
		_active = false
		var result := scene.run_controller.last_result
		if not scene.run_controller.last_error.is_empty(): failures.append(scene.run_controller.last_error); break
		timings.append(scene._last_sim_ms)
		report.actions.append({"kind":command.data.kind,"sim_ms":scene._last_sim_ms,"playback_ms":scene._last_anim_ms,"input_to_view_change_ms":_first_response/1000.0,
			"state_digest":result.state_digest,"event_digest":result.event_digest})
		if scene.board_scene._board_state.digest() != scene.run_controller.get_board().digest(): failures.append("view_mismatch")
		if pictures and turn == 3: await _picture(path,"progress")
	var state := scene.run_controller.run_state
	report.phase = state.phase; report.reason = state.room.failure_reason; report.work = state.moves_remaining
	report.recoveries = state.room.recovery_count; report.remaining = state.room.remaining(state.board)
	report.simulation = _stats(timings); report.legal_query = _stats(queries); report.frames = _stats(_frames)
	report.raw_frame_ms = _frames.duplicate(); report.extra_page_loads = int(forge.delivery_report().page_loads)-warm_loads
	if report.extra_page_loads != 0: failures.append("warmed_burst_cold_loads")
	report.target_5ms_met = report.simulation.get("p95",999) <= 5.0
	report.target_16_7ms_met = report.frames.get("p95",999) <= 16.7
	if state.phase not in ["complete","failed"]: failures.append("room_did_not_finish")
	if not ReplayRecord.verify(scene.run_controller.export_replay()).ok: failures.append("room_replay")
	var replay := FileAccess.open(path+".replay",FileAccess.WRITE)
	replay.store_buffer(CanonicalCodec.encode(scene.run_controller.export_replay()))
	if pictures: await _picture(path,"result")
	scene._on_restart_pressed()
	for frame in 120:
		await get_tree().process_frame
		if scene.board_scene.visible and not scene._delivery_loading and not scene.board_scene._input_gates.has("loading"): break
	await scene._begin_room()
	if scene.run_controller.run_state.digest() != initial_digest: failures.append("restart_identity")
	report.functional_tools = await _functional_tools(scene)
	report.audio_cues = scene._audio.streams.size()
	report.audio_cues_played = scene._audio.cues_played
	if scene._audio.streams.size() != 10 or scene._audio.cues_played == 0: failures.append("runtime_audio_cues")
	scene._toggle_sound()
	if not RoomAudio.muted or scene._audio.voices.any(func(v: AudioStreamPlayer) -> bool: return v.playing): failures.append("runtime_mute")
	scene._toggle_sound(); scene._audio.cancel()
	scene.queue_free(); await get_tree().process_frame; await get_tree().process_frame
	scene = null
	# Let the audio mixer consume stop requests before the probe quits the process.
	await get_tree().create_timer(0.2).timeout
	_finish(path,report)

func _memory(scene: RunScene) -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/workshop_manifest.json"))
	var texture_bytes := 0; var audio_bytes := 0
	for path in manifest.resources:
		if path.ends_with(".svg"):
			var texture: Texture2D = load(path)
			texture_bytes += texture.get_width()*texture.get_height()*4
	for stream in scene._audio.streams.values():
		if stream is AudioStreamWAV: audio_bytes += stream.data.size()
	return {"gem":get_node("/root/GemForge").delivery_report(),"non_gem_rgba_bytes":texture_bytes,"decoded_audio_bytes":audio_bytes,
		"non_gem_16mib_met":texture_bytes <= 16*1024*1024,"audio_2mib_met":audio_bytes <= 2*1024*1024,
		"unmeasured":"font/scene/container/decode/transient driver overhead; SVG estimate is RGBA base-level payload"}

func _functional_tools(scene: RunScene) -> Array:
	var observations: Array = []
	scene.instant_playback = true
	for kind in ["action.exchange","action.clear_target","action.promote_target"]:
		var room := RoomDefinitionResource.new(); room.room_id = "probe_tool_room"
		room.craft = 6; room.layout = BoardLayoutResource.new(); room.layout.board_size = Vector2i(3,3)
		room.obstacles = [{"id":"rubble/probe","cell":Vector2i(1,2),"kind":"rubble","durability":2}]
		room.marked_ids = ["rubble/probe"]
		if not scene.run_controller.start_room(room,31): failures.append("tool_room_start"); continue
		for frame in 120:
			await get_tree().process_frame
			if scene.board_scene.visible and not scene._delivery_loading and not scene.board_scene._input_gates.has("loading"): break
		await scene._begin_room()
		if not scene.board_scene.has_focus(): failures.append("tool_keyboard_focus/"+kind)
		var state := scene.run_controller.run_state
		var choices := RoomActionLegality.tools(state).filter(func(c: RoomCommand) -> bool: return c.data.kind == kind and (kind != "action.clear_target" or c.data.layer == "obstacle"))
		if choices.is_empty(): failures.append("tool_fixture_target/"+kind); continue
		var command: RoomCommand = choices[0]
		scene._select_tool(kind)
		if kind == "action.exchange": scene._on_cell_pressed(command.data.origin); scene._on_cell_pressed(command.data.destination)
		else: scene._on_cell_pressed(command.data.cell)
		if scene._preview_command == null or scene._room_panel._confirm.disabled: failures.append("tool_preview/"+kind); continue
		var unchanged := state.digest()
		scene._cancel_selection()
		if state.digest() != unchanged or scene._preview_command != null: failures.append("tool_cancel/"+kind)
		scene._select_tool(kind)
		if kind == "action.exchange": scene._on_cell_pressed(command.data.origin); scene._on_cell_pressed(command.data.destination)
		else:
			scene.board_scene.cursor_cell = command.data.cell
			var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true
			scene.board_scene._gui_input(enter)
		await scene._confirm_target()
		var after := scene.run_controller.run_state
		var okay := scene.run_controller.last_error.is_empty() and after.moves_remaining == 16 and after.room.craft == 6-RoomActionLegality.cost(kind,after.rules) and not after.room.tool_available
		if not okay: failures.append("tool_cost_or_allowance/"+kind)
		if after.board.digest() != scene.board_scene._board_state.digest(): failures.append("tool_view/"+kind)
		observations.append({"kind":kind,"passed":okay,"state_digest":after.digest(),"event_digest":scene.run_controller.last_result.event_digest})
	return observations

func _picture(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path+"."+label+".png")

func _stats(values: Array) -> Dictionary:
	return ActionProbe._stats(values)

func _finish(path: String, report: Dictionary) -> void:
	report.status = "passed" if failures.is_empty() else "failed"; report.failures = failures
	var output := FileAccess.open(path,FileAccess.WRITE)
	if output == null: printerr("FAIL: room probe report path"); get_tree().quit(1); return
	output.store_string(JSON.stringify(report,"\t")); output.close()
	for failure in failures: printerr("FAIL: "+failure)
	print("CHECK_COMPLETE: room_probe"); get_tree().quit(0 if failures.is_empty() else 1)
