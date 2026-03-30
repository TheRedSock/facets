class_name BoardValidator
extends RefCounted

## Validates a BoardLayoutResource and returns an array of issue strings.
## Each issue is prefixed with [ERROR] or [WARNING] to indicate severity.
## Errors indicate configurations that will break the engine.
## Warnings indicate configurations that may produce unexpected behavior.


func validate(layout: BoardLayoutResource) -> Array[String]:
	var issues: Array[String] = []
	var board := BoardState.new()
	board.apply_layout(layout)

	_check_gravity_cycles(board, issues)
	_check_reachability(board, layout, issues)
	_check_orphaned_spawn_entries(board, issues)
	_check_contention_zones(board, issues)
	_check_portal_targets(board, layout, issues)

	return issues


## Checks for gravity cycles — following gravity from a cell leads back to itself.
## A cycle means tiles would orbit forever; the engine's MAX_SETTLE_ROUNDS prevents
## hanging but the board would never stabilize.
func _check_gravity_cycles(board: BoardState, issues: Array[String]) -> void:
	var max_steps := board.size.x * board.size.y

	for pos in board.all_cells():
		var visited: Dictionary = {}
		var cursor := pos
		var steps := 0

		while cursor != Vector2i(-1, -1):
			if visited.has(cursor):
				issues.append("[ERROR] Gravity cycle detected: cell (%d,%d) eventually loops back to (%d,%d)" % [
					pos.x, pos.y, cursor.x, cursor.y])
				break
			if steps >= max_steps:
				issues.append("[ERROR] Gravity path from (%d,%d) exceeds max length — possible unbounded path" % [
					pos.x, pos.y])
				break
			visited[cursor] = true
			var gravity: Vector2i = board.get_effective_gravity(cursor)
			if gravity == Vector2i.ZERO:
				break  # No gravity — tile rests here
			cursor = board.get_neighbor(cursor, gravity)
			steps += 1


## Checks whether every non-blocked cell can be reached from at least one spawn entry.
## Unreachable cells can only be filled by special effects, which may be intentional
## but should be flagged for designer awareness.
func _check_reachability(board: BoardState, layout: BoardLayoutResource, issues: Array[String]) -> void:
	# Determine spawn entries: explicit or fallback (top row for standard boards)
	var spawn_cells: Array[Vector2i] = []
	if not layout.spawn_entries.is_empty():
		spawn_cells = layout.spawn_entries
	else:
		# Fallback: consider all cells as potential spawn sources (standard behavior)
		return  # Can't check reachability without explicit spawn entries

	# For each spawn entry, trace gravity forward to find all reachable cells
	var reachable: Dictionary = {}  # Vector2i -> true
	var max_steps := board.size.x * board.size.y

	for entry in spawn_cells:
		var cursor := entry
		var steps := 0
		while cursor != Vector2i(-1, -1) and steps < max_steps:
			if reachable.has(cursor):
				break  # Already explored from another entry
			reachable[cursor] = true
			var gravity: Vector2i = board.get_effective_gravity(cursor)
			if gravity == Vector2i.ZERO:
				break
			cursor = board.get_neighbor(cursor, gravity)
			steps += 1

	# Check which cells are unreachable
	for pos in board.all_cells():
		if not reachable.has(pos):
			issues.append("[WARNING] Cell (%d,%d) is not reachable from any spawn entry — requires special effects to fill" % [
				pos.x, pos.y])


## Checks for spawn entries that are blocked or outside the board.
func _check_orphaned_spawn_entries(board: BoardState, issues: Array[String]) -> void:
	for pos in board.all_cells():
		var cs: CellState = board.get_cell(pos)
		if cs != null and cs.is_spawn_entry:
			if cs.blocked:
				issues.append("[ERROR] Spawn entry at (%d,%d) is on a blocked cell" % [
					pos.x, pos.y])


## Checks for cells where multiple gravity lanes converge.
## Not an error, but designer should be aware of contention.
func _check_contention_zones(board: BoardState, issues: Array[String]) -> void:
	var incoming_count: Dictionary = {}  # Vector2i -> int

	for pos in board.all_cells():
		var gravity: Vector2i = board.get_effective_gravity(pos)
		if gravity == Vector2i.ZERO:
			continue
		var target: Vector2i = board.get_neighbor(pos, gravity)
		if target == Vector2i(-1, -1):
			continue
		incoming_count[target] = incoming_count.get(target, 0) + 1

	# Also count diagonal fill sources
	for pos in board.all_cells():
		var cs: CellState = board.get_cell(pos)
		if cs == null or cs.fill_sources.is_empty():
			continue
		for source_dir in cs.fill_sources:
			var source: Vector2i = board.get_neighbor(pos, source_dir)
			if source != Vector2i(-1, -1):
				incoming_count[pos] = incoming_count.get(pos, 0) + 1

	for cell in incoming_count:
		if incoming_count[cell] > 1:
			issues.append("[WARNING] Cell (%d,%d) has %d incoming gravity/fill paths — processing order determines which tile arrives first" % [
				cell.x, cell.y, incoming_count[cell]])


## Checks that portal targets are valid (in bounds, not blocked).
func _check_portal_targets(board: BoardState, layout: BoardLayoutResource, issues: Array[String]) -> void:
	for portal in layout.portals:
		var from: Vector2i = portal.get("from", Vector2i(-1, -1))
		var to: Vector2i = portal.get("to", Vector2i(-1, -1))
		var dir: Vector2i = portal.get("direction", Vector2i.ZERO)

		if not board.in_bounds(from):
			issues.append("[ERROR] Portal source (%d,%d) is out of bounds" % [from.x, from.y])
		if not board.in_bounds(to):
			issues.append("[ERROR] Portal target (%d,%d) is out of bounds" % [to.x, to.y])
		elif board.is_blocked(to):
			issues.append("[ERROR] Portal target (%d,%d) is a blocked cell" % [to.x, to.y])
		if dir == Vector2i.ZERO:
			issues.append("[ERROR] Portal from (%d,%d) has zero direction" % [from.x, from.y])
