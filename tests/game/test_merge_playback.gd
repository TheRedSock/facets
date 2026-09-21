extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _loaded(view: MergeRoomView) -> bool:
	var end := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec() < end:
		await process_frame
		if not view.error.is_empty(): check(false,"load: "+view.error); return false
		if view.board != null and view.board.visible and view.session != null and view.player.live.size() > 0:
			view._begin.pressed.emit(); return true
	check(false,"room loading timeout"); return false

func _window(view: MergeRoomView, id: int) -> bool:
	var end := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec() < end:
		await process_frame
		if not view.error.is_empty(): check(false,"playback: "+view.error); return false
		if view.session.window_id == id and view.can_input(): return true
	check(false,"merge window timeout %d; %s" % [id,view.session.phase]); return false

func _run() -> void:
	var fixture := GemDeliveryFixture.create(report_path("assets"),load("res://data/presentation/default.tres"))
	check(root.get_node("GemForge").open_library(fixture.library,fixture.catalog),"streaming asset fixture opens")
	var checkpoints: Array = []
	for fps in [30,60,120]:
		Engine.max_fps = fps
		var state := InterventionFixture.create(16,"automatic_chain")
		state.board.set_tile(Vector2i(1,2),state.catalog.create_tile(2))
		var view := MergeRoomView.new(); view.initial_override = state.to_dict(); view.automatic_clock = false; view.reduced_motion = fps == 120
		root.add_child(view)
		if not await _loaded(view): view.queue_free(); continue
		check(view.can_input() and not view.board.input_is_locked(),"ready board accepts gestures")
		view.board.cursor_cell = Vector2i(3,3)
		var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_ENTER
		view.board._gui_input(key)
		key = InputEventKey.new(); key.pressed = true; key.keycode = KEY_LEFT; view.board._gui_input(key)
		key = InputEventKey.new(); key.pressed = true; key.keycode = KEY_ENTER; view.board._gui_input(key)
		check(view.player.motion_busy and not view.session.reservation.is_empty(),"swap feedback starts before computed result")
		if not await _window(view,1): view.queue_free(); continue
		check(view.board._board_state.to_dict() == view.session.state.board.to_dict(),"MW15 post-merge board is visible input authority")
		var id := view.session.state.board.get_tile(Vector2i(2,3)).instance_id
		var promoted: TileView = view.player.live[id]
		check(promoted.tier == 2 and promoted.cell == Vector2i(2,3),"MW15 first-frame promoted identity")
		check(not view.player.ghosts.is_empty() and view.board._tile_views.get(Vector2i(2,1)) == null,"MW15 consumed ghosts excluded from hit map")
		if DisplayServer.get_name() != "headless" and fps == 60:
			root.get_texture().get_image().save_png(report_path("first-merge.png"))
		var prior := CanonicalCodec.encode(view.session.mechanical_snapshot())
		view.board.swap_requested.emit(Vector2i(2,1),Vector2i(1,1))
		check(CanonicalCodec.encode(view.session.mechanical_snapshot()) == prior and view.can_input(),"ghost gesture cannot reserve or block valid input")
		view.session.tick(19)
		view.board.swap_requested.emit(Vector2i(2,3),Vector2i(1,3))
		check(view.player.motion_busy and view.player.live[id] == promoted,"MW15 promoted view transfers into buffered swap before decoration ends")
		check(view.player.ghosts.size() > 0,"independent departing decorations continue")
		if not await _window(view,2): view.queue_free(); continue
		check(view.session.state.board.get_tile(Vector2i(1,3)).tier == 3 and view.player.live[id] == promoted,"redirection uses same live gem at stronger match")
		check(view.session.history.back().tick == 19,"MW17 buffered receipt remains tick 19")
		checkpoints.append(CanonicalCodec.digest(view.session.mechanical_snapshot()))
		view.board.size = Vector2(520,570)
		await process_frame; await process_frame
		check(view.board._tile_views[Vector2i(1,3)] == promoted and promoted.position == view.board._cell_to_pixel(Vector2i(1,3)),"resize preserves live identity and anchor")
		var saved := view.session.snapshot()
		check(view.restore_session(saved) and view.session.clock.paused and view.session.clock.assisted,"MW24 native parked restore presents committed board paused")
		check(view.board._board_state.to_dict() == view.session.state.board.to_dict(),"restored visible input board exact")
		view.clock_adapter.pause(false,"manual")
		view.clock_adapter.pause(true,"focus"); var tick: int = view.session.clock.tick
		view.clock_adapter.automatic = true; view.clock_adapter.advance(Time.get_ticks_usec()+30000)
		check(view.session.clock.paused and view.session.clock.tick == tick and not view.can_input(),"MW18 focus pause freezes deadline and input")
		view.clock_adapter.pause(false,"focus"); view.clock_adapter.automatic = false
		var press := InputEventMouseButton.new(); press.pressed = true; press.button_index = MOUSE_BUTTON_LEFT
		press.position = view.board._board_offset+view.board._cell_to_pixel(Vector2i(2,4))+Vector2(view.board._cell_size)*0.5
		view.board._gui_input(press)
		check(view.session.reservation.is_empty(),"MW17 pointer down alone never reserves a command")
		view.session.tick(20)
		view._refresh()
		check(view.board._drag_origin == Vector2i(-1,-1),"expiry cancels unfinished gesture before a new board can replace its targets")
		prior = CanonicalCodec.encode(view.session.mechanical_snapshot())
		view.board.swap_requested.emit(Vector2i(2,4),Vector2i(1,4))
		check(CanonicalCodec.encode(view.session.mechanical_snapshot()) == prior,"MW17 tie rejects gesture before continuation")
		var deadline := Time.get_ticks_msec()+5000
		while not view.player.observations.any(func(o: Dictionary) -> bool: return o.kind == "gravity_started") and Time.get_ticks_msec() < deadline: await process_frame
		check(view.player.observations.any(func(o: Dictionary) -> bool: return o.kind == "gravity_started"),"expiry releases exact gravity packet")
		view.restart()
		if await _loaded(view):
			view.board.swap_requested.emit(Vector2i(3,3),Vector2i(2,3))
			if await _window(view,1):
				view.session.tick(20)
				if await _window(view,2): check(view.board._tile_views[Vector2i(2,5)].tier == 3,"MW03 native no-input automatic merge opens another actionable window")
		if fps == 60:
			view.restart()
			if await _loaded(view):
				view.executor.injected_delay_us = 220000
				view.board.swap_requested.emit(Vector2i(3,3),Vector2i(2,3))
				if await _window(view,1): check(view.starvation > 0 and view.session.clock.tick == 0,"MW23 deliberate underflow records starvation and opens a full new window")
		var executor := view.executor
		view.queue_free(); await process_frame; await process_frame
		check(not executor._thread.is_started() and executor._pending.is_empty(),"navigation cancels worker and frees presentation")
	check(checkpoints.size() == 3 and checkpoints[0] == checkpoints[1] and checkpoints[1] == checkpoints[2],"MW18 same admitted transcript across FPS and reduced motion")
	var room := MergeRoomView.new(); room.seed_value = 1; room.automatic_clock = false
	root.add_child(room)
	if await _loaded(room):
		var remote := false
		for index in 5:
			var choices := ActionLegality.enumerate_legal_swaps(room.session.state.board)
			check(not choices.is_empty(),"native repeated witness has next legal command")
			if choices.is_empty(): break
			var swap := choices[0]
			if index > 0:
				var promoted_ids: Array = room.session.last_batch.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_promoted").map(func(f: Dictionary) -> String: return f.instance_id)
				if room.session.state.board.get_tile(swap.origin).instance_id not in promoted_ids and room.session.state.board.get_tile(swap.destination).instance_id not in promoted_ids: remote = true
			var mouse := InputEventMouseButton.new(); mouse.pressed = true; mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = room.board._board_offset+room.board._cell_to_pixel(swap.origin)+Vector2(room.board._cell_size)*0.5
			room.board._gui_input(mouse)
			var drag := InputEventMouseMotion.new(); drag.button_mask = MOUSE_BUTTON_MASK_LEFT
			drag.position = room.board._board_offset+room.board._cell_to_pixel(swap.destination)+Vector2(room.board._cell_size)*0.5
			room.board._gui_input(drag)
			if not await _window(room,index+1): break
		check(remote and room.session.move_id == 5,"MW16 remote match and four interventions through actual drag adapter")
		room.clock_adapter.automatic = true
		room.clock_adapter._previous_us = Time.get_ticks_usec()-200000
		room.clock_adapter.advance(Time.get_ticks_usec())
		check(room.session.clock.paused and room.session.clock.assisted and room.session.clock.tick == 0,"MW18 visible stall freezes a full input window and records assistance")
		check(room.clock_adapter.pass_now() and room.session.clock.tick == 20,"explicit pass records decision without invented player input")
	room.queue_free(); await process_frame; await process_frame
	Engine.max_fps = 120
	# AudioServer releases stopped mixer voices asynchronously after node teardown.
	await create_timer(0.1).timeout
	write_report("playback.json",{"checkpoints":checkpoints,"assertions":assertions,"failures":failures})
	finish("test_merge_playback")
