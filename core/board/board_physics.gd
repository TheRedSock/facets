class_name BoardPhysics
extends RefCounted

## Maximum settling rounds to prevent infinite loops from cyclic gravity configurations.
const MAX_SETTLE_ROUNDS := 256

## Per-tile movement events from the last gravity resolution.
## Each entry: { type: "tile_moved", from: Vector2i, to: Vector2i, tile_id: StringName, tier: int }
## Consumed by the EventTimeline for animation sequencing.
var last_move_events: Array[Dictionary] = []


## Resolves gravity on the board using iterative settling.
## Each round, every tile tries to move one cell in its gravity direction.
## After primary gravity, diagonal fill is attempted on eligible cells.
## Rounds repeat until no tile moves (board is stable).
## Returns the total number of tiles that moved.
func resolve_gravity(board: BoardState) -> int:
	last_move_events.clear()
	var total_moves := 0
	var settle_order := _settle_order(board)

	for round_idx in MAX_SETTLE_ROUNDS:
		var moved_this_round := 0

		# --- Primary gravity pass ---
		for cell in settle_order:
			moved_this_round += _try_primary_move(board, cell)

		# --- Diagonal fill pass ---
		for cell in settle_order:
			moved_this_round += _try_diagonal_fill(board, cell)

		total_moves += moved_this_round
		if moved_this_round == 0:
			break

	return total_moves


## Attempts to move a single tile one cell in its effective gravity direction.
## Returns 1 if the tile moved, 0 otherwise.
func _try_primary_move(board: BoardState, cell: Vector2i) -> int:
	var tile: TileState = board.get_tile(cell)
	if tile == null or tile.immovable:
		return 0

	var gravity: Vector2i = board.get_effective_gravity(cell)
	if gravity == Vector2i.ZERO:
		return 0  # No gravity on this cell (e.g., "floating" modifier)

	var target: Vector2i = board.get_neighbor(cell, gravity)
	if target == Vector2i(-1, -1):
		return 0  # Out of bounds / no neighbor
	if board.is_blocked(target) or board.get_tile(target) != null:
		return 0  # Target occupied or blocked

	board.move_tile(cell, target)
	last_move_events.append({
		"type": &"tile_moved",
		"from": cell,
		"to": target,
		"tile_id": tile.tile_id,
		"tier": tile.tier,
	})
	return 1


## Attempts to fill an empty cell from a diagonal source.
## Only triggers on cells with fill_sources configured (opt-in per cell).
## Checks each source direction in order; the first valid source wins (deterministic).
## Returns 1 if a tile was moved in, 0 otherwise.
func _try_diagonal_fill(board: BoardState, cell: Vector2i) -> int:
	if board.get_tile(cell) != null:
		return 0  # Cell already occupied
	var cs: CellState = board.get_cell(cell)
	if cs == null or cs.blocked or cs.fill_sources.is_empty():
		return 0  # No diagonal fill on this cell

	for source_dir in cs.fill_sources:
		var source: Vector2i = board.get_neighbor(cell, source_dir)
		if source == Vector2i(-1, -1):
			continue
		var source_tile: TileState = board.get_tile(source)
		if source_tile == null or source_tile.immovable:
			continue

		board.move_tile(source, cell)
		last_move_events.append({
			"type": &"tile_moved",
			"from": source,
			"to": cell,
			"tile_id": source_tile.tile_id,
			"tier": source_tile.tier,
		})
		return 1  # First valid source wins

	return 0


## Returns cells in deterministic processing order: bottom-to-top, right-to-left.
## This gives downward gravity natural priority (bottom tiles settle first,
## creating space for tiles above). Within a row, rightward gravity gets
## slight priority via right-to-left processing.
func _settle_order(board: BoardState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(board.size.y - 1, -1, -1):
		for x in range(board.size.x - 1, -1, -1):
			var pos := Vector2i(x, y)
			if not board.is_blocked(pos):
				cells.append(pos)
	return cells


## Returns all empty, non-blocked cells that are eligible for tile spawning.
## If any cells are marked as spawn entries, only those are returned.
## Otherwise, falls back to all empty cells (standard match-3 behavior).
func find_spawn_eligible_cells(board: BoardState) -> Array[Vector2i]:
	var spawn_empties: Array[Vector2i] = []
	var all_empties: Array[Vector2i] = []
	for y in board.size.y:
		for x in board.size.x:
			var pos := Vector2i(x, y)
			var cs: CellState = board.get_cell(pos)
			if cs == null or cs.blocked or cs.tile != null:
				continue
			all_empties.append(pos)
			if cs.is_spawn_entry:
				spawn_empties.append(pos)
	# If no spawn entries are configured, fall back to all empties
	return spawn_empties if not spawn_empties.is_empty() else all_empties
