class_name OpeningGenerator
extends RefCounted

## Setup uses bounded rejection of local three-runs. Normal refill is unchanged.
static func generate(layout: BoardLayoutResource, catalog: GameCatalog, streams: RngStreamBank, rules: RuleSet = null, initial: BoardState = null) -> Dictionary:
	if rules == null: rules = RuleSet.new()
	var admitted := LayoutAdmission.admit(layout)
	if not admitted.ok: return {"ok": false, "code": "invalid_layout", "issues": admitted.issues}
	if catalog == null: return {"ok": false, "code": "missing_catalog"}
	var restored := RngStreamBank.restored(streams.capture())
	var candidate_streams: RngStreamBank = restored.bank
	var spawner := SpawnResolver.new(catalog)
	var supply := catalog.supply()
	var budget := ResolutionBudget.new(rules)
	if rules.is_p3() and initial != null:
		var checked := StateAdmission.board(initial.to_dict(),catalog)
		if not checked.ok: return checked
	var next_instance := initial.next_instance if initial != null else 1
	for attempt in int(rules.value("max_openings")):
		var board := BoardState.new()
		board.apply_topology(admitted.topology)
		if initial != null:
			board.room_board = initial.room_board
			board.obstacles = initial.obstacles.duplicate(true)
			if rules.is_p3():
				board = initial.duplicate_board()
				board.next_instance = next_instance
		var failed := false
		for pos in board.all_cells():
			if not board.can_enter(pos): continue
			if rules.is_p3() and board.get_tile(pos) != null: continue
			var chosen: TileState = null
			for draw in 64:
				if not budget.spend(1): return {"ok": false, "code": budget.error}
				var tile := spawner._spawn_tile(candidate_streams.stream("board"), supply)
				if not makes_backward_line(board, pos, tile): chosen = tile; break
			if chosen == null: failed = true; break
			board.set_tile(pos, chosen)
		next_instance = board.next_instance
		if failed: continue
		var physical := BoardPhysics.new().settle(board, budget)
		if not physical.ok: return {"ok": false, "code": physical.code}
		if rules.is_p3() and initial != null:
			for pos in initial.all_cells():
				if initial.get_tile(pos) != null and (board.get_tile(pos) == null or board.get_tile(pos).to_dict() != initial.get_tile(pos).to_dict()): failed = true
			if failed: continue
		if not MatchDetector.new().find_matches(board).is_empty(): continue
		if not ActionLegality.has_legal_swap(board): continue
		return {"ok": true, "board": board, "streams": candidate_streams, "attempts": attempt + 1, "work": budget.work}
	return {"ok": false, "code": "opening_exhausted", "attempts": int(rules.value("max_openings"))}

static func makes_backward_line(board: BoardState, pos: Vector2i, tile: TileState) -> bool:
	for direction in [Vector2i.LEFT, Vector2i.UP]:
		var one := board.neighbor_for(pos, direction, "match")
		var two := board.neighbor_for(one, direction, "match")
		var a := board.get_tile(one)
		var b := board.get_tile(two)
		if a != null and b != null and a.get_match_group() == tile.get_match_group() and b.get_match_group() == tile.get_match_group(): return true
	return false
