extends "res://tests/game/game_test.gd"

func _initialize() -> void:
	_run.call_deferred()

func fixture_state() -> RunState:
	var state := RunState.new()
	state.catalog = GameTestCatalog.create()
	state.board = GameFixtureAdapter.board(GameFixtureAdapter.read_cases()[0])
	state.moves_remaining = 2; state.streams = RngStreamBank.new(140901)
	state.sync_adapters()
	return state

func _run() -> void:
	test_atomicity()
	test_events()
	test_adapters_and_replay()
	test_opening_reroll()
	test_chain_family_terminal()
	finish("test_game_transaction")

func test_atomicity() -> void:
	var command := SwapCommand.new(Vector2i(1,1),Vector2i(1,0))
	var controller := RunController.new()
	check(controller.restore_snapshot(fixture_state().to_dict()), "fixture session admitted")
	var before := CanonicalCodec.encode(controller.run_state.to_dict())
	var replay_before := CanonicalCodec.encode(controller.export_replay())
	for fail_at in ["after_swap","after_promotion","after_spawn","before_commit"]:
		var result := controller.apply_action(command,-1,fail_at)
		check(not result.ok and result.status == "failed", fail_at + " reports failure")
		check(CanonicalCodec.encode(controller.run_state.to_dict()) == before and CanonicalCodec.encode(controller.export_replay()) == replay_before and controller.event_log.size() == 0, fail_at + " rolls back board/RNG/allocators/budget/recording")
	for field in ["max_work","max_facts","max_settle","max_cascades"]:
		var state := fixture_state()
		if field == "max_settle":
			var lower_match: Dictionary = GameFixtureAdapter.read_cases()[0].duplicate(true)
			lower_match.board.reverse()
			state.board = GameFixtureAdapter.board(lower_match)
		var limits := state.rules.to_dict(); limits[field] = 0; state.rules = RuleSet.new(limits)
		var initial := CanonicalCodec.encode(state.to_dict())
		var result := ActionTransaction.resolve(state,command)
		check(not result.ok and result.status == "failed" and CanonicalCodec.encode(state.to_dict()) == initial, field + " fails atomically")
	var invalid := controller.apply_action(SwapCommand.new(Vector2i.ZERO,Vector2i(2,1)))
	check(not invalid.ok and invalid.status == "rejected" and CanonicalCodec.encode(controller.run_state.to_dict()) == before, "invalid command preserves whole state")
	var result := controller.apply_action(command)
	check(result.ok and controller.run_state.moves_remaining == 1 and controller.run_state.revision == 1 and controller.export_replay().commands.size() == 1, "accepted action charges once and records once")
	var after := controller.run_state.digest()
	check(controller.acknowledge(result.action_id,result.generation) and controller.acknowledge(result.action_id,result.generation) and controller.run_state.digest() == after, "repeated acknowledgment is read-only")
	check(not controller.apply_action(command,0).ok, "stale revision rejected")
	check(not controller.restore_bytes(PackedByteArray([1,2,3])) and controller.run_state.digest() == after, "bad restore preserves live session")

func test_events() -> void:
	var state := fixture_state()
	var result := ActionTransaction.resolve(state,SwapCommand.new(Vector2i(1,1),Vector2i(1,0)))
	check(result.ok, "event action succeeds")
	if not result.ok: return
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/goldens/action-v1.json"))
	check(state.digest() == golden.initial_digest and result.state_digest == golden.state_digest and result.event_digest == golden.event_digest and CanonicalCodec.encode(result.facts).hex_encode() == golden.fact_bytes,"reviewed action protocol golden")
	var ids := {}; var removals := {}; var consumed := {}; var assists := []; var settled := 0
	for fact in result.facts:
		check(not ids.has(fact.event_id), "event ID unique")
		if fact.parent_event_id != null: check(ids.has(fact.parent_event_id), "parent precedes child")
		ids[fact.event_id] = true
		check(fact.root_action_id == 1 and fact.is_read_only(), "immutable fact has root")
		if fact.type == "tile_removed": removals[fact.removal_id] = fact
		if fact.type == "tile_consumed": consumed[fact.removal_id] = fact
		if fact.type == "swap_assisted": assists.append(fact.instance_id)
		if fact.type == "action_settled": settled += 1
		if fact.type == "tile_promoted": check(fact.old.instance_id == fact.new.instance_id and fact.old.tier + 1 == fact.new.tier, "promotion keeps instance/source snapshot")
	for id in consumed: check(removals.has(id) and removals[id].instance_id == consumed[id].instance_id, "removal subtype shares identity")
	check(assists == [state.board.get_tile(Vector2i(1,0)).instance_id], "displaced helper assist uses initial components")
	check(settled == 1 and result.facts[-1].type == "action_settled", "one final settlement")
	check_projection(result)
	var log := EventLog.new(); log._max_entries = 2
	var payload := {"nested":{"counter":1}}
	log.push(&"one",payload); payload.nested.counter = 99
	check(log.entries[0].nested.counter == 1, "log payload deep copied")
	for i in 5: log.push(&"next")
	check(log.entries[0].index == 4 and log.entries[1].index == 5, "truncation does not reuse IDs")
	log.clear(); log.push(&"after_clear")
	check(log.entries[0].index == 6, "clear does not reuse IDs")

func test_adapters_and_replay() -> void:
	var controller := RunController.new()
	controller.restore_snapshot(fixture_state().to_dict())
	check(controller.begin_swap(Vector2i(1,1),Vector2i(1,0)), "compatibility begin commits")
	var digest := controller.run_state.digest()
	controller.resolve_remaining_cascades(); controller.resolve_remaining_cascades()
	controller.finalize_swap(); controller.finalize_swap()
	check(controller.run_state.digest() == digest and controller.export_replay().commands.size() == 1, "compatibility calls do not finalize twice")
	var replay := controller.export_replay()
	var verified := ReplayRecord.verify(CanonicalCodec.decode(CanonicalCodec.encode(replay)).value)
	check(verified.ok and verified.state.digest() == digest, "self-contained versioned replay reproduces checkpoint/events")
	replay.commands[0].event_digest = "wrong"
	check(not ReplayRecord.verify(replay).ok, "event checkpoint mismatch rejects")
	var old_generation := controller.generation
	controller.restart()
	check(not controller.acknowledge(1,old_generation), "stale session acknowledgment rejects")

func test_opening_reroll() -> void:
	var controller := RunController.new()
	var layout := BoardLayoutResource.new(); layout.board_size = Vector2i(4,4); layout.add_blocked(Vector2i(1,1))
	check(controller.start_new_run({"board_layout":layout,"seed":8}), "shaped opening")
	var roster := controller.run_state.catalog.to_dict()
	check(controller.reroll_board(9) and controller.get_board().is_blocked(Vector2i(1,1)) and controller.run_state.catalog.to_dict() == roster, "reroll preserves layout and roster/supply")
	var before := controller.run_state.digest()
	var invalid := BoardLayoutResource.new(); invalid.board_size = Vector2i.ONE
	check(not controller.start_new_run({"board_layout":invalid}) and controller.run_state.digest() == before, "failed opening retains committed session")

func check_projection(result: Dictionary) -> void:
	var board: BoardState = result.before.duplicate_board()
	board.swap_cells(result.command.origin,result.command.destination)
	for step in result.timeline.cascade_steps:
		for event in step.remove_events:
			check(board.get_tile(event.cell) != null and board.get_tile(event.cell).instance_id == event.instance_id,"projection removes existing identity")
			board.remove_tile(event.cell)
		for event in step.upgrade_events:
			var piece := board.get_tile(event.cell)
			check(piece != null and piece.instance_id == event.instance_id,"projection upgrades existing survivor")
			piece.tier = event.new.tier; piece.tile_id = event.new.tile_id; piece.match_group = event.new.match_group
			piece.family_tags.assign(event.new.family_tags)
		for event in step.gravity_events:
			check(board.get_tile(event.from) != null and board.get_tile(event.from).instance_id == event.instance_id and board.get_tile(event.to) == null,"projection segment preserves occupancy and identity")
			board.move_tile(event.from,event.to)
		for event in step.spawn_events:
			check(board.get_tile(event.cell) == null,"projection spawns only into empty cell")
			var piece := TileState.new()
			piece.instance_id = event.instance_id; piece.tile_id = event.tile_id; piece.tier = event.tier; piece.match_group = event.source.match_group; piece.family_tags.assign(event.source.family_tags)
			board.set_tile(event.cell,piece)
	board.next_instance = result.after.next_instance
	check(board.digest() == result.after.digest(),"canonical fact projection reproduces complete final board")

func test_chain_family_terminal() -> void:
	for fixture in GameFixtureAdapter.read_cases():
		if fixture.phase != "swap_then_first_match": continue
		var candidate := fixture_state(); candidate.board = GameFixtureAdapter.board(fixture)
		var swap := SwapCommand.new(GameFixtureAdapter.cell(fixture.swap[0]),GameFixtureAdapter.cell(fixture.swap[1]))
		var action := ActionTransaction.resolve(candidate,swap)
		check(action.ok and action.state.moves_remaining == 1,fixture.id + " complete action always costs exactly one")
		if action.ok: check_projection(action)
	var state := fixture_state()
	var data := state.catalog.to_dict()
	data.definitions.debug_tier_1.family_tags = ["source_family"]
	data.definitions.debug_tier_2.family_tags = ["promoted_family"]
	state.catalog = GameCatalog.admit(data).catalog
	for pos in state.board.all_cells(): state.board.get_tile(pos).family_tags.assign(state.catalog.definition(state.board.get_tile(pos).tier).family_tags)
	var result := ActionTransaction.resolve(state,SwapCommand.new(Vector2i(1,1),Vector2i(1,0)))
	check(result.ok,"cross-family action commits")
	if result.ok:
		var promotion: Dictionary = result.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_promoted")[0]
		check(promotion.old.family_tags.map(str) == ["source_family"] and promotion.new.family_tags.map(str) == ["promoted_family"],"immutable old/new family snapshots")
		check_projection(result)
	state = fixture_state(); state.moves_remaining = 1
	for pos in state.board.all_cells():
		if state.board.get_tile(pos).tier == 1:
			var original := state.board.get_tile(pos); var terminal := state.catalog.create_tile(8); terminal.instance_id = original.instance_id; state.board.set_tile(pos,terminal)
	result = ActionTransaction.resolve(state,SwapCommand.new(Vector2i(1,1),Vector2i(1,0)))
	check(result.ok and result.state.phase == "budget_exhausted" and result.state.moves_remaining == 0,"last accepted swap costs one and exhausts budget")
	if result.ok:
		check(result.state.terminal_recovered.get("8",0) == 3,"T8 recovers every member")
		check(result.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_consumed" and f.source.tier == 8).is_empty(),"T8 removal has no consumption subtype")
		check(not ActionTransaction.resolve(result.state,SwapCommand.new(Vector2i(1,1),Vector2i(1,0))).ok,"zero budget rejects")
		check_projection(result)
	state = fixture_state()
	state.board = BoardState.new(Vector2i(3,3))
	var rows := [[3,1,4],[4,1,3],[1,2,2]]
	for pos in state.board.all_cells(): state.board.set_tile(pos,state.catalog.create_tile(rows[pos.y][pos.x]))
	var limits := state.rules.to_dict(); limits.max_chains = 0; state.rules = RuleSet.new(limits)
	var before := state.digest()
	result = ActionTransaction.resolve(state,SwapCommand.new(Vector2i(0,2),Vector2i(1,2)))
	check(not result.ok and result.code == "chain_cap" and state.digest() == before,"pre-gravity chain cap rolls back complete action")
