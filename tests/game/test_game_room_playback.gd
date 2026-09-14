extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _loaded(scene: RunScene) -> void:
	for frame in 180:
		await process_frame
		if scene.board_scene.visible and not scene._delivery_loading: return
	check(false,"room delivered board loads")

func _run() -> void:
	_motion_pockets()
	var fixture := GemDeliveryFixture.create("res://artifacts/game/p2/playback-assets",load("res://data/presentation/default.tres"))
	check(root.get_node("GemForge").open_library(fixture.library,fixture.catalog),"room art fixture opens")
	var scene: RunScene = load("res://scenes/run/run_scene.tscn").instantiate()
	scene.room_mode = true; root.add_child(scene); await _loaded(scene)
	check(scene.run_controller.run_state.phase == "briefing" and scene.board_scene.input_is_locked(),"briefing gates gameplay")
	check(scene._room_panel.visible and scene._hud_model.work == 16 and scene._hud_model.craft == 1,"room HUD has authored economy")
	var before := scene.run_controller.run_state.digest()
	await scene._on_swap_requested(Vector2i.ZERO,Vector2i.RIGHT)
	check(scene.run_controller.run_state.digest() == before,"briefing input changes nothing")
	await scene._begin_room()
	check(scene.run_controller.run_state.phase == "ready" and not scene.board_scene.input_is_locked(),"Begin opens gameplay")
	# Dummy driver verifies lifecycle/voice ownership, not perceptual sound quality.
	var silent := AudioStreamWAV.new(); silent.format = AudioStreamWAV.FORMAT_16_BITS
	silent.mix_rate = 48000; silent.data = PackedByteArray(); silent.data.resize(48000)
	var accepted_match: AudioStream = scene._audio.streams.get("match_commit")
	scene._audio.cancel()
	scene._audio.streams["match_commit"] = silent
	scene._audio.set_muted(false)
	var burst_start := scene._audio.cues_played
	for i in 30: scene._audio.play("match_commit")
	check(scene._audio.cues_played == burst_start+1,"duplicate simultaneous impacts coalesce")
	for cue in ["tile_swap","tile_promoted","obstacle_hit","obstacle_broken"]: scene._audio.play(cue)
	check(scene._audio.voices.slice(2,6).filter(func(v: AudioStreamPlayer) -> bool: return v.playing).size() == 4,"bounded game impact voices")
	scene._audio.play("room_success"); scene._audio.play("ui_accept")
	check(scene._audio.voices[6].playing and scene._audio.voices[0].playing,"results and UI remain audible during dense impacts")
	var prior_generation := scene._audio.generation
	scene._audio.cancel(); var played := scene._audio.cues_played
	scene._audio.play("match_commit",prior_generation)
	check(scene._audio.cues_played == played and scene._audio.voices.all(func(v: AudioStreamPlayer) -> bool: return not v.playing),"canceled generation cannot play stale cues")
	scene._audio.set_muted(true); scene._audio.play("match_commit")
	check(scene._audio.cues_played == played,"mute prevents playback")
	scene._audio.set_muted(false)
	scene._audio.streams["match_commit"] = accepted_match
	silent = null
	var model := RoomHudModel.build(scene.run_controller.run_state)
	check(model.is_read_only() and model.tools.all(func(t: Dictionary) -> bool: return t.reason == "Need %d Craft" % t.cost),"immutable HUD explains unaffordable tools")
	Engine.time_scale = 40.0
	for kind in ["action.clear_target","action.promote_target","action.exchange"]:
		var source := RoomTestSupport.fixture([[2,1,3],[1,2,1],[3,0,4]],[{"cell":Vector2i(1,2)}],16,6)
		var expected := ""
		for mode in ["concurrent","serial","instant","skip"]:
			check(scene.run_controller.restore_snapshot(source.to_dict()),"fixture restores "+kind+mode); await _loaded(scene)
			if scene.board_scene._action_player == null: scene.board_scene._action_player = ActionPlayer.new(scene.board_scene)
			scene.board_scene._action_player.serial_reference = mode == "serial"
			scene.instant_playback = mode == "instant"
			var command := RoomCommand.target(scene.run_controller.run_state,kind,Vector2i.ZERO)
			if kind == "action.exchange": command = RoomCommand.exchange(scene.run_controller.run_state,Vector2i.ZERO,Vector2i.RIGHT,true)
			if mode == "skip":
				scene._submit_command(command); scene.skip_playback(); await process_frame
			else: await scene._submit_command(command)
			check(scene.run_controller.last_error.is_empty(),"tool through scene "+kind+mode)
			if expected.is_empty(): expected = scene.run_controller.run_state.digest()
			check(scene.run_controller.run_state.digest() == expected,"playback mode preserves state "+kind+mode)
			check(scene.board_scene._board_state.digest() == scene.run_controller.get_board().digest(),"final gems and overlays exact "+kind+mode)
			check(not scene.board_scene.input_is_locked(),"live room reopens input "+kind+mode)
			if kind != "action.exchange" and mode == "concurrent": check(scene.board_scene._action_player.last_plan[0].kind == "match","direct tool has explicit effect phase")
	# Mouse and keyboard feed the same preview and command admission.
	var source := RoomTestSupport.fixture([[2,1,3],[1,2,1],[3,0,4]],[{"cell":Vector2i(1,2)}],16,6)
	scene.run_controller.restore_snapshot(source.to_dict()); await _loaded(scene)
	scene._select_tool("action.clear_target")
	scene.board_scene.cursor_cell = Vector2i(2,2)
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true
	scene.board_scene._gui_input(enter)
	check(scene._preview_command != null and scene._room_panel._confirm.disabled,"keyboard preview rejects T4 Chisel")
	scene.board_scene.cursor_cell = Vector2i(1,2); scene.board_scene._gui_input(enter)
	check(not scene._room_panel._confirm.disabled and scene._preview_command.data.layer == "obstacle","keyboard explicitly targets rubble")
	before = scene.run_controller.run_state.digest(); scene._cancel_selection()
	check(scene.run_controller.run_state.digest() == before and not scene.board_scene.target_mode,"cancel costs nothing")
	# A completed room is gated only after the authoritative action; skip must
	# retain that gate and show the final objective rather than the old overlay.
	for c in GameFixtureAdapter.read_cases():
		if c.id != "last_action_win": continue
		var win := RoomTestSupport.fixture(c.board,c.obstacles,int(c.work),int(c.craft))
		win.streams = RngStreamBank.new(int(c.seed)); win.sync_adapters()
		scene.run_controller.restore_snapshot(win.to_dict()); await _loaded(scene)
		scene.instant_playback = false
		scene._on_swap_requested(GameFixtureAdapter.cell(c.swap[0]),GameFixtureAdapter.cell(c.swap[1]))
		check(scene.run_controller.run_state.phase == "complete","final Work commits victory before playback")
		scene.skip_playback(); await process_frame
		check(scene.board_scene.input_is_locked() and scene._hud_model.remaining == 0,"skip preserves terminal gate and final HUD")
		scene._on_restart_pressed(); await _loaded(scene)
		check(scene.run_controller.run_state.digest() == win.digest() and not scene.board_scene.input_is_locked(),"restart removes stale terminal gate")
	Engine.time_scale = 1.0
	scene.queue_free(); await process_frame; await process_frame
	# The headless frame loop can outrun the audio mixer consuming stopped voices.
	await create_timer(0.1).timeout
	finish("test_game_room_playback")

func _motion_pockets() -> void:
	var catalog := GameTestCatalog.create()
	var board := BoardState.new(Vector2i(3,6)); board.room_board = true
	board.obstacles = {"rock":{"id":"rock","cell":Vector2i(0,2),"kind":"rubble","durability":2}}
	for pos in board.all_cells(): board.set_tile(pos,catalog.create_tile(1+(pos.x+pos.y)%4))
	for pos in [Vector2i(0,4),Vector2i(1,4),Vector2i(1,3)]: board.remove_tile(pos)
	var before := board.duplicate_board()
	var rng := SeededRng.new(); rng.reseed(55)
	var settled := BoardSettler.resolve(board,rng,catalog.supply(),SpawnResolver.new(catalog))
	check(settled.ok,"rubble pocket settles")
	var timeline := EventTimeline.new()
	for step in settled.steps:
		step.match_events = []; step.remove_events = []; step.upgrade_events = []; timeline.add_cascade_step(step)
	var plan := MotionPlan.build({"before":before,"timeline":timeline})
	check(plan.size() == 1 and plan[0].concurrent,"rubble room retains concurrent lanes")
	var pocket_count := 0
	for journey in plan[0].journeys:
		if journey.spawn and journey.to.x == 0 and journey.to.y > 2:
			pocket_count += 1
			check(journey.in_place and journey.from == journey.to and journey.start > 0,"pocket refill fades in after lane clears, never through rubble")
		elif journey.spawn: check(journey.from.y < 0,"open lane uses incoming stack")
	check(pocket_count > 0,"fixture exercises pocket refill")
