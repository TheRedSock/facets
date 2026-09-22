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
	await create_timer(0.1).timeout
	finish("test_merge_input")
