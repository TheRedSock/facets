class_name BoardSettler
extends RefCounted

static func resolve(board: BoardState, rng: SeededRng, supply: SpawnTableResource, spawner: SpawnResolver, budget: ResolutionBudget = null, cause: String = "setup") -> Dictionary:
	if budget == null: budget = ResolutionBudget.new()
	var steps: Array = []
	var physics := BoardPhysics.new()
	while budget.error.is_empty():
		var result := physics.settle(board, budget)
		if not result.ok: return {"ok": false, "code": result.code, "steps": []}
		var moves := physics.last_move_events.duplicate(true)
		var cells := physics.find_spawn_eligible_cells(board)
		if not budget.spend(board.size.x * board.size.y, cells.size()): break
		var count := spawner.refill_spawn_entries(board, rng, supply, cells)
		if count < 0: return {"ok": false, "code": spawner.last_error, "steps": []}
		if not moves.is_empty() or count > 0:
			var spawned := spawner.last_spawn_events.duplicate(true)
			for event in moves + spawned:
				event.cause = cause; event.reward_eligible = cause != "setup"
			steps.append({"gravity_events": moves, "spawn_events": spawned})
		if count == 0: return {"ok": true, "code": "", "steps": steps}
	return {"ok": false, "code": budget.error, "steps": []}
