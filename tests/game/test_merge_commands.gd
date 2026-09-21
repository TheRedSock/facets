extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _fixture() -> RunState:
	var state := InterventionFixture.create(16,"automatic_chain")
	# A four-match in column 1 is one swap away after the root promotion;
	# passing instead resolves the three-match in column 2.
	state.board.set_tile(Vector2i(1,2),state.catalog.create_tile(2))
	return state

func _started(mods: Dictionary = MergeModifiers.DEFAULTS) -> MergeSession:
	var session := MergeSession.new()
	check(session.start(_fixture().to_dict()),"redirect fixture admits as stable")
	check(session.configure_modifiers(mods),"typed modifiers admit")
	check(session.apply(InterventionFixture.command(session.state)).ok,"root publishes")
	check(session.presented(),"first merge presented")
	return session

func _run() -> void:
	var pass_session := _started()
	pass_session.tick(20)
	check(pass_session.apply().ok,"automatic control commits")
	var session := _started()
	var promoted_id := session.state.board.get_tile(Vector2i(2,3)).instance_id
	var old_facts: Array = session.last_batch.facts
	var redirect := RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3))
	var equilibrium := session._detached(); equilibrium.phase = "ready"
	check(equilibrium.quote(redirect).cost == session.quote(redirect).cost,"MW07 identical neighborhood default price in either phase")
	check(equilibrium.apply(redirect).ok,"equilibrium reference on same match neighborhood")
	check(session.quote(redirect).ok,"MW04 upgraded gem may leave pending automatic match")
	check(session.apply(redirect).ok,"MW04 stronger match intervention commits")
	check(session.state.board.to_dict() == equilibrium.state.board.to_dict() and session.state.room.craft == equilibrium.state.room.craft,"MW07 same base match effects and Craft")
	var matches: Array = session.last_batch.facts.filter(func(f: Dictionary) -> bool: return f.type == "match_committed")
	check(matches.size() == 1 and matches[0].size_class == 4,"MW04 exact four-match replaces automatic three-match")
	check(matches[0].survivor_id == promoted_id and matches[0].survivor == Vector2i(1,3),"moved upgraded gem survives at new destination")
	check(session.state.board.get_tile(Vector2i(2,4)).tier == 2 and session.state.board.get_tile(Vector2i(2,5)).tier == 2,"denied automatic match's other gems remain")
	check(session.state.room.craft == pass_session.state.room.craft+1,"stronger match earns ordinary four-match Craft")
	check(session.move_id == 2 and session.state.room.normal_turns == 2 and session.state.moves_remaining == 14,"MW07 intervention uses normal paid-move accounting")
	check(session.last_batch.facts.all(func(f: Dictionary) -> bool: return f.move_context == "intervention" and f.root_action_id == 2 and f.direct_input_batch),"MW11 direct intervention facts typed")
	check(old_facts.all(func(f: Dictionary) -> bool: return f.move_context == "equilibrium" and f.root_action_id == 1),"old fact ancestry remains its own scope")
	var vector := {"profile":MergeSession.PROFILE,"initial_digest":CanonicalCodec.digest(session.initial),
		"pass_state_digest":CanonicalCodec.digest(pass_session.mechanical_snapshot()),"pass_event_digest":pass_session.last_batch.event_digest,
		"redirect_state_digest":CanonicalCodec.digest(session.mechanical_snapshot()),"redirect_event_digest":session.last_batch.event_digest,
		"redirect_session_digest":CanonicalCodec.digest(session.snapshot())}
	check(vector == JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/goldens/merge-redirection-v1.json")),"reviewed automatic-versus-stronger-match checkpoint vector")
	write_report("redirection-vector.json",vector)
	_pure_rejections()
	_accounting()
	_repeated_and_remote()
	_tools()
	finish("test_merge_commands")

func _pure_rejections() -> void:
	var session := _started()
	var before := CanonicalCodec.encode(session.mechanical_snapshot())
	var clock_before := session.clock.duplicate(true)
	for endpoints in [[Vector2i(0,0),Vector2i(1,0)],[Vector2i(2,3),Vector2i(2,2)],[Vector2i(2,3),Vector2i(0,0)]]:
		check(not session.apply(RoomCommand.exchange(session.state,endpoints[0],endpoints[1])).ok,"MW05 invalid swap not licensed by pending match")
		check(CanonicalCodec.encode(session.mechanical_snapshot()) == before,"invalid endpoints pure")
	var command := RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3)).to_dict()
	command.revision -= 1
	check(not session.apply(RoomCommand.parse(command)).ok,"stale revision rejects")
	command.revision += 1; command.origin_id = "piece/stale"
	check(not session.apply(RoomCommand.parse(command)).ok,"stale identity rejects")
	check(session.clock == clock_before,"invalid attempts do not alter clock")
	var tool := RoomCommand.target(session.state,"action.promote_target",Vector2i(0,0))
	check(not session.quote(tool).ok,"MW10 tools remain equilibrium-only")

func _accounting() -> void:
	var session := _started({"schema":1,"discount_charges":1,"reward_bonus":1,"reward_trigger":"direct"})
	var command := RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3))
	check(session.quote(command).cost == 0,"MW12 finite-charge intervention discount")
	check(session.apply(command).ok,"discounted intervention commits")
	check(session.discount_charges == 0 and session.discount_spent == 1 and session.state.moves_remaining == 15,"one bounded charge consumed instead of Work")
	check(session.state.room.craft == 3 and session.context.entitlement == 2,"one normal base plus diagnostic reward")
	var entitlement := session.context.entitlement
	session.presented(); session.tick(20)
	check(session.apply().ok,"discounted scope continuation")
	check(session.context.entitlement >= entitlement and session.context.classification == "intervention","MW11 descendant context retained")
	check(session.last_batch.facts.all(func(f: Dictionary) -> bool: return not f.direct_input_batch and f.move_context == "intervention"),"automatic descendant facts distinct from direct batch")
	check(not MergeModifiers.admit({"schema":1,"discount_charges":-1,"reward_bonus":1,"reward_trigger":"direct"}).ok,"unbounded discount configuration rejects")
	var state := InterventionFixture.create()
	state.room.craft = 6
	var context := MergeMoveContext.new(state,InterventionFixture.command(state),1,"intervention")
	context.best_craft = 2; context.settle_increment()
	check(context.entitlement == 2 and state.room.craft == 6,"MW09 clipped entitlement consumed")
	state.room.craft = 3; context.settle_increment()
	check(state.room.craft == 3,"MW09 spent Craft cannot reclaim clipped entitlement")
	context.raw_bonus = 2; context.settle_increment()
	check(state.room.craft == 4 and context.entitlement == 3,"MW09 cap adds only new entitlement delta")
	context.settle_increment(); check(state.room.craft == 4,"MW09 no repeated settlement award")
	check(MergeModifiers.matches("intervention",false,"automatic") and not MergeModifiers.matches("intervention",false,"direct") and not MergeModifiers.matches("equilibrium",true,"any"),"typed predicates distinguish automatic/direct/context")

func _repeated_and_remote() -> void:
	# Seed/policy is fixed. Record the actual selected identities for replay evidence.
	var game := RunController.new(); check(game.start_room(null,1),"repeated room")
	game.apply_action(RoomCommand.begin(0))
	var session := MergeSession.new(); session.start(game.run_state.to_dict())
	var commands: Array = []
	var remote := false
	for index in 5:
		if session.phase == "merge_window": session.presented()
		var options := ActionLegality.enumerate_legal_swaps(session.state.board)
		if options.is_empty(): break
		var swap := options[0]
		var command := RoomCommand.exchange(session.state,swap.origin,swap.destination)
		if index > 0:
			var promoted: Array = session.last_batch.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_promoted").map(func(f: Dictionary) -> String: return f.instance_id)
			if command.data.origin_id not in promoted and command.data.destination_id not in promoted: remote = true
		commands.append(command.to_dict())
		check(session.apply(command).ok,"repeated paid command %d" % index)
	check(commands.size() == 5 and session.move_id == 5 and session.window_id == 5,"MW06 four consecutive interventions without arbitrary cap")
	check(remote,"MW05 remote legal match succeeds during a different merge")
	write_report("repeated.json",{"seed":1,"commands":commands,"remote":remote,"moves":session.move_id})

func _tools() -> void:
	var state := _fixture()
	state.room.craft = 3
	# Promote (1,3) to create a four-match immediately, before gravity.
	state.board.set_tile(Vector2i(1,3),state.catalog.create_tile(1))
	var session := MergeSession.new(); check(session.start(state.to_dict()),"tool fixture admits")
	check(session.apply(RoomCommand.target(session.state,"action.promote_target",Vector2i(1,3))).ok,"tool initiates merge")
	check(session.phase == "merge_window" and not session.context.reward_eligible and session.state.room.craft == 0,"MW10 suppressed tool merge still opens input window")
	session.presented()
	var choices := ActionLegality.enumerate_legal_swaps(session.state.board)
	check(not choices.is_empty(),"tool window has legal paid intervention witness")
	if not choices.is_empty():
		check(session.apply(RoomCommand.exchange(session.state,choices[0].origin,choices[0].destination)).ok,"paid intervention after tool")
		check(session.context.reward_eligible and session.state.room.tool_available and session.context.classification == "intervention","fresh paid scope restores normal eligibility and tool allowance")
