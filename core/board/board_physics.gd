class_name BoardPhysics
extends RefCounted
const MAX_SETTLE_ROUNDS := 256
var last_move_events: Array[Dictionary] = []
var last_result: Dictionary = {}

## Compatibility adapter: -1 is an explicit failure; inspect last_result.
func resolve_gravity(board: BoardState) -> int:
	last_result = settle(board)
	return last_result.moves if last_result.ok else -1

func settle(board: BoardState, budget: ResolutionBudget = null) -> Dictionary:
	if budget == null: budget = ResolutionBudget.new()
	last_move_events.clear()
	var order := _settle_order(board)
	var seen := {}
	var rounds := 0
	while true:
		if not budget.spend(order.size()): return _failed(budget.error)
		var signature: Array = []
		for pos in order:
			var tile := board.get_tile(pos)
			signature.append(tile.instance_id if tile != null else "")
		var key := str(signature)
		if seen.has(key): return _failed("physical_cycle")
		seen[key] = true
		if rounds >= int(budget.rules.value("max_settle")):
			if _has_move(board, order): return _failed("settle_cap")
			return {"ok": true, "code": "", "moves": last_move_events.size(), "rounds": rounds}
		var before := last_move_events.size()
		for pos in order:
			if not budget.spend(1): return _failed(budget.error)
			var target := _primary_target(board, pos)
			if target != Vector2i(-1,-1):
				if not budget.spend(0, 1): return _failed(budget.error)
				_move(board, pos, target, "portal" if board.has_portal(pos, board.get_effective_gravity(pos)) else "gravity", rounds)
		for pos in order:
			if not budget.spend(1): return _failed(budget.error)
			var source := _fill_source(board, pos)
			if source != Vector2i(-1,-1):
				if not budget.spend(0, 1): return _failed(budget.error)
				_move(board, source, pos, "fill", rounds)
		rounds += 1
		if last_move_events.size() == before: return {"ok": true, "code": "", "moves": last_move_events.size(), "rounds": rounds}
	return _failed("unreachable")

func _failed(code: String) -> Dictionary:
	return {"ok": false, "code": code, "moves": last_move_events.size()}

func _primary_target(board: BoardState, pos: Vector2i) -> Vector2i:
	var cell := board.get_cell(pos)
	if cell == null or cell.blocked or cell.tile == null or cell.tile.immovable or not cell.lock.is_empty(): return Vector2i(-1,-1)
	var direction := cell.tile.gravity_override
	if direction == Vector2i.ZERO: direction = cell.gravity_direction
	if direction == Vector2i.ZERO: direction = Vector2i.DOWN
	var target := board.get_neighbor(pos,direction)
	var destination := board.get_cell(target)
	return target if destination != null and board.can_enter(target) else Vector2i(-1,-1)

func _fill_source(board: BoardState, pos: Vector2i) -> Vector2i:
	var cell := board.get_cell(pos)
	if cell == null or not board.can_enter(pos): return Vector2i(-1,-1)
	for direction in cell.fill_sources:
		var source := board.neighbor_for(pos, direction, "fill")
		if source != Vector2i(-1,-1) and board.can_move_occupant(source): return source
	return Vector2i(-1,-1)

func _has_move(board: BoardState, order: Array[Vector2i]) -> bool:
	for pos in order:
		if _primary_target(board,pos) != Vector2i(-1,-1) or _fill_source(board,pos) != Vector2i(-1,-1): return true
	return false

func _move(board: BoardState, from: Vector2i, to: Vector2i, kind: String, round_index: int) -> void:
	var tile := board.get_tile(from)
	if not board.move_tile(from,to): return
	last_move_events.append({"type": &"tile_moved", "from": from, "to": to, "tile_id": tile.tile_id, "tier": tile.tier,
		"instance_id": tile.instance_id, "kind": kind, "round": round_index, "sequence": last_move_events.size()})

func _settle_order(board: BoardState) -> Array[Vector2i]:
	var cells := board.all_cells()
	cells.reverse()
	return cells

func find_spawn_eligible_cells(board: BoardState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pos in board.all_cells():
		if not board.can_enter(pos): continue
		if board.spawn_policy == "fill_empty_cells" or (board.spawn_policy == "entry_only" and board.get_cell(pos).is_spawn_entry): cells.append(pos)
	return cells
