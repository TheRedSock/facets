extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var fixture := GemDeliveryFixture.create(report_path("assets"),load("res://data/presentation/default.tres"))
	check(root.get_node("GemForge").open_library(fixture.library,fixture.catalog),"input asset fixture opens")
	var cases := MergeReleaseCases.new(); cases.tree = self
	for reduced in [false,true]:
		var view := MergeRoomView.new(); view.automatic_clock = false; view.reduced_motion = reduced
		root.add_child(view)
		if not await cases.loaded(view): check(false,"room loads"); view.queue_free(); continue
		view.session.state.room.craft = 0; view._refresh()
		var before := CanonicalCodec.digest(view.session.mechanical_snapshot())
		for button in view._tool_buttons:
			check(button.disabled,"unaffordable tool disabled")
			button.pressed.emit()
			check(view._tool.is_empty() and not view.board.target_mode and view.can_input(),"programmatic unaffordable choice cannot trap swaps")
		check(CanonicalCodec.digest(view.session.mechanical_snapshot()) == before,"unaffordable selections spend nothing")
		view.session.state.room.craft = 3; view._refresh()
		for button in view._tool_buttons:
			button.pressed.emit(); check(view.board.target_mode,"affordable tool enters targeting")
			button.pressed.emit(); check(not view.board.target_mode,"selecting same tool cancels")
			button.pressed.emit()
			var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_ESCAPE
			view.board._gui_input(key)
			check(not view.board.target_mode and view._tool.is_empty(),"Escape returns to swaps")
			button.pressed.emit(); view._cancel_button.pressed.emit()
			check(not view.board.target_mode,"visible cancel returns to swaps")
		view._select_tool("action.promote_target")
		view.session.state.room.craft = 0
		view._target(Vector2i.ZERO)
		check(view._tool.is_empty() and not view.board.target_mode and view.can_input(),"failed tool attempt releases target mode")
		var cues: Array = []
		view.board.presentation_cue.connect(func(cue: String): cues.append(cue))
		var swaps := ActionLegality.enumerate_legal_swaps(view.session.state.board)
		view.request_swap(swaps[0].origin,swaps[0].destination)
		if await cases.window(view,1):
			check("tile_swap" in cues and "match_commit" in cues and "tile_promoted" in cues,"normal and reduced merge emit swap/match/promotion cues")
			var expected := {"obstacle_damaged":"obstacle_hit","obstacle_broken":"obstacle_broken"}
			for fact in view.session.last_batch.facts:
				if expected.has(fact.type): check(expected[fact.type] in cues,"committed rubble cue emitted")
			cues.clear()
			view.player.present_fact_cues([{"type":"obstacle_damaged"},{"type":"obstacle_damaged"},{"type":"obstacle_broken"}])
			check(cues == ["obstacle_hit","obstacle_broken"],"simultaneous rubble cues coalesce")
		view.queue_free(); await process_frame; await process_frame
	await _buffer_cases(cases)
	await cases.buffer_gravity()
	for observation in cases.observations: check(observation.passed,observation.case)
	await create_timer(0.5).timeout
	finish("test_merge_input")

func _drag_ids(view: MergeRoomView, first: String, second: String) -> void:
	var views := view.player.input_views()
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = view.board._board_offset+views[first].position+Vector2(view.board._cell_size)*0.5
	view.board._gui_input(press)
	var motion := InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = view.board._board_offset+views[second].position+Vector2(view.board._cell_size)*0.5
	view.board._gui_input(motion)

func _buffer_cases(cases: MergeReleaseCases) -> void:
	for reduced in [false,true]:
		var initial := InterventionFixture.create(16,"automatic_chain")
		initial.board.set_tile(Vector2i(1,2),initial.catalog.create_tile(2))
		var view := MergeRoomView.new(); view.initial_override = initial.to_dict()
		view.automatic_clock = false; view.reduced_motion = reduced; root.add_child(view)
		if not await cases.loaded(view): check(false,"buffer fixture loads"); view.queue_free(); continue
		var first := initial.board.get_tile(Vector2i(3,3)).instance_id
		var second := initial.board.get_tile(Vector2i(1,3)).instance_id
		view.request_swap(Vector2i(3,3),Vector2i(2,3))
		var reserved := CanonicalCodec.digest(view.session.mechanical_snapshot())
		_drag_ids(view,first,second)
		check(view.input_buffer.pending.get("origin_id") == first and view.input_buffer.pending.get("destination_id") == second,"drag during swap buffers drawn gems by identity")
		check(CanonicalCodec.digest(view.session.mechanical_snapshot()) == reserved,"buffer capture never mutates reservation/resources/RNG")
		check(not view._cancel_button.disabled and "buffered" in view._status.text,"pending intent has visible feedback and cancel")
		if DisplayServer.get_name() != "headless" and not reduced:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(report_path("buffered-swap.png"))
		if await cases.window(view,2):
			check(view.session.state.board.get_tile(Vector2i(1,3)).instance_id == first and view.session.state.board.get_tile(Vector2i(1,3)).tier == 3,"buffer follows moving gem and denies automatic match")
			check(view.session.state.moves_remaining == initial.moves_remaining-2,"buffer costs one normal additional move")
			check(view.session.history.back().tick == 0,"buffer admitted at next window tick zero")
			var starts := view.player.observations.filter(func(o: Dictionary) -> bool: return o.kind == "swap_started")
			check(starts.size() == 2 and starts[1].us-starts[0].us >= 140000,"buffer plays after full initiating swap")
			check(view.input_buffer.pending.is_empty(),"buffer consumed once")
			var replay := MergeReplay.restored(MergeReplay.capture(view.session))
			check(replay.ok,"buffered command uses ordinary replay admission")
		# Keyboard queues a pair during motion; replacement remains one slot.
		view.restart()
		if await cases.loaded(view):
			view.request_swap(Vector2i(3,3),Vector2i(2,3))
			view.board.cursor_cell = Vector2i(1,3)
			for code in [KEY_ENTER,KEY_DOWN,KEY_ENTER]:
				var key := InputEventKey.new(); key.pressed = true; key.keycode = code; view.board._gui_input(key)
			check(not view.input_buffer.pending.is_empty(),"keyboard gesture buffers while swap runs")
			_drag_ids(view,first,second)
			check(view.input_buffer.pending.destination_id == second,"new completed gesture replaces pending pair")
			view._cancel_button.pressed.emit()
			check(view.input_buffer.pending.is_empty(),"visible cancellation clears buffered intent")
			_drag_ids(view,first,second)
			view._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			check(view.input_buffer.pending.is_empty() and not view.can_buffer(),"focus loss clears buffer and closes collection")
			view._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			view.input_buffer.put(first,second)
			var snapshot := view.session.snapshot()
			check(view.restore_session(snapshot) and view.input_buffer.pending.is_empty(),"restore discards unadmitted input")
		view.restart()
		if await cases.loaded(view):
			view.request_swap(Vector2i(3,3),Vector2i(2,3))
			var doomed := initial.board.get_tile(Vector2i(2,1)).instance_id
			view.input_buffer.put(doomed,second)
			if await cases.window(view,1):
				check(view.session.move_id == 1 and view.input_buffer.pending.is_empty() and "disappeared" in view._notice,"removed gem cancels without silently targeting its replacement")
				var before := CanonicalCodec.digest(view.session.mechanical_snapshot())
				view.input_buffer.put(first,view.session.state.board.get_tile(Vector2i(0,0)).instance_id)
				view._consume_buffer()
				check(CanonicalCodec.digest(view.session.mechanical_snapshot()) == before and "no longer" in view._notice,"nonadjacent buffered pair cancels without charge")
				view.input_buffer.put(first,second); view.restart()
				check(view.input_buffer.pending.is_empty(),"restart clears buffered pair")
		view.queue_free(); await process_frame; await process_frame
	# Pure intent resolution follows IDs through a relocation and never charges.
	var buffer := MergeInputBuffer.new()
	var board := initial_board()
	var a := board.get_tile(Vector2i(0,0)); var b := board.get_tile(Vector2i(1,0))
	buffer.put(a.instance_id,b.instance_id)
	board.set_tile(Vector2i(0,0),null); board.set_tile(Vector2i(1,0),null)
	board.set_tile(Vector2i(0,1),a); board.set_tile(Vector2i(1,1),b)
	var intent := buffer.take(board)
	check(intent.ok and intent.origin == Vector2i(0,1) and intent.destination == Vector2i(1,1),"relocation resolves selected identities at their new cells")

func initial_board() -> BoardState:
	return InterventionFixture.create().board
