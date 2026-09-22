extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func fixture(tier: int = 1, family: String = "") -> RunState:
	var state := InterventionFixture.create(16,"automatic_chain")
	state.rules = RuleSet.for_p3(); state.catalog = P3Content.catalog().catalog
	if not family.is_empty():
		var data := state.catalog.to_dict(); data.definitions[data.roster[tier-1]].family_tags = [family]
		state.catalog = GameCatalog.admit(data).catalog
	for pos in state.board.all_cells():
		var old := state.board.get_tile(pos)
		if old == null: continue
		var tile := state.catalog.create_tile(tier if old.tier == 1 else old.tier)
		tile.instance_id = old.instance_id; state.board.set_tile(pos,tile)
	state.sync_adapters()
	return state

func merge(state: RunState, suppressed: bool = false) -> MergeMoveContext:
	var command := InterventionFixture.command(state)
	var context := MergeMoveContext.new(state,command,1,"equilibrium")
	context.reward_eligible = not suppressed
	state.board.swap_cells(command.data.origin,command.data.destination)
	var result := MergeKernel.resolve_match(context,{"cascade":0,"chain":0},[command.data.origin,command.data.destination])
	check(result.ok,"family batch commits")
	return context

func count(context: MergeMoveContext, type: String) -> int:
	return context.facts.filter(func(f: Dictionary) -> bool: return f.type == type).size()

func _run() -> void:
	var legacy: Dictionary = GameBootstrap.catalog().catalog.to_dict()
	var p3: Dictionary = P3Content.catalog().catalog.to_dict()
	check(legacy != p3 and legacy == GameBootstrap.catalog().catalog.to_dict(),"separate metadata leaves legacy catalog unchanged")
	check(p3.targets == [1,2,3,4] and p3.weights == [4,3,2,1],"P3 retains supply")
	var quartz := merge(fixture())
	check(quartz.raw_bonus == 1 and quartz.uses.quartz and quartz.state.room.craft == 2,"Quartz three-match earns one bonus")
	quartz.best_craft = 2; quartz.state.room.craft = 5; quartz.settle_increment()
	check(quartz.entitlement == 3 and quartz.state.room.craft == 6,"shared cap consumes capacity-clipped entitlement")
	quartz.state.room.craft = 0; quartz.settle_increment()
	check(quartz.state.room.craft == 0,"clipped entitlement cannot return after spending")
	var source: Dictionary = quartz.facts.filter(func(f: Dictionary) -> bool: return f.type == "match_committed")[0]
	FamilyDispatcher.dispatch(quartz,[source,source])
	check(quartz.raw_bonus == 1,"Quartz once across multiple automatic components")
	var changed := merge(fixture(2))
	check(changed.raw_bonus == 1 and changed.state.board.get_tile(Vector2i(2,3)).family_tags.is_empty(),"frozen Amethyst Quartz family survives promotion to Peridot")
	var corundum_state := fixture(5)
	# One obstacle touches two members of this one component.
	corundum_state.board.set_tile(Vector2i(0,1),corundum_state.catalog.create_tile(5))
	corundum_state.board.set_tile(Vector2i(1,1),corundum_state.catalog.create_tile(5))
	corundum_state.board.remove_tile(Vector2i(1,2))
	corundum_state.board.obstacles["rubble/contact"] = {"id":"rubble/contact","cell":Vector2i(1,2),"kind":"rubble","durability":2}
	var corundum := merge(corundum_state)
	check(not corundum_state.board.obstacles.has("rubble/contact"),"Corundum replaces base damage with two")
	check(count(corundum,"obstacle_damaged") == 1 and count(corundum,"obstacle_broken") == 1,"component damage and break deduplicated")
	var beryl := merge(fixture(6))
	check(beryl.uses.get("beryl",false) and beryl.state.board.get_tile(Vector2i(2,4)).tier == 3,"Beryl chooses lowest eligible live neighbor")
	var chain_state := fixture(6)
	chain_state.board.set_tile(Vector2i(1,4),chain_state.catalog.create_tile(3))
	chain_state.board.set_tile(Vector2i(3,4),chain_state.catalog.create_tile(3))
	var chain := merge(chain_state)
	check(not MatchDetector.new().find_matches(chain.state.board).is_empty(),"Beryl creates pending match without resolving it before the window")
	var stale := {"reaction_id":"beryl","source_event_id":beryl.root,"scope":"move","target":{"cell":Vector2i(1,3),"target_id":"piece/stale","tier":3}}
	beryl.uses.erase("beryl"); FamilyDispatcher.apply(beryl,stale)
	check(not beryl.uses.has("beryl"),"stale target does not spend use")
	var target_source := {"survivor":Vector2i(2,3),"survivor_id":beryl.state.board.get_tile(Vector2i(2,3)).instance_id}
	for cell in [Vector2i(2,2),Vector2i(1,3),Vector2i(3,3),Vector2i(2,4)]:
		beryl.state.board.set_tile(cell,beryl.state.catalog.create_tile(1))
	check(FamilyDispatcher.target(beryl,target_source).cell == Vector2i(2,2),"Beryl equal tiers select minimum y then x")
	beryl.state.board.remove_tile(Vector2i(2,2))
	check(FamilyDispatcher.target(beryl,target_source).cell == Vector2i(1,3),"Beryl same-row tie selects minimum x")
	for cell in [Vector2i(1,3),Vector2i(3,3),Vector2i(2,4)]: beryl.state.board.set_tile(cell,beryl.state.catalog.create_tile(4))
	check(FamilyDispatcher.target(beryl,target_source).is_empty(),"Beryl excludes T4 without Bridge")
	FamilyDispatcher.apply(beryl,{"reaction_id":"beryl","source_event_id":beryl.root,"scope":"move","target":{}})
	check(not beryl.uses.has("beryl"),"no target preserves Beryl use")
	for family in ["quartz","corundum","beryl"]:
		var terminal := merge(fixture(8,family))
		check(terminal.raw_bonus == (1 if family == "quartz" else 0),"T8 frozen eligibility: "+family)
		check(not terminal.uses.has("beryl"),"T8 has no Beryl survivor")
		var suppressed := merge(fixture(1,family),true)
		check(suppressed.raw_bonus == 0 and not suppressed.uses.has(family),"suppressed family: "+family)
	var session := MergeSession.new(); check(session.start(fixture().to_dict()),"P3 session starts")
	check(session.apply(InterventionFixture.command(session.state)).ok,"published first batch")
	session.presented(); session.tick(20)
	var before := CanonicalCodec.encode(session.snapshot())
	check(not session.prepare(null,"after_family").ok,"failure after family rejects unpublished batch")
	check(CanonicalCodec.encode(session.snapshot()) == before,"failure retains committed prefix/RNG/allocators/history")
	check(session.apply().ok,"same continuation succeeds without injected failure")
	check(MergeReplay.restored(session.snapshot(),false).ok,"complete family replay and restore")
	var capped := fixture(); var rules := capped.rules.to_dict(); rules.max_reactions = 0
	capped.rules = RuleSet.admit(rules).rules
	var limited := MergeSession.new(); check(limited.start(capped.to_dict()),"bounded reaction profile admits")
	var initial_bytes := CanonicalCodec.encode(limited.snapshot())
	check(limited.prepare(InterventionFixture.command(limited.state)).get("code") == "reaction_cap","reaction cap fails explicitly")
	check(CanonicalCodec.encode(limited.snapshot()) == initial_bytes,"reaction cap rolls back all unpublished effects")
	var intervened := MergeSession.new(); check(intervened.start(fixture().to_dict()),"intervention family fixture")
	check(intervened.apply(InterventionFixture.command(intervened.state)).ok,"first paid Quartz use")
	intervened.presented()
	var legal := ActionLegality.enumerate_legal_swaps(intervened.state.board)
	check(not legal.is_empty(),"intervention witness has a legal swap")
	if not legal.is_empty():
		check(intervened.apply(RoomCommand.exchange(intervened.state,legal[0].origin,legal[0].destination)).ok,"paid intervention before pending automatic match")
		check(intervened.context.classification == "intervention" and intervened.move_id == 3,"intervention gets fresh family scope")
		check(MergeReplay.restored(intervened.snapshot(),false).ok,"intervention family replay")
	for seed_value in [1,7,8]:
		var opened := P3Content.room(seed_value); check(opened.ok,"P3 opening")
		var run := MergeSession.new(); check(run.start(opened.state.to_dict()),"generated family room admission")
		for index in 12:
			if run.phase in ["complete","failed"]: break
			var result: Dictionary
			if run.phase == "ready":
				var moves := ActionLegality.enumerate_legal_swaps(run.state.board)
				if moves.is_empty(): break
				result = run.apply(RoomCommand.exchange(run.state,moves[0].origin,moves[0].destination))
			else:
				if run.phase == "merge_window": run.presented(); run.tick(20)
				result = run.apply()
			check(result.ok,"deterministic generated batch")
			if not result.ok: break
		check(MergeReplay.restored(run.snapshot(),false).ok,"generated complete checkpoint replay")
	finish("test_p3_families")
