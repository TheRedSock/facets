class_name MergeKernel
extends RefCounted
## One deterministic batch. The caller owns candidate rollback and publication.

static func resolve_match(context: MergeMoveContext, cursor: Dictionary, pair: Array[Vector2i], fail_at: String = "") -> Dictionary:
	var board := context.state.board
	var budget := context.budget
	if not budget.spend(board.size.x * board.size.y * 2): return StateAdmission.fail(budget.error)
	var matches := MatchClassifier.new().classify(MatchDetector.new().find_matches(board))
	if matches.is_empty(): return {"ok":true,"matched":false}
	if cursor.cascade >= int(context.state.rules.value("max_cascades")): return StateAdmission.fail("cascade_cap")
	if cursor.chain > int(context.state.rules.value("max_chains")): return StateAdmission.fail("chain_cap")
	var match_events: Array[Dictionary] = []
	for component in matches:
		var sources: Array = []
		for pos in component.cells: sources.append({"cell":pos,"tile":board.get_tile(pos).to_dict()})
		var survivor: Variant = MatchClassifier.survivor(component.cells,pair) if component.tier < 8 else null
		var fact: Dictionary = component.duplicate(true)
		fact.merge({"type":&"match_formed","sources":sources,"survivor":survivor,
			"survivor_id":board.get_tile(survivor).instance_id if survivor != null else "",
			"obstacle_targets":board.obstacle_neighbors(component.cells)})
		match_events.append(fact)
	var plan := ConflictResolver.new().resolve(EffectPlanner.new().build_base_plan(matches,pair),board)
	if not budget.spend(plan.size(),matches.size()+plan.size()*2): return StateAdmission.fail(budget.error)
	var effects := EffectResolver.new(context.state.catalog)
	if effects.apply(board,plan,EventLog.new()) < 0: return StateAdmission.fail(effects.last_error)
	if fail_at == "after_promotion": return StateAdmission.fail("injected_after_promotion")
	context.match_step({"cascade_index":cursor.cascade,"chain_index":cursor.chain,"match_events":match_events,
		"remove_events":effects.last_remove_events,"upgrade_events":effects.last_upgrade_events})
	if fail_at == "after_obstacle": return StateAdmission.fail("injected_after_obstacle")
	if not budget.error.is_empty(): return StateAdmission.fail(budget.error)
	cursor.chain += 1
	context.settle_increment()
	return {"ok":budget.error.is_empty(),"code":budget.error,"matched":true}

static func resolve_gravity(context: MergeMoveContext, cursor: Dictionary, fail_at: String = "") -> Dictionary:
	context._journeys.clear()
	var state := context.state
	var result := BoardSettler.resolve(state.board,state.streams.stream("board"),state.catalog.supply(),
		SpawnResolver.new(state.catalog),context.budget,context.cause)
	if not result.ok: return result
	if fail_at == "after_spawn": return StateAdmission.fail("injected_after_spawn")
	for physical in result.steps: context.physical_step(physical)
	# Journey aggregation is private to this gravity packet, never across publish.
	context._journeys.clear()
	cursor.cascade += 1; cursor.chain = 0
	return {"ok":context.budget.error.is_empty(),"code":context.budget.error,"moved":not result.steps.is_empty()}
