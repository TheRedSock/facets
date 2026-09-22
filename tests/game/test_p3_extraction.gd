extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func extraction(state: RunState, outlets: Array, tier: int, demand: int) -> RunState:
	var data := state.room.definition.data.duplicate(true)
	data.schema = 2; data.objective = "extract"; data.marked_ids = []
	data.merge({"outlets":outlets,"minimum_tier":tier,"demand":demand,"outlet_requires_clear":true,"outlet_requires_unlocked":true})
	var admitted := RoomDefinition.admit(data,state.catalog)
	check(admitted.ok,"typed extraction objective admits")
	state.room.definition = admitted.definition; state.rules = RuleSet.for_p3()
	return state

func _run() -> void:
	for fixture in GameFixtureAdapter.read_cases():
		if fixture.id != "outlet_delivery": continue
		var state := RunState.new(); state.catalog = P3Content.catalog().catalog; state.rules = RuleSet.for_p3()
		var board := BoardState.new(Vector2i(3,3)); board.room_board = true
		var data := {"schema":2,"id":"frozen_outlet","initial_board":board.to_dict(),"work":int(fixture.work),"craft":1,"objective":"extract","marked_ids":[],
			"outlets":[GameFixtureAdapter.cell(fixture.outlets[0])],"minimum_tier":int(fixture.objective.minimum_tier),"demand":int(fixture.objective.count),"outlet_requires_clear":true,"outlet_requires_unlocked":true}
		var admitted := RoomDefinition.admit(data,state.catalog); check(admitted.ok,"frozen P0 outlet data admits")
		state.board = board; state.room = RoomState.new(); state.room.definition = admitted.definition
		for y in 3:
			for x in 3: board.set_tile(Vector2i(x,y),state.catalog.create_tile(int(fixture.board[y][x])))
		state.moves_remaining = 0; state.room.normal_turns = 1; state.revision = 1; state.next_action = 2; state.next_event = 3
		state.streams = RngStreamBank.new(int(fixture.seed)); state.sync_adapters()
		var context := MergeMoveContext.new(state,RoomCommand.begin(1),1,"equilibrium")
		var rng := state.streams.capture()
		check(ExtractionResolver.collect(context).removed and RoomBoundaryResolver.finish(context),"P0 outlet executes at stable boundary")
		check(state.phase == fixture.expected.room_result and state.moves_remaining == 0,"completion wins on final Work")
		check(context.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_removed").size() == int(fixture.expected.removed_count),"P0 removal count")
		var facts := context.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_extracted")
		check(facts.size() == int(fixture.expected.extracted_count) and board.get_tile(GameFixtureAdapter.cell(fixture.expected.carry_excludes_cell)) == null,"P0 extraction and carry exclusion")
		check(state.streams.capture() == rng and state.terminal_recovered.is_empty(),"completion stops refill; extraction is not recovery")
		check(not ExtractionResolver.collect(context).removed,"completed demand cannot remove again")
		check(RunState.restored(state.to_dict(),false).ok,"terminal holes admit as committed state")
	var state := extraction(InterventionFixture.create(),[Vector2i(2,5),Vector2i(0,5)],5,1)
	for cell in [Vector2i(0,5),Vector2i(2,5)]: state.board.set_tile(cell,state.catalog.create_tile(5))
	var context := MergeMoveContext.new(state,InterventionFixture.command(state),1,"equilibrium")
	check(ExtractionResolver.collect(context).removed,"multiple candidates extract")
	check(state.room.deliveries[0].cell == Vector2i(0,5) and state.board.get_tile(Vector2i(2,5)) != null,"ordered extraction stops immediately at demand")
	check(not context.reward_eligible and context.cause == "extraction","extraction descendants suppressed")
	var blocked := extraction(InterventionFixture.create(),[Vector2i(0,5),Vector2i(3,5)],5,1)
	blocked.board.set_tile(Vector2i(0,5),blocked.catalog.create_tile(4))
	context = MergeMoveContext.new(blocked,InterventionFixture.command(blocked),1,"equilibrium")
	check(not ExtractionResolver.collect(context).removed,"threshold and own-cell obstacle block extraction")
	blocked.board.set_tile(Vector2i(0,5),blocked.catalog.create_tile(5)); blocked.board.get_cell(Vector2i(0,5)).lock = {"kind":"movement_lock","durability":1}
	check(not ExtractionResolver.collect(context).removed,"own-cell lock blocks extraction")
	blocked.board.get_cell(Vector2i(0,5)).lock = {}
	check(ExtractionResolver.collect(context).removed,"adjacent rubble does not remotely lock an outlet")
	for demand in [1,2]:
		var integrated := extraction(InterventionFixture.create(1),[Vector2i(0,5)],5,demand)
		integrated.board.set_tile(Vector2i(0,5),integrated.catalog.create_tile(5))
		var session := MergeSession.new(); check(session.start(integrated.to_dict()),"integrated extraction starts")
		check(session.apply(InterventionFixture.command(session.state)).ok,"last paid swap commits before extraction")
		check(session.phase == "merge_window" and session.state.room.deliveries.is_empty(),"outlets never collect in intervention window")
		for step in 150:
			if session.phase in ["complete","failed"]: break
			if session.phase == "merge_window": session.presented(); session.tick(20)
			var before := CanonicalCodec.encode(session.snapshot())
			var rejected := session.prepare(null,"after_extraction")
			if not rejected.ok: check(CanonicalCodec.encode(session.snapshot()) == before,"extraction failure rolls back unpublished batch")
			var result := session.apply(); check(result.ok,"extraction continuation commits")
			if not result.ok: break
		check(session.phase == ("complete" if demand == 1 else "failed"),"demand determines final Work result")
		check(session.state.room.deliveries.size() == 1,"one unique integrated delivery")
		check(MergeReplay.restored(session.snapshot(),false).ok,"full extraction replay/restore")
	finish("test_p3_extraction")
