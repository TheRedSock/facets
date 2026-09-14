extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for case in GameFixtureAdapter.read_cases():
		if case.id not in ["recovery_possible","recovery_impossible"]: continue
		# The frozen observation is a recovery query; a disconnected marked cell
		# extends its geometry without changing its original 3x3 swap topology.
		var rows: Array = case.board.duplicate(true)
		rows.append([0,0,0])
		var state := RoomTestSupport.fixture(rows,[{"cell":Vector2i(1,3)}],16,0)
		state.board.set_blocked(Vector2i(0,3),true); state.board.set_blocked(Vector2i(2,3),true)
		state.room.tool_available = false
		state.streams = RngStreamBank.new(int(case.seed))
		check(not ActionLegality.has_legal_swap(state.board),case.id+" no legal swaps")
		var board_before := state.board.to_dict()
		var other_streams := state.streams.capture()
		var context := ActionContext.new(state,RoomCommand.begin(state.revision))
		var result := RecoveryResolver.recover(context)
		check(result.ok,case.id+" recovery bounded")
		check(state.moves_remaining == 16 and state.room.craft == 0 and not state.room.tool_available,case.id+" economy preserved")
		var snapshot := state.streams.capture()
		for name in ["board","rewards","routes"]:
			check(snapshot.streams[name] == other_streams.streams[name],case.id+" stream isolation "+name)
		if case.id == "recovery_possible":
			check(result.recovered and ActionLegality.has_legal_swap(state.board),"recovery witnesses a legal swap")
			check(MatchDetector.new().find_matches(state.board).is_empty(),"no free recovery matches")
			var old_ids: Array = []; var new_ids: Array = []
			for cell in board_before.cells:
				if cell.tile != null: old_ids.append(CanonicalCodec.digest(cell.tile))
			for pos in state.board.all_cells():
				if state.board.get_tile(pos) != null: new_ids.append(CanonicalCodec.digest(state.board.get_tile(pos).to_dict()))
			old_ids.sort(); new_ids.sort()
			check(old_ids == new_ids,"full instance multiset retained")
		else:
			check(not result.recovered and state.board.to_dict() == board_before,"high-tier board unchanged")
			check(state.room.recovery_attempts == 0 and snapshot == other_streams,"no eligible pieces draw no RNG")
	var game := RunController.new(); check(game.start_room(null,4),"room recovery integration starts")
	check(game.apply_action(RoomCommand.begin(0)).ok,"room begins")
	for i in 16:
		if game.run_state.phase != "ready": break
		var swaps := game.enumerate_legal_swaps()
		if swaps.is_empty(): break
		var result := game.apply_action(RoomCommand.exchange(game.run_state,swaps[0].origin,swaps[0].destination))
		check(result.ok,"complete room action %d/%s" % [i,result.get("code")])
		if not result.ok: break
	check(ReplayRecord.verify(game.export_replay()).ok,"full room sequence replay")
	# Two of each match group can never create a triple, under any permutation.
	var exhausted := RoomTestSupport.fixture([[1,2],[3,1],[2,3],[0,0]],
		[{"cell":Vector2i(0,3)},{"cell":Vector2i(1,3)}],16,0)
	exhausted.room.tool_available = false
	var original := exhausted.to_dict()
	var replay_state := exhausted.duplicate_state()
	for subject in [exhausted,replay_state]:
		var context := ActionContext.new(subject,RoomCommand.begin(subject.revision))
		check(RoomBoundaryResolver.finish(context),"ordinary exhaustion commits")
		check(subject.phase == "failed" and subject.room.failure_reason == "board_locked" and subject.room.recovery_attempts == 64,"64 candidates exhausted")
		check(subject.board.to_dict() == original.board,"exhaustion retains original board")
	check(exhausted.digest() == replay_state.digest(),"recovery exhaustion exactly deterministic")
	check(exhausted.streams.capture() != original.rng,"recovery consumes its RNG on exhaustion")
	# Recovery is required after this nonmatching exchange; a technical budget
	# cap must roll back root tool cost, board mutation, IDs, facts and RNG.
	var capped := RoomTestSupport.fixture([[2,1,3],[1,2,1],[3,0,4]],[{"cell":Vector2i(1,2)}],16,6)
	var rules := capped.rules.to_dict(); rules.max_work = 80
	capped.rules = RuleSet.new(rules)
	game = RoomTestSupport.controller(capped)
	var before := game.run_state.digest(); var record := CanonicalCodec.digest(game.export_replay())
	var failure := game.apply_action(RoomCommand.exchange(game.run_state,Vector2i.ZERO,Vector2i.RIGHT,true))
	check(not failure.ok and failure.code == "work_cap" and failure.status == "failed","recovery work cap is technical failure")
	check(game.run_state.digest() == before and CanonicalCodec.digest(game.export_replay()) == record,"recovery cap rolls back entire tool")
	finish("test_game_recovery")
