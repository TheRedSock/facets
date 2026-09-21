class_name ActionProbe
extends Node
## Opt-in CLI diagnostics in the actual executable. No normal UI/rule behavior.
var _scene: RunScene
var _frames: Array = []
var _active := false
var _previous := 0
var _input_at := 0
var _first_motion_us := -1
var _watched: TileView
var _initial_position := Vector2.ZERO
var _failures: Array = []

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _active:
		_frames.append((now - _previous) / 1000.0)
		if _first_motion_us < 0 and is_instance_valid(_watched) and _watched.position.distance_to(_initial_position) > 0.01:
			_first_motion_us = now - _input_at
	_previous = now

func run(report_path: String) -> void:
	var corpus := "--probe-corpus" in OS.get_cmdline_user_args()
	var room_corpus := "--probe-room-corpus" in OS.get_cmdline_user_args()
	var serial := "--probe-serial" in OS.get_cmdline_user_args()
	var report := {"schema":"facets-action-probe-v1","godot":Engine.get_version_info().string,"editor":OS.has_feature("editor"),
		"executable":OS.get_executable_path(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"display":DisplayServer.get_name(),
		"mode":"corpus" if corpus else ("serial" if serial else "concurrent"),"warmup_frames":30,"actions":[],"failures":_failures}
	if room_corpus: await _room_corpus(report)
	elif corpus: await _corpus(report)
	else: await _playback(report,serial)
	report.status = "pass" if _failures.is_empty() else "fail"
	var output := FileAccess.open(report_path,FileAccess.WRITE)
	if output == null:
		printerr("FAIL: Cannot write action probe report"); get_tree().quit(1); return
	output.store_string(JSON.stringify(report,"\t")); output.close()
	print("CHECK_COMPLETE: action_probe")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _room_corpus(report: Dictionary) -> void:
	report.mode = "p2-mixed-v1"; report.outcomes = {}
	var timings: Array = []; var queries: Array = []; var startups: Array = []; var begins: Array = []
	var by_kind := {}; var recovery: Array = []
	for seed_value in range(1,101):
		var game := RunController.new(); var start := Time.get_ticks_usec()
		if not game.start_room(null,seed_value): _failures.append(game.last_error); continue
		startups.append((Time.get_ticks_usec()-start)/1000.0)
		start = Time.get_ticks_usec(); var begun := game.apply_action(RoomCommand.begin(0))
		begins.append((Time.get_ticks_usec()-start)/1000.0)
		if not begun.ok: _failures.append(begun.code); continue
		for turn in 40:
			if game.run_state.phase != "ready": break
			start = Time.get_ticks_usec()
			var tools := RoomActionLegality.tools(game.run_state); var swaps := game.enumerate_legal_swaps()
			queries.append((Time.get_ticks_usec()-start)/1000.0)
			var command: RoomCommand
			if not tools.is_empty() and (turn%3 == 0 or swaps.is_empty()): command = tools[(seed_value+turn*17)%tools.size()]
			elif not swaps.is_empty():
				var swap := swaps[(seed_value+turn*13)%swaps.size()]; command = RoomCommand.exchange(game.run_state,swap.origin,swap.destination)
			else: _failures.append("ready_without_actions"); break
			start = Time.get_ticks_usec(); var result := game.apply_action(command)
			var elapsed := (Time.get_ticks_usec()-start)/1000.0
			if not result.ok: _failures.append(result.code); break
			timings.append(elapsed)
			if not by_kind.has(command.data.kind): by_kind[command.data.kind] = []
			by_kind[command.data.kind].append(elapsed)
			var segments := 0
			for fact in result.facts:
				if fact.type == "tile_moved": segments += fact.path.size()
			var recovered: bool = result.facts.any(func(f: Dictionary) -> bool: return f.type == "board_rearranged")
			if recovered: recovery.append(elapsed)
			report.actions.append({"seed":seed_value,"index":turn,"kind":command.data.kind,"sim_ms":elapsed,
				"state_digest":result.state_digest,"event_digest":result.event_digest,"facts":result.facts.size(),"work":result.timeline.work_count,"segments":segments,"recovery":recovered})
		report.outcomes[game.run_state.phase] = report.outcomes.get(game.run_state.phase,0)+1
		if game.run_state.phase not in ["complete","failed"]: _failures.append("incomplete_room/%d" % seed_value)
		if seed_value%10 == 0: print("P2 action corpus: %d/100" % seed_value); await get_tree().process_frame
	report.simulation = _stats(timings); report.legal_query = _stats(queries); report.startup = _stats(startups); report.begin = _stats(begins)
	report.by_kind = {}; report.recovery = _stats(recovery)
	for kind in by_kind: report.by_kind[kind] = _stats(by_kind[kind])
	report.target_5ms_met = report.simulation.p95 <= 5.0
	if report.actions.size() != 1194: _failures.append("incomplete_p2_corpus")

func _corpus(report: Dictionary) -> void:
	var timings: Array = []
	var queries: Array = []
	for seed_value in 100:
		var session := RunController.new()
		if not session.start_new_run({"seed":seed_value}): _failures.append(session.last_error); continue
		for index in 20:
			var start := Time.get_ticks_usec()
			var commands := session.enumerate_legal_swaps()
			queries.append((Time.get_ticks_usec()-start)/1000.0)
			if commands.is_empty(): _failures.append("early_no_legal_swap/%d/%d" % [seed_value,index]); break
			start = Time.get_ticks_usec()
			var result := session.apply_action(commands[(seed_value+index) % commands.size()])
			var elapsed := (Time.get_ticks_usec()-start)/1000.0
			timings.append(elapsed)
			if not result.ok: _failures.append(result.code); break
			report.actions.append({"seed":seed_value,"index":index,"sim_ms":elapsed,"state_digest":result.state_digest,"event_digest":result.event_digest,"work":result.timeline.work_count})
		if seed_value % 10 == 9:
			print("Action corpus: %d/100 seeds" % [seed_value+1])
			await get_tree().process_frame
	report.simulation = _stats(timings)
	report.legal_query = _stats(queries)
	report.target_5ms_met = report.simulation.p95 <= 5.0
	if report.actions.size() != 2000: _failures.append("incomplete_corpus")

func _playback(report: Dictionary, serial: bool) -> void:
	_scene = load("res://scenes/run/run_scene.tscn").instantiate()
	get_tree().root.add_child(_scene)
	if not await _ready_board(): return
	_scene.run_controller.start_new_run({"seed":0})
	if not await _ready_board(): return
	for frame in 30: await get_tree().process_frame
	var forge := get_node("/root/GemForge")
	var initial_loads: int = forge.delivery_report().page_loads
	var all_frames: Array = []
	for index in 20:
		if _scene.board_scene._action_player == null: _scene.board_scene._action_player = ActionPlayer.new(_scene.board_scene)
		_scene.board_scene._action_player.serial_reference = serial
		var start := Time.get_ticks_usec()
		var commands := _scene.run_controller.enumerate_legal_swaps()
		var query_ms := (Time.get_ticks_usec()-start)/1000.0
		if commands.is_empty(): _failures.append("early_no_legal_swap"); break
		var command: SwapCommand = commands[index % commands.size()]
		_watched = _scene.board_scene._tile_views[command.origin]
		_initial_position = _watched.position; _first_motion_us = -1
		_frames.clear(); _input_at = Time.get_ticks_usec(); _previous = _input_at; _active = true
		await _scene._on_swap_requested(command.origin,command.destination)
		await get_tree().process_frame
		_active = false
		var result := _scene.run_controller.last_result
		if result.is_empty() or not result.ok: _failures.append("action_failed"); break
		all_frames.append_array(_frames)
		var player: ActionPlayer = _scene.board_scene._action_player
		var plan := MotionPlan.build(result)
		var scheduled := AnimationSequencer.swap_duration
		var serial_falls := 0.0; var concurrent_falls := 0.0
		for phase in plan:
			if phase.kind == "travel":
				serial_falls += phase.serial_seconds; concurrent_falls += phase.motion_seconds
				scheduled += phase.motion_seconds + (AnimationSequencer.landing_bounce_duration if phase.concurrent else 0.0)
			else:
				if not phase.step.remove_events.is_empty(): scheduled += AnimationSequencer.removal_duration
				if not phase.step.upgrade_events.is_empty(): scheduled += AnimationSequencer.upgrade_scale_duration
		var row := {"seed":0,"index":index,"sim_ms":_scene._last_sim_ms,"playback_ms":_scene._last_anim_ms,"query_ms":query_ms,
			"input_to_motion_ms":_first_motion_us/1000.0,"scheduled_seconds":scheduled,"serial_fall_seconds":serial_falls,
			"concurrent_fall_seconds":concurrent_falls,"frames":_stats(_frames),"state_digest":result.state_digest,"event_digest":result.event_digest,
			"observations":player.observations.duplicate(true),"active_views":_scene.board_scene._tile_views.size()}
		report.actions.append(row)
		if row.active_views != 64: _failures.append("view_count")
		for frame in 3: await get_tree().process_frame
	report.frames = _stats(all_frames); report.raw_frame_ms = all_frames
	report.frame_target_met = report.frames.p95 <= 16.7
	report.extra_page_loads = int(forge.delivery_report().page_loads) - initial_loads
	if report.extra_page_loads != 0: _failures.append("cold_pages")
	if report.actions.size() != 20: _failures.append("incomplete_playback")
	await _lifecycle(report)

func _lifecycle(report: Dictionary) -> void:
	var checks := {}
	_scene._on_restart_pressed()
	if not await _ready_board(): return
	var initial := _scene.run_controller.run_state.digest()
	await _scene._on_swap_requested(Vector2i.ZERO,Vector2i.ZERO)
	checks.invalid_unchanged = _scene.run_controller.run_state.digest() == initial and not _scene.board_scene.input_is_locked()
	var command := _scene.run_controller.enumerate_legal_swaps()[0]
	_scene._on_swap_requested(command.origin,command.destination)
	var committed := _scene.run_controller.run_state.digest()
	_scene.skip_playback(); await get_tree().process_frame
	checks.skip_committed = _scene.run_controller.run_state.digest() == committed and not _scene.board_scene.input_is_locked()
	_scene._on_restart_pressed()
	if not await _ready_board(): return
	checks.restart_initial = _scene.run_controller.run_state.digest() == initial
	_scene._on_swap_requested(command.origin,command.destination)
	_scene._show_delivery_error("action probe controlled failure")
	_scene.skip_playback(); await get_tree().process_frame
	checks.error_locked = _scene.board_scene.input_is_locked() and not _scene.board_scene.visible
	_scene._on_restart_pressed()
	if not await _ready_board(): return
	_scene._on_swap_requested(command.origin,command.destination)
	var player := _scene.board_scene._action_player
	_scene._on_back_pressed(); _scene.queue_free()
	await get_tree().process_frame; await get_tree().process_frame
	checks.navigation_canceled = player._tweens.is_empty() and player._views_by_id.is_empty()
	report.lifecycle = checks
	for name in checks:
		if not checks[name]: _failures.append("lifecycle/" + name)

func _ready_board() -> bool:
	for frame in 1000:
		await get_tree().process_frame
		if not _scene._delivery_error.is_empty(): _failures.append(_scene._delivery_error); return false
		if _scene.board_scene.visible and not _scene.board_scene.input_is_locked(): return true
	_failures.append("load_timeout"); return false

static func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0,"p95":0.0,"max":0.0,"over_16_7":0}
	var sorted := values.duplicate(); sorted.sort()
	return {"count":values.size(),"quantile":"nearest_rank","p50":sorted[int(ceil(sorted.size()*0.5))-1],"p95":sorted[mini(sorted.size()-1,int(ceil(sorted.size()*0.95))-1)],"max":sorted[-1],
		"over_16_7":values.filter(func(value: float) -> bool: return value > 16.7).size()}
