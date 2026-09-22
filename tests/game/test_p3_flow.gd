extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/p3-preparation.json"))
	for expected in spec.rooms:
		var room := P3Rooms.definition(expected.id,P3Content.catalog().catalog)
		check(room.ok,"authored room admits "+expected.id)
		check(room.board.size == Vector2i(8,8) and room.definition.data.work == int(expected.work) and room.definition.data.objective == expected.kind,"room matches frozen size/budget/objective")
		var cells: Array = []
		for item in room.board.obstacles.values(): cells.append([item.cell.x,item.cell.y])
		var expected_cells: Array = []
		for cell in expected.rubble: expected_cells.append([int(cell[0]),int(cell[1])])
		check(cells == expected_cells,"authored rubble positions match preparation")
	# All candidate pairs, including fallback twice, without claiming a synthetic
	# outcome is a winning gameplay witness.
	for first in spec.reward_pool:
		for second in spec.reward_pool:
			if first == second and first != "next_room_craft": continue
			var run: ExpeditionState = ExpeditionState.create(7).run
			run.phase = "reward_selection"; run.offers = spec.reward_pool.duplicate()
			var before := CanonicalCodec.encode(run.snapshot())
			check(not run.choose_reward(first,run.revision(),false).ok and before == CanonicalCodec.encode(run.snapshot()),"failed asset preflight preserves reward screen")
			check(run.choose_reward(first,run.revision()).ok,"first reward "+first)
			check(run.reward_pool().size() >= 3 and second in run.reward_pool(),"second reward eligibility "+first+"/"+second)
			for route in ["deep_seam","commission"]:
				var rng := run.state.streams.capture()
				run.phase = "route_selection"
				check(run.choose_route(route,run.revision()).ok and rng == run.state.streams.capture(),"route consumes persisted choice without RNG")
			run.room_index = 1; run.phase = "reward_selection"; run.offers = run.reward_pool()
			check(run.choose_reward(second,run.revision()).ok and run.phase == "next_room_ready","every second-screen pair commits")
	var initial: ExpeditionState = ExpeditionState.create(7).run
	check(ExpeditionState.restored(initial.snapshot(),false).ok,"briefing whole-run replay")
	check(initial.begin(initial.revision()).ok,"begin whole-run replay")
	check(ExpeditionState.restored(initial.snapshot(),false).ok,"ready whole-run replay")
	# Actual commands, no board mutation. Every batch checkpoint is retained.
	for route in ["deep_seam","commission"]:
		var run: ExpeditionState = ExpeditionState.create(7).run
		var steps := 0
		while run.phase != "results" and steps < 800:
			steps += 1
			match run.phase:
				"briefing": check(run.begin(run.revision()).ok,"scripted Begin")
				"playing":
					var result: Dictionary
					if run.session.phase == "ready":
						var command := P3Policy.command(run.session)
						if command == null: check(false,"policy found command"); break
						result = run.session.apply(command)
					else:
						if run.session.phase == "merge_window": run.session.presented(); run.session.tick(20)
						result = run.session.apply()
					check(result.ok,"scripted batch")
					if not result.ok: break
					if run.session.phase in ["complete","failed"]: check(run.finish_room().ok,"record immutable room outcome")
				"carry_selection":
					var eligible := run.eligible_carry()
					eligible.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.tier > b.tier if a.tier != b.tier else a.instance_id < b.instance_id)
					var ids: Array = []
					for tile in eligible.slice(0,2): ids.append(tile.instance_id)
					check(run.confirm_carry(ids,run.revision()).ok,"scripted carry")
					var snapshot := CanonicalCodec.encode(run.snapshot()); var rng := run.state.streams.capture()
					check(ExpeditionState.restored(run.snapshot(),false).ok,"reward screen replays without reroll")
					check(snapshot == CanonicalCodec.encode(run.snapshot()) and run.state.streams.capture() == rng,"reopening is pure")
				"reward_selection": check(run.choose_reward("steady_hand" if "steady_hand" in run.offers else run.offers[0],run.revision()).ok,"scripted reward")
				"route_selection": check(run.choose_route(route,run.revision()).ok,"scripted route")
				"next_room_ready": check(run.publish_entry(run.prepare_next()),"scripted next room")
		check(run.phase == "results","scripted run terminates "+route)
		check(ExpeditionState.restored(run.snapshot(),false).ok,"complete expedition replay "+route)
		write_report(route+".fac",run.snapshot(),true)
		print("P3_FLOW: ",route," room=",run.room_index," outcome=",run.current().phase," steps=",steps)
	finish("test_p3_flow")
