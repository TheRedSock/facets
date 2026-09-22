extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _loaded(view: InterventionView) -> void:
	for frame in 180:
		await process_frame
		if view.ready_for_start: return
	check(false,"trial view delivery completes: "+view.error)

func _run() -> void:
	var fixture := GemDeliveryFixture.create(report_path("assets"),load("res://data/presentation/default.tres"))
	check(root.get_node("GemForge").open_library(fixture.library,fixture.catalog),"trial art fixture opens")
	Engine.time_scale = 40
	var expected := ""
	for fps in [30,60,120]:
		Engine.max_fps = fps
		var view := InterventionView.new(); view.mode = 2; view.automatic_clock = false; view.reduced_motion = fps == 120
		root.add_child(view); await _loaded(view)
		check(view.board._tile_views.size() == 23 and not view.board._layout_refresh_needs_rebuild,"ready publishes every initial view without a pending rebuild")
		var cues: Array = []
		view.board.presentation_cue.connect(func(cue: String): cues.append(cue))
		await view.start_opening()
		check("tile_swap" in cues and "match_commit" in cues and "tile_promoted" in cues,"trial opening retains sound cues including reduced motion")
		if not view.reduced_motion: check(view.board._action_player.observations.any(func(o: Dictionary) -> bool: return o.kind == "match"),"opening visibly plays its prefix rather than snapping past missing views")
		check(view.trial.phase == "window" and view.trial.clock.started and view.trial.clock.tick == 0,"visible boundary hands off clock at %d FPS" % fps)
		check(view.board._board_state.digest() == view.trial.state.board.digest(),"prefix view equals authoritative parked board")
		await view.apply_event(view.trial.event("advance",{"tick":7}))
		await view.apply_event(view.trial.event("pause",{"paused":true,"reason":"focus"}))
		await process_frame; await process_frame # Rendering during pause has no input authority.
		await view.apply_event(view.trial.event("pause",{"paused":false,"reason":"focus"}))
		await view.apply_event(view.trial.event("decide",{"command":view.trial.offers[0],"tick":12}))
		var digest := CanonicalCodec.digest(view.trial.snapshot())
		if expected.is_empty(): expected = digest
		check(digest == expected,"identical admitted stream under render FPS and reduced motion")
		check(view.board._board_state.digest() == view.trial.state.board.digest() and not view.playing,"continuation playback reaches exact settled view")
		view.restart(); await _loaded(view); await view.start_opening()
		view.automatic_clock = true; view._previous_us = Time.get_ticks_usec()-200000
		view._advance_clock(Time.get_ticks_usec())
		check(view.trial.clock.paused and view.trial.clock.tick == 0,"200ms render stall freezes last visible tick")
		check(view.trial.snapshot().transcript[-1].input.reason == "render_stall","stall is explicitly recorded as assisted")
		view.automatic_clock = false
		view.restart(); await _loaded(view); await view.start_opening()
		await view.apply_event(view.trial.event("advance",{"tick":24}))
		check(view.trial.phase == "stable" and view.trial.interventions == 0,"expiry plays the unmodified continuation")
		check(view.board._board_state.digest() == view.trial.state.board.digest() and not view.playing,"expiry playback reaches exact settled view")
		view.restart(); await _loaded(view)
		check(view.trial == null and not view.playing,"restart discards pending window and stale clock")
		view.start_opening(); var player := view.board._action_player
		view.queue_free(); await process_frame; await process_frame
		check(player._tweens.is_empty() and player._views_by_id.is_empty(),"navigation cancels all prefix playback awaits")
	Engine.max_fps = 120; Engine.time_scale = 1
	# Audio uses real time even while this test accelerates animation by 40x.
	# The current frame still carries its accelerated delta after time_scale is
	# reset; a SceneTreeTimer created here can expire immediately. Drain against
	# monotonic wall time so stopped voices reach mixer cleanup before shutdown.
	var drain_began := Time.get_ticks_usec()
	while Time.get_ticks_usec()-drain_began < 500000: await process_frame
	check(Time.get_ticks_usec()-drain_began >= 500000,"real half-second mixer drain despite prior accelerated frame delta")
	finish("test_intervention_playback")
