extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _session(variant: String = "offered", work: int = 16) -> MergeSession:
	var result := MergeSession.new()
	check(result.start(InterventionFixture.create(work,variant).to_dict()),"admitted merge fixture")
	return result

func _pass(session: MergeSession) -> Dictionary:
	if session.phase == "merge_window":
		if not session.clock.started: check(session.presented(),"present once")
		check(session.tick(20),"expiry tick")
	return session.apply()

func _run() -> void:
	var session := _session("automatic_chain")
	var initial_rng := session.state.streams.capture()
	var initial_bytes := CanonicalCodec.encode(session.mechanical_snapshot())
	var prepared := session.prepare(InterventionFixture.command(session.state))
	check(prepared.ok,"MW01 detached first batch resolves")
	check(CanonicalCodec.encode(session.mechanical_snapshot()) == initial_bytes,"prepare does not mutate authority")
	if not prepared.ok: print(prepared); finish("test_merge_kernel"); return
	check(session.publish(prepared),"publish admitted root")
	check(session.phase == "merge_window" and session.state.moves_remaining == 15,"MW01 window and one normal cost")
	check(session.state.room.normal_turns == 1 and session.move_id == 1,"normal turn and move scope")
	check(session.state.board.get_tile(Vector2i(2,3)).tier == 2,"MW03 promotion chain remains unresolved")
	check(not MatchDetector.new().find_matches(session.state.board).is_empty(),"pending automatic match exists")
	check(session.state.streams.capture() == initial_rng,"no speculative refill RNG")
	var first_facts: Array = session.last_batch.facts
	var first_hash := CanonicalCodec.digest(first_facts)
	check(_pass(session).ok and session.phase == "merge_window","MW03 automatic merge opens next window")
	check(session.state.board.get_tile(Vector2i(2,5)).tier == 3,"automatic survivor follows canonical no-swap priority")
	check(session.window_id == 2 and session.move_id == 1,"free continuation retains move and creates window")
	check(CanonicalCodec.digest(first_facts) == first_hash,"published facts never extended")
	_disjoint()
	_caps()
	_terminal()
	_pass_corpus()
	finish("test_merge_kernel")

func _disjoint() -> void:
	var state := InterventionFixture.create()
	# Two complete components in a kernel fixture; unlike session start this
	# deliberately represents a board immediately after a command.
	for x in 3:
		state.board.set_tile(Vector2i(x,0),state.catalog.create_tile(3))
		state.board.set_tile(Vector2i(x,4),state.catalog.create_tile(2))
	state.board.set_tile(Vector2i(1,5),state.catalog.create_tile(5))
	state.board.set_tile(Vector2i(3,0),state.catalog.create_tile(5))
	var context := MergeMoveContext.new(state,RoomCommand.begin(state.revision),1,"equilibrium")
	var result := MergeKernel.resolve_match(context,{"cascade":0,"chain":0},[])
	check(result.ok and result.matched,"MW02 simultaneous components resolve")
	var matches := context.facts.filter(func(f: Dictionary) -> bool: return f.type == "match_committed")
	check(matches.size() == 2,"MW02 exactly two disjoint components in one batch")
	if matches.size() == 2:
		check(matches[0].cells.has(Vector2i(0,0)) and matches[1].cells.has(Vector2i(0,4)),"canonical component order")
	var upper := state.board.get_tile(Vector2i(2,0)); var lower := state.board.get_tile(Vector2i(2,4))
	check(upper != null and lower != null and upper.tier == 4 and lower.tier == 3,"both exact survivors promoted once")

func _caps() -> void:
	var malformed := _session()
	malformed.apply(InterventionFixture.command(malformed.state)); malformed.presented(); malformed.tick(20)
	# Simulate an incorrectly implemented future reaction emitting an unsupported
	# wire type. A complete state hash is mandatory even for internal candidates.
	malformed.context.facts.append({"type":"diagnostic_bad_fact","value":0.5})
	var original_state := malformed.state.digest(); var original_context := malformed.context.capture()
	var rejected := malformed.prepare()
	check(not rejected.ok and rejected.code == "merge_codec_failure","unencodable complete candidate never publishes an empty hash")
	check(malformed.state.digest() == original_state and malformed.context.capture() == original_context,"codec rejection preserves state, RNG, accounting and context")
	var initial := InterventionFixture.create(16,"automatic_chain")
	var rules := initial.rules.to_dict(); rules.max_chains = 0
	initial.rules = RuleSet.new(rules)
	var session := MergeSession.new(); check(session.start(initial.to_dict()),"cap fixture admits")
	check(session.apply(InterventionFixture.command(session.state)).ok,"cap permits initial batch")
	session.presented(); session.tick(20)
	var before := CanonicalCodec.encode(session.mechanical_snapshot())
	var result := session.apply()
	check(not result.ok and result.code == "chain_cap","MW14 chain budget survives decision boundary")
	check(CanonicalCodec.encode(session.mechanical_snapshot()) == before,"MW14 failed continuation preserves published prefix")
	for fault in ["after_cost","after_promotion","after_obstacle","before_commit"]:
		session = _session()
		before = CanonicalCodec.encode(session.mechanical_snapshot())
		check(not session.apply(InterventionFixture.command(session.state),fault).ok,"injected failure "+fault)
		check(CanonicalCodec.encode(session.mechanical_snapshot()) == before,"candidate rollback "+fault)
	session = _session()
	session.apply(InterventionFixture.command(session.state)); session.presented(); session.tick(20)
	before = CanonicalCodec.encode(session.mechanical_snapshot())
	check(not session.apply(null,"after_spawn").ok,"gravity failure injected")
	check(CanonicalCodec.encode(session.mechanical_snapshot()) == before,"gravity rollback includes RNG and facts")
	for limit in ["max_work","max_facts","max_cascades"]:
		initial = InterventionFixture.create()
		rules = initial.rules.to_dict(); rules[limit] = 0; initial.rules = RuleSet.new(rules)
		session = MergeSession.new(); check(session.start(initial.to_dict()),"bounded fixture "+limit)
		before = CanonicalCodec.encode(session.mechanical_snapshot())
		result = session.apply(InterventionFixture.command(session.state))
		check(not result.ok and result.code.ends_with("_cap"),"MW14 enforced "+limit)
		check(CanonicalCodec.encode(session.mechanical_snapshot()) == before,"MW14 full unpublished rollback "+limit)

func _terminal() -> void:
	var session := _session("offered",1)
	check(session.apply(InterventionFixture.command(session.state)).ok,"final Work legal swap")
	check(session.state.moves_remaining == 0 and session.phase == "merge_window","MW13 no premature exhaustion at merge")
	var batches := 0
	while session.phase in ["merge_window","gravity"] and batches < 100:
		check(_pass(session).ok,"last Work automatic continuation")
		batches += 1
	check(session.phase in ["failed","complete"] and batches < 100,"MW13 automatic work finishes before final result")
	# Move the marked obstacle next to the root component, one hit from completion.
	var state := InterventionFixture.create(1)
	var resource := RoomDefinitionResource.new()
	resource.room_id = "merge_terminal_fixture"; resource.work = 1; resource.craft = 1
	resource.layout = BoardLayoutResource.new(); resource.layout.board_size = Vector2i(4,6)
	resource.obstacles = [{"id":"rubble/end","cell":Vector2i(3,2),"kind":"rubble","durability":1}]
	resource.marked_ids = ["rubble/end"]
	var room := RoomDefinition.compile(resource,state.catalog)
	state.room.definition = room.definition
	state.board.remove_tile(Vector2i(3,2)); state.board.obstacles = room.board.obstacles.duplicate(true)
	state.board.set_tile(Vector2i(3,5),state.catalog.create_tile(3))
	# Hand-authored terminal expectation: the three T1 gems in column 3
	# merge into the moved gem at row 4, the adjacent last rubble breaks,
	# and the two consumed cells plus the former rubble cell remain empty.
	# No automatic settling/refill is permitted after this new terminal boundary.
	var expected := state.board.duplicate_board()
	expected.swap_cells(Vector2i(3,3),Vector2i(2,3))
	expected.remove_tile(Vector2i(2,1)); expected.remove_tile(Vector2i(2,2))
	var promoted := state.catalog.create_tile(2)
	promoted.instance_id = expected.get_tile(Vector2i(2,3)).instance_id
	expected.set_tile(Vector2i(2,3),promoted); expected.obstacles.erase("rubble/end")
	check(session.start(state.to_dict()),"terminal fixture admission")
	var rng := session.state.streams.capture()
	check(session.apply(InterventionFixture.command(session.state)).ok,"terminal root commits")
	check(session.phase == "complete" and session.state.moves_remaining == 0,"MW13 completion wins final Work")
	check(session.state.streams.capture() == rng and session.window_id == 0,"terminal merge stops before refill or another window")
	check(session.state.board.to_dict() == expected.to_dict(),"MW08 exact hand-authored terminal board, IDs and allocator")
	var legacy := RunController.new()
	check(legacy.restore_snapshot(state.to_dict()),"early-terminal legacy control admits unchanged initial state")
	check(legacy.apply_action(InterventionFixture.command(legacy.run_state)).ok,"early-terminal legacy control executes")
	check(legacy.run_state.phase == "complete" and legacy.run_state.board.to_dict() != expected.to_dict(),"MW08 explicitly retained legacy post-completion settling difference")
	check(legacy.run_state.moves_remaining == session.state.moves_remaining and legacy.run_state.room.craft == session.state.room.craft,"terminal difference does not hide Work/Craft mismatch")

func _pass_corpus() -> void:
	var samples := 0
	var differences := 0
	for seed_value in range(1,11):
		var game := RunController.new(); check(game.start_room(null,seed_value),"legacy corpus start")
		game.apply_action(RoomCommand.begin(0))
		for index in 5:
			var legal := game.enumerate_legal_swaps()
			if legal.is_empty(): break
			var selected := legal[(seed_value+index)%legal.size()]
			var command := RoomCommand.exchange(game.run_state,selected.origin,selected.destination)
			var session := MergeSession.new(); check(session.start(game.run_state.to_dict()),"corpus successor admitted")
			var result := session.apply(command)
			check(result.ok,"corpus root resolves")
			var count := 0
			while result.ok and session.phase in ["merge_window","gravity"] and count < 150:
				result = _pass(session); count += 1
			check(result.ok and count < 150,"corpus reaches stable boundary")
			var control := game.apply_action(command)
			check(control.ok,"legacy control resolves")
			if session.phase != "complete":
				check(session.state.board.to_dict() == game.run_state.board.to_dict(),"MW08 unchanged all-pass board %d/%d" % [seed_value,index])
				check(session.state.streams.capture() == game.run_state.streams.capture(),"MW08 exact RNG")
				check(session.state.moves_remaining == game.run_state.moves_remaining and session.state.room.craft == game.run_state.room.craft,"MW08 exact Work/Craft")
			else:
				differences += 1
				check(game.run_state.phase == "complete" and session.state.room.remaining(session.state.board) == 0,"early-terminal difference explicitly classified")
			samples += 1
	check(samples == 50,"all 50 named corpus actions complete")
	write_report("kernel.json",{"samples":samples,"early_terminal_cases":differences,"assertions":assertions,"failures":failures})
