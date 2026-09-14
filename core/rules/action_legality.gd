class_name ActionLegality
extends RefCounted

static func can_apply(board: BoardState, command: SwapCommand, budget: int = 1, phase: String = "ready") -> Dictionary:
	var code := ""
	if board == null or command == null: code = "invalid_command"
	elif phase != "ready": code = "invalid_phase"
	elif budget <= 0: code = "budget_exhausted"
	elif not board.in_bounds(command.origin) or not board.in_bounds(command.destination): code = "out_of_bounds"
	elif command.origin == command.destination: code = "same_cell"
	elif board.neighbor_for(command.origin, command.destination - command.origin, "swap") != command.destination: code = "not_adjacent"
	elif board.get_tile(command.origin) == null or board.get_tile(command.destination) == null: code = "empty_cell"
	elif not board.can_move_occupant(command.origin) or not board.can_move_occupant(command.destination): code = "movement_locked"
	if not code.is_empty(): return {"ok": false, "code": code}
	if board.get_tile(command.origin).get_match_group() == board.get_tile(command.destination).get_match_group(): return {"ok": false, "code": "no_new_match"}
	var relevant := _matched_after_swap(board, command.origin, command) or _matched_after_swap(board, command.destination, command)
	return {"ok": relevant, "code": "" if relevant else "no_new_match"}

# Virtual occupancy keeps the query pure and examines only lines changed by the swap.
static func _matched_after_swap(board: BoardState, center: Vector2i, command: SwapCommand) -> bool:
	var tile := _virtual_tile(board, center, command)
	if tile == null or tile.unmatchable: return false
	for axis in [Vector2i.RIGHT, Vector2i.DOWN]:
		var count := 1
		for direction in [axis, -axis]:
			var cursor := board.neighbor_for(center, direction, "match")
			while cursor != Vector2i(-1,-1):
				var other := _virtual_tile(board, cursor, command)
				if other == null or other.unmatchable or other.get_match_group() != tile.get_match_group(): break
				count += 1
				cursor = board.neighbor_for(cursor, direction, "match")
		if count >= 3: return true
	return false

static func _virtual_tile(board: BoardState, pos: Vector2i, command: SwapCommand) -> TileState:
	if pos == command.origin: return board.get_tile(command.destination)
	if pos == command.destination: return board.get_tile(command.origin)
	return board.get_tile(pos)

static func has_legal_swap(board: BoardState) -> bool:
	for cell in board.all_cells():
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			if can_apply(board, SwapCommand.new(cell, cell + direction)).ok: return true
	return false

static func enumerate_legal_swaps(board: BoardState, budget: int = 1, phase: String = "ready") -> Array[SwapCommand]:
	var result: Array[SwapCommand] = []
	if board == null or budget <= 0 or phase != "ready": return result
	for cell in board.all_cells():
		var neighbors: Array[Vector2i] = []
		for direction in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor := board.neighbor_for(cell, direction, "swap")
			if neighbor != Vector2i(-1, -1): neighbors.append(neighbor)
		neighbors.sort_custom(MatchClassifier.cell_less)
		for neighbor in neighbors:
			var command := SwapCommand.new(cell, neighbor)
			if can_apply(board, command, budget, phase).ok: result.append(command)
	return result
