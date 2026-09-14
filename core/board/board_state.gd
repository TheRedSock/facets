class_name BoardState
extends RefCounted

var size: Vector2i = Vector2i.ZERO
var _cells: Array = []
var spawn_policy: String = "fill_empty_cells"
var next_instance: int = 1
var id_namespace: String = "piece"
## P2 obstacle layer; an obstacle occupies an active cell without a gem.
var room_board := false
var obstacles: Dictionary = {}

## Portal connections: "x,y,dx,dy" -> Vector2i target cell.
## When get_neighbor() is called for a cell+direction that has a portal entry,
## the portal target is returned instead of the normal grid neighbor.
var _portals: Dictionary = {}


func _init(board_size: Vector2i = Vector2i.ZERO) -> void:
	if board_size != Vector2i.ZERO:
		resize(board_size)


func resize(board_size: Vector2i) -> void:
	size = board_size
	obstacles.clear()
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
	if cell_state == null or cell_state.blocked or not obstacle_at(cell).is_empty():
		return
	if tile != null and tile.instance_id.is_empty():
		tile.instance_id = "%s/%d" % [id_namespace, next_instance]
		next_instance += 1
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
func swap_cells(a: Vector2i, b: Vector2i) -> bool:
	if a == b or not can_move_occupant(a) or not can_move_occupant(b): return false
	var cell_a: CellState = get_cell(a)
	var cell_b: CellState = get_cell(b)
	if cell_a.blocked or cell_b.blocked:
		return false
	if (cell_a.tile != null and cell_a.tile.immovable) or \
	   (cell_b.tile != null and cell_b.tile.immovable):
		return false
	var temp := cell_a.tile
	cell_a.tile = cell_b.tile
	cell_b.tile = temp
	return true


## Moves a tile from one cell to another. Target must be empty and non-blocked.
## Returns true if the move succeeded.
func move_tile(from: Vector2i, to: Vector2i) -> bool:
	if not can_move_occupant(from): return false
	var from_cell: CellState = get_cell(from)
	if from_cell == null or from_cell.tile == null:
		return false
	var to_cell: CellState = get_cell(to)
	if to_cell == null or not can_enter(to):
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
	return cs.gravity_direction if cs.gravity_direction != Vector2i.ZERO else Vector2i.DOWN

func can_move_occupant(cell: Vector2i) -> bool:
	var cs := get_cell(cell)
	return cs != null and not cs.blocked and cs.tile != null and not cs.tile.immovable and cs.lock.is_empty() and obstacle_at(cell).is_empty()

func obstacle_at(cell: Vector2i) -> Dictionary:
	for obstacle in obstacles.values():
		if obstacle.cell == cell: return obstacle
	return {}

func can_enter(cell: Vector2i) -> bool:
	var cs := get_cell(cell)
	return cs != null and not cs.blocked and cs.tile == null and obstacle_at(cell).is_empty()

func obstacle_neighbors(cells: Array) -> Array:
	var targets := {}
	for cell in cells:
		for direction in LayoutAdmission.CARDINALS:
			var neighbor := neighbor_for(cell, direction, "match")
			var obstacle := obstacle_at(neighbor)
			if not obstacle.is_empty(): targets[obstacle.id] = obstacle.duplicate(true)
	var ordered := targets.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return MatchClassifier.cell_less(a.cell, b.cell))
	return ordered

func neighbor_for(cell: Vector2i, direction: Vector2i, purpose: String) -> Vector2i:
	if is_blocked(cell) or purpose not in ["match", "swap", "gravity", "fill"]: return Vector2i(-1, -1)
	if purpose in ["match", "swap"] and abs(direction.x) + abs(direction.y) != 1: return Vector2i(-1, -1)
	var target := get_neighbor(cell, direction) if purpose == "gravity" else cell + direction
	return Vector2i(-1, -1) if is_blocked(target) else target

func duplicate_board() -> BoardState:
	var result := BoardState.new(size)
	result._portals = _portals.duplicate(true)
	result.spawn_policy = spawn_policy
	result.next_instance = next_instance
	result.id_namespace = id_namespace
	result.room_board = room_board
	result.obstacles = obstacles.duplicate(true)
	for i in _cells.size():
		var source: CellState = _cells[i]
		var target: CellState = result._cells[i]
		target.blocked = source.blocked
		target.gravity_direction = source.gravity_direction
		target.fill_sources = source.fill_sources.duplicate()
		target.is_spawn_entry = source.is_spawn_entry
		target.tags = source.tags.duplicate(true)
		target.lock = source.lock.duplicate(true)
		target.tile = source.tile.duplicate_tile() if source.tile != null else null
	return result

func to_dict() -> Dictionary:
	var cells: Array = []
	for cs in _cells: cells.append(cs.to_dict())
	var data := {"size": size, "cells": cells, "portals": _portals.duplicate(true), "spawn_policy": spawn_policy, "next_instance": next_instance, "id_namespace": id_namespace}
	if room_board: data.obstacles = obstacles.duplicate(true)
	return data


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
func apply_layout(layout: BoardLayoutResource) -> bool:
	var result := LayoutAdmission.admit(layout)
	if not result.ok: return false
	apply_topology(result.topology)
	return true

func apply_topology(topology: Dictionary) -> void:
	resize(topology.size)
	spawn_policy = topology.spawn_policy
	_portals = topology.portals.duplicate(true)
	for i in _cells.size():
		var raw: Dictionary = topology.cells[i]
		var cs: CellState = _cells[i]
		cs.blocked = raw.blocked
		cs.gravity_direction = raw.gravity
		cs.is_spawn_entry = raw.entry
		cs.fill_sources.assign(raw.fill)

func layout_resource() -> BoardLayoutResource:
	var layout := BoardLayoutResource.new()
	layout.board_size = size
	layout.spawn_policy = spawn_policy
	for pos in all_positions():
		var cs := get_cell(pos)
		if cs.blocked: layout.add_blocked(pos); continue
		layout.set_gravity(pos, cs.gravity_direction)
		if cs.is_spawn_entry: layout.add_spawn_entry(pos)
		if not cs.fill_sources.is_empty(): layout.set_fill_sources(pos, cs.fill_sources)
	for key in _portals:
		var parts: PackedStringArray = key.split(",")
		layout.add_portal(Vector2i(int(parts[0]),int(parts[1])),Vector2i(int(parts[2]),int(parts[3])),_portals[key])
	return layout

# ---- State Hashing ----


## Computes a deterministic hash of the complete board state.
## Used for replay verification and anti-cheat checkpoints.
## Two boards with identical cell/tile configurations produce identical hashes.
func compute_hash() -> int:
	# Compatibility only. Authoritative replay uses the complete SHA-256 digest.
	return digest().left(15).hex_to_int()

func digest() -> String:
	return CanonicalCodec.digest(to_dict())

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
