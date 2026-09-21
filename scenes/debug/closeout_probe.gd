class_name CloseoutProbe
extends Node
## Opt-in release diagnostics. Cases are labelled as authored or normal-policy.
var failures: Array = []
var checks := {}

func run(path: String) -> void:
	var kind := "lifecycle"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--closeout-case="): kind = arg.trim_prefix("--closeout-case=")
	var report := {"schema":1,"case":kind,"executable":OS.get_executable_path(),"editor":OS.has_feature("editor"),
		"godot":Engine.get_version_info().string,"fps_cap":Engine.max_fps,"size":get_viewport().get_visible_rect().size,"checks":checks}
	if kind == "trial": await _trial(report,path)
	else: await _room(report,kind)
	await get_tree().create_timer(0.2).timeout
	report.status = "passed" if failures.is_empty() else "failed"; report.failures = failures
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: printerr("FAIL: closeout report unavailable"); get_tree().quit(1); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	for failure in failures: printerr("FAIL: "+failure)
	print("CHECK_COMPLETE: closeout_probe"); get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks[label] = ok
	if not ok: failures.append(label)

func _loaded(scene: RunScene, expect_error: bool = false) -> bool:
	for frame in 600:
		await get_tree().process_frame
		if not scene._delivery_error.is_empty(): return expect_error
		if scene.board_scene.visible and not scene._delivery_loading and not scene.board_scene._input_gates.has("loading"): return not expect_error
	return false

func _room(report: Dictionary, kind: String) -> void:
	var scene: RunScene = load("res://scenes/run/run_scene.tscn").instantiate()
	scene.room_mode = true; get_tree().root.add_child(scene)
	if kind == "delivery_error":
		_check(await _loaded(scene,true),"expected asset error appears")
		_check(scene.board_scene.input_is_locked() and not scene.board_scene.visible,"asset error gates input and hides board")
		report.expected_load_error = scene._delivery_error
		scene.queue_free(); await get_tree().process_frame; return
	if not await _loaded(scene): _check(false,"room loads"); scene.queue_free(); return
	await scene._begin_room()
	var snapshot := scene.run_controller.run_state.to_dict()
	var digest := scene.run_controller.run_state.digest()
	await scene._on_swap_requested(Vector2i.ZERO,Vector2i.ZERO)
	_check(scene.run_controller.run_state.digest() == digest and not scene.board_scene.input_is_locked(),"invalid input pure and reopens gate")
	# Natural loss uses unchanged Open seam and the fixed mixed-command policy.
	_check(scene.run_controller.start_room(null,8),"natural-loss seed starts")
	await _loaded(scene); scene.instant_playback = true; await scene._begin_room()
	for turn in 40:
		var state := scene.run_controller.run_state
		if state.phase != "ready": break
		var tools := RoomActionLegality.tools(state); var swaps := scene.run_controller.enumerate_legal_swaps()
		var command: RoomCommand
		if not tools.is_empty() and (turn%3 == 0 or swaps.is_empty()): command = tools[(8+turn*17)%tools.size()]
		elif not swaps.is_empty():
			var swap := swaps[(8+turn*13)%swaps.size()]; command = RoomCommand.exchange(state,swap.origin,swap.destination)
		else: _check(false,"natural loss offers actions"); break
		await scene._submit_command(command)
	_check(scene.run_controller.run_state.phase == "failed" and scene.run_controller.run_state.room.failure_reason == "work_exhausted","natural Work-exhaustion loss")
	report.loss_replay = scene.run_controller.export_replay() # Diagnostic JSON only; hashes/commands remain visible.
	# Authored frozen P0 final-Work fixture.
	var final_work := _fixture([[2,1,3],[1,2,1],[3,0,2]],1,1,1)
	final_work.streams = RngStreamBank.new(140908); final_work.sync_adapters()
	_check(scene.run_controller.restore_snapshot(final_work.to_dict()),"final-Work fixture admitted")
	await _loaded(scene); scene.instant_playback = false
	scene._on_swap_requested(Vector2i(1,0),Vector2i(1,1))
	_check(scene.run_controller.run_state.phase == "complete" and scene.run_controller.run_state.moves_remaining == 0,"final-Work victory beats loss")
	scene.skip_playback(); await get_tree().process_frame
	_check(scene.board_scene.input_is_locked() and scene._hud_model.remaining == 0,"terminal action skip preserves terminal HUD")
	scene._on_restart_pressed(); await _loaded(scene)
	_check(scene.run_controller.run_state.digest() == final_work.digest(),"terminal restart restores exact entry")
	for operation in ["skip","restart"]:
		await scene._on_swap_requested(Vector2i(1,0),Vector2i(1,1))
		_check(scene._audio.voices.slice(6,8).any(func(v: AudioStreamPlayer) -> bool: return v.playing),"reached result audio tail "+operation)
		var terminal := scene.run_controller.run_state.digest()
		if operation == "skip":
			scene.skip_playback()
			_check(scene.run_controller.run_state.digest() == terminal and scene.board_scene.input_is_locked(),"result-tail skip preserves terminal state")
		else: scene._on_restart_pressed(); await _loaded(scene)
		_check(scene._audio.voices.all(func(v: AudioStreamPlayer) -> bool: return not v.playing),"result tail canceled "+operation)
		if operation == "skip": scene._on_restart_pressed(); await _loaded(scene)
	var locked := _fixture([[4,5],[6,4],[5,6],[0,0]],16,0)
	locked.room.tool_available = false; locked.room.recovery_count = 1; locked.phase = "failed"; locked.room.failure_reason = "board_locked"
	_check(scene.run_controller.restore_snapshot(locked.to_dict()),"authored board-lock diagnostic admitted")
	await _loaded(scene)
	_check(scene.board_scene.input_is_locked() and scene._hud_model.reason == "board_locked","board-lock reason and gate visible")
	# Actual concurrent travel cancellation and direct effects use ordinary view code.
	for operation in ["travel_skip","travel_restart","direct_skip","direct_restart"]:
		var source := _fixture([[2,1,3],[1,2,1],[3,0,4]],16,6) if operation.begins_with("direct") else null
		_check(scene.run_controller.restore_snapshot(source.to_dict() if source != null else snapshot),"restore "+operation)
		await _loaded(scene)
		if source != null: scene._submit_command(RoomCommand.target(scene.run_controller.run_state,"action.promote_target",Vector2i.ZERO))
		else:
			var swap := scene.run_controller.enumerate_legal_swaps()[0]
			scene._on_swap_requested(swap.origin,swap.destination)
		var player := scene.board_scene._action_player
		if operation.begins_with("travel"):
			for frame in 600:
				await get_tree().process_frame
				if player.observations.any(func(o: Dictionary) -> bool: return o.kind == "start"): break
			_check(player.observations.any(func(o: Dictionary) -> bool: return o.kind == "start"),"reached concurrent travel "+operation)
		else: _check(not player._tweens.is_empty(),"reached direct effect "+operation)
		var committed := scene.run_controller.run_state.digest()
		if operation.ends_with("skip"):
			scene.skip_playback(); await get_tree().process_frame
			_check(scene.run_controller.run_state.digest() == committed and scene.board_scene._board_state.digest() == scene.run_controller.get_board().digest(),"skip exact "+operation)
		else: scene._on_restart_pressed(); await _loaded(scene)
		_check(player._tweens.is_empty() and player._views_by_id.is_empty(),"cancellation releases ownership "+operation)
	var stale := RoomCommand.target(scene.run_controller.run_state,"action.clear_target",Vector2i(1,2),"obstacle")
	digest = scene.run_controller.run_state.digest()
	stale = RoomCommand.new(stale.to_dict().merged({"target_id":"stale/target"},true))
	await scene._submit_command(stale)
	_check(scene.run_controller.run_state.digest() == digest,"stale target rejection pure")
	var recoverable := _fixture([[2,1,3],[1,2,1],[3,0,4]],16,6)
	scene.run_controller.restore_snapshot(recoverable.to_dict()); await _loaded(scene)
	scene.instant_playback = true
	await scene._submit_command(RoomCommand.exchange(scene.run_controller.run_state,Vector2i.ZERO,Vector2i.RIGHT,true))
	_check(scene.run_controller.last_result.facts.any(func(f: Dictionary) -> bool: return f.type == "board_rearranged"),"actual tool invokes recovery")
	_check(scene.board_scene._board_state.digest() == scene.run_controller.get_board().digest(),"recovery visual equals committed board")
	var recovered := scene.run_controller.run_state.to_dict(); digest = scene.run_controller.run_state.digest()
	scene.run_controller.restore_snapshot(recovered); await _loaded(scene)
	_check(scene.run_controller.run_state.digest() == digest,"restored recovery does not reshuffle or draw")
	scene.instant_playback = false
	# Actual required-resource preflight failures, not a fabricated UI error string.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/workshop_manifest.json"))
	for missing in ["ui","sound"]:
		var broken := manifest.duplicate(true)
		if missing == "ui": broken.resources["res://assets/ui/missing-closeout.svg"] = "missing"
		else: broken.audio_resources.append("res://assets/audio/sfx/missing-closeout.wav")
		_check(not scene._audio.load_manifest(broken),"required "+missing+" absence detected")
		scene._on_restart_pressed(); await _loaded(scene,true)
		_check(not scene._delivery_error.is_empty() and scene.board_scene.input_is_locked(),"required "+missing+" failure gates scene")
		_check(scene._audio.load_manifest(manifest),"required "+missing+" restored")
		scene._on_restart_pressed(); _check(await _loaded(scene),"load-error restart recovery "+missing)
	var capped := _fixture([[2,1,3],[1,2,1],[3,0,4]],16,6)
	var rules := capped.rules.to_dict(); rules.max_work = 0; capped.rules = RuleSet.new(rules)
	scene.run_controller.restore_snapshot(capped.to_dict()); await _loaded(scene)
	digest = scene.run_controller.run_state.digest()
	await scene._on_swap_requested(Vector2i(1,0),Vector2i(1,1))
	_check(scene._resolution_error == "work_cap" and scene.run_controller.run_state.digest() == digest and scene.board_scene.input_is_locked(),"technical failure rolls back and shows recovery controls")
	scene._on_restart_pressed(); await _loaded(scene)
	_check(scene._resolution_error.is_empty(),"technical-error restart clears diagnostic gate")
	scene._audio.set_volume(0); _check(scene._audio.voices.all(func(v: AudioStreamPlayer) -> bool: return not v.playing),"zero volume stops voices")
	scene._audio.set_volume(0.8)
	scene.run_controller.restore_snapshot(snapshot); await _loaded(scene)
	var next := scene.run_controller.enumerate_legal_swaps()[0]
	scene._on_swap_requested(next.origin,next.destination)
	var active := scene.board_scene._action_player
	scene._on_back_pressed(); scene.queue_free(); await get_tree().process_frame; await get_tree().process_frame
	_check(active._tweens.is_empty() and active._views_by_id.is_empty(),"menu navigation cancels active action")

func _fixture(rows: Array, work: int, craft: int, durability: int = 2) -> RunState:
	var catalog: GameCatalog = GameBootstrap.catalog().catalog
	var resource := RoomDefinitionResource.new(); resource.room_id = "closeout_diagnostic"
	resource.work = work; resource.craft = craft; resource.layout = BoardLayoutResource.new(); resource.layout.board_size = Vector2i(rows[0].size(),rows.size())
	for y in rows.size():
		for x in rows[y].size():
			if rows[y][x] == 0:
				var id := "rubble/%d/%d" % [y,x]
				resource.obstacles.append({"id":id,"cell":Vector2i(x,y),"kind":"rubble","durability":durability}); resource.marked_ids.append(id)
	var admitted := RoomDefinition.compile(resource,catalog)
	var state := RunState.new(); state.board = admitted.board; state.catalog = catalog; state.rules = RuleSet.for_room(); state.streams = RngStreamBank.new(1234)
	state.room = RoomState.new(); state.room.definition = admitted.definition; state.room.craft = craft
	state.moves_remaining = work; state.phase = "ready"; state.revision = 1; state.next_action = 2; state.next_event = 3
	for y in rows.size():
		for x in rows[y].size():
			if rows[y][x] > 0: state.board.set_tile(Vector2i(x,y),catalog.create_tile(rows[y][x]))
	state.sync_adapters(); return state

func _trial(report: Dictionary, path: String) -> void:
	report.profiles = []
	for mode in 4:
		var view := InterventionView.new(); view.mode = mode; view.automatic_clock = false
		view.reduced_motion = "--reduced-motion" in OS.get_cmdline_user_args(); get_tree().root.add_child(view)
		for frame in 600:
			await get_tree().process_frame
			if view.ready_for_start or not view.error.is_empty(): break
		_check(view.ready_for_start,"trial loads "+InterventionView.MODES[mode])
		if not view.ready_for_start: view.queue_free(); continue
		await view.start_opening()
		if mode > 0:
			_check(view.trial.phase == "window" and view.trial.clock.tick == 0,"trial handoff "+str(mode))
			if "--room-screenshots" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(path+".window-%d.png" % mode)
			await view.apply_event(view.trial.event("advance",{"tick":7}))
			await view.apply_event(view.trial.event("pause",{"paused":true,"reason":"focus"}))
			await get_tree().process_frame; await get_tree().process_frame
			await view.apply_event(view.trial.event("pause",{"paused":false,"reason":"focus"}))
			await view.apply_event(view.trial.event("decide",{"command":view.trial.offers[0],"tick":12}))
			_check(view.trial.phase == "stable" and view.board._board_state.digest() == view.trial.state.board.digest(),"trial settled view "+str(mode))
			_check(InterventionTrial.restored(view.trial.snapshot()).ok,"trial release replay "+str(mode))
			report.profiles.append({"mode":mode,"snapshot_digest":CanonicalCodec.digest(view.trial.snapshot()),"state_digest":view.trial.state.digest(),"event_digest":CanonicalCodec.digest(view.trial.context.facts)})
		if mode == 3:
			view.restart()
			for frame in 600:
				await get_tree().process_frame
				if view.ready_for_start: break
			view.automatic_clock = true; await view.start_opening()
			OS.delay_msec(200); view._advance_clock(Time.get_ticks_usec())
			_check(view.trial.clock.paused and view.trial.clock.tick == 0,"actual render stall pauses visible deadline")
			view.restart()
			for frame in 600:
				await get_tree().process_frame
				if view.ready_for_start: break
			await view.start_opening()
			for frame in 300:
				await get_tree().process_frame
				if view.trial.phase == "stable" and not view.playing: break
			_check(view.trial.phase == "stable" and view.trial.interventions == 0 and view.trial.clock.tick == 48,"real 800ms clock expires without input")
		view.queue_free(); await get_tree().process_frame; await get_tree().process_frame
