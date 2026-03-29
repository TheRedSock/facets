class_name BoardState
extends RefCounted

var size: Vector2i = Vector2i.ZERO
var _cells: Array = []

## Portal connections: "x,y,dx,dy" -> Vector2i target cell.
## When get_neighbor() is called for a cell+direction that has a portal entry,
## the portal target is returned instead of the normal grid neighbor.
var _portals: Dictionary = {}


func _init(board_size: Vector2i = Vector2i.ZERO) -> void:
	if board_size != Vector2i.ZERO:
		resize(board_size)


func resize(board_size: Vector2i) -> void:
	size = board_size
	_cells.resize(size.x * size.y)
	for index in _cells.size():
		_cells[index] = CellState.open()


func clear() -> void:
	for index in _cells.size():
		_cells[index].tile = null


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func index_for(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


## Returns the CellState at the given position, or null if out of bounds.
func get_cell(cell: Vector2i) -> CellState:
	if not in_bounds(cell):
		return null
	return _cells[index_for(cell)]


## Returns the TileState at the given position, or null if empty/blocked/out of bounds.
func get_tile(cell: Vector2i) -> TileState:
	var cell_state: CellState = get_cell(cell)
	if cell_state == null:
		return null
	return cell_state.tile


## Sets the tile at the given position. Does nothing if out of bounds or cell is blocked.
func set_tile(cell: Vector2i, tile: TileState) -> void:
	var cell_state: CellState = get_cell(cell)
	if cell_state == null or cell_state.blocked:
		return
	cell_state.tile = tile


## Removes the tile at the given position. Returns the removed tile or null.
func remove_tile(cell: Vector2i) -> TileState:
	var cell_state: CellState = get_cell(cell)
	if cell_state == null:
		return null
	var removed := cell_state.tile
	cell_state.tile = null
	return removed


## Marks a cell as blocked (hole). Removes any tile in it.
func set_blocked(cell: Vector2i, blocked: bool) -> void:
	var cell_state: CellState = get_cell(cell)
	if cell_state == null:
		return
	cell_state.blocked = blocked
	if blocked:
		cell_state.tile = null


## Returns true if the cell is blocked (hole, wall, etc.).
func is_blocked(cell: Vector2i) -> bool:
	var cell_state: CellState = get_cell(cell)
	if cell_state == null:
		return true
	return cell_state.blocked


## Swaps the tiles in two cells. Rejects swaps involving blocked or immovable tiles.
func swap_cells(a: Vector2i, b: Vector2i) -> void:
	if not in_bounds(a) or not in_bounds(b):
		return
	var cell_a: CellState = get_cell(a)
	var cell_b: CellState = get_cell(b)
	if cell_a.blocked or cell_b.blocked:
		return
	if (cell_a.tile != null and cell_a.tile.immovable) or \
	   (cell_b.tile != null and cell_b.tile.immovable):
		return
	var temp := cell_a.tile
	cell_a.tile = cell_b.tile
	cell_b.tile = temp


## Moves a tile from one cell to another. Target must be empty and non-blocked.
## Returns true if the move succeeded.
func move_tile(from: Vector2i, to: Vector2i) -> bool:
	var from_cell: CellState = get_cell(from)
	if from_cell == null or from_cell.tile == null:
		return false
	var to_cell: CellState = get_cell(to)
	if to_cell == null or to_cell.blocked or to_cell.tile != null:
		return false
	to_cell.tile = from_cell.tile
	from_cell.tile = null
	return true


# ---- Topology Methods ----


## Returns the neighbor of a cell in the given direction, respecting portal overrides.
## Returns Vector2i(-1, -1) if the neighbor is out of bounds or doesn't exist.
func get_neighbor(cell: Vector2i, direction: Vector2i) -> Vector2i:
	var key := _portal_key(cell, direction)
	if _portals.has(key):
		return _portals[key]
	var neighbor := cell + direction
	if in_bounds(neighbor):
		return neighbor
	return Vector2i(-1, -1)


## Returns the effective gravity direction for a cell, considering tile overrides.
## Tile gravity_override (if non-zero) takes priority over cell gravity_direction.
func get_effective_gravity(cell: Vector2i) -> Vector2i:
	var tile := get_tile(cell)
	if tile != null and tile.gravity_override != Vector2i.ZERO:
		return tile.gravity_override
	var cs: CellState = get_cell(cell)
	if cs == null:
		return Vector2i.DOWN
	return cs.gravity_direction


## Adds a portal connection. Gravity/movement from `from` in `direction` arrives at `to`.
func add_portal(from: Vector2i, direction: Vector2i, to: Vector2i) -> void:
	_portals[_portal_key(from, direction)] = to


## Removes a portal connection.
func remove_portal(from: Vector2i, direction: Vector2i) -> void:
	_portals.erase(_portal_key(from, direction))


## Returns true if a portal exists for the given cell and direction.
func has_portal(from: Vector2i, direction: Vector2i) -> bool:
	return _portals.has(_portal_key(from, direction))


## Applies a BoardLayoutResource to configure this board's topology.
## Resizes the board, sets blocked cells, gravity directions, spawn entries,
## fill sources, and portal connections.
func apply_layout(layout: BoardLayoutResource) -> void:
	resize(layout.board_size)

	# Apply blocked cells
	for cell_pos in layout.blocked_cells:
		set_blocked(cell_pos, true)

	# Apply gravity overrides
	for key in layout.gravity_overrides:
		var pos := BoardLayoutResource._parse_cell_key(key)
		var cs: CellState = get_cell(pos)
		if cs != null:
			cs.gravity_direction = layout.gravity_overrides[key]

	# Apply spawn entries
	for cell_pos in layout.spawn_entries:
		var cs: CellState = get_cell(cell_pos)
		if cs != null:
			cs.is_spawn_entry = true

	# Apply fill source overrides
	for key in layout.fill_source_overrides:
		var pos := BoardLayoutResource._parse_cell_key(key)
		var cs: CellState = get_cell(pos)
		if cs != null:
			cs.fill_sources = layout.fill_source_overrides[key]

	# Apply portal connections
	_portals.clear()
	for portal in layout.portals:
		var from: Vector2i = portal["from"]
		var dir: Vector2i = portal["direction"]
		var to: Vector2i = portal["to"]
		add_portal(from, dir, to)


# ---- State Hashing ----


## Computes a deterministic hash of the complete board state.
## Used for replay verification and anti-cheat checkpoints.
## Two boards with identical cell/tile configurations produce identical hashes.
func compute_hash() -> int:
	var hash_val := 17
	for y in size.y:
		for x in size.x:
			var pos := Vector2i(x, y)
			var cs: CellState = get_cell(pos)
			hash_val = hash_val * 31 + (1 if cs.blocked else 0)
			hash_val = hash_val * 31 + cs.gravity_direction.x
			hash_val = hash_val * 31 + cs.gravity_direction.y
			if cs.tile != null:
				hash_val = hash_val * 31 + cs.tile.tile_id.hash()
				hash_val = hash_val * 31 + cs.tile.tier
				hash_val = hash_val * 31 + (1 if cs.tile.protected else 0)
				hash_val = hash_val * 31 + (1 if cs.tile.immovable else 0)
				hash_val = hash_val * 31 + (1 if cs.tile.unmatchable else 0)
				hash_val = hash_val * 31 + cs.tile.gravity_override.x
				hash_val = hash_val * 31 + cs.tile.gravity_override.y
				for flag_key in cs.tile.status_flags:
					hash_val = hash_val * 31 + flag_key.hash()
			else:
				hash_val = hash_val * 31 + 0
	return hash_val


# ---- Query Helpers ----


## Returns all non-blocked cell positions.
func all_cells() -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var pos := Vector2i(x, y)
			if not is_blocked(pos):
				output.append(pos)
	return output


## Returns all cell positions including blocked ones.
func all_positions() -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			output.append(Vector2i(x, y))
	return output


func to_debug_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in size.y:
		var pieces: Array[String] = []
		for x in size.x:
			var pos := Vector2i(x, y)
			if is_blocked(pos):
				pieces.append("#")
			else:
				var tile: TileState = get_tile(pos)
				pieces.append("." if tile == null else str(tile.tier))
		rows.append(" ".join(pieces))
	return rows


# ---- Internal ----


static func _portal_key(cell: Vector2i, direction: Vector2i) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, direction.x, direction.y]
