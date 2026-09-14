class_name CellState
extends RefCounted

## The tile occupying this cell, or null if empty.
var tile: TileState = null

## Whether this cell is blocked (hole, wall, etc.). Blocked cells cannot hold tiles.
var blocked: bool = false

## The direction tiles fall in this cell. Default is DOWN.
var gravity_direction: Vector2i = Vector2i.DOWN

## Whether new tiles can enter the board through this cell during spawn.
var is_spawn_entry: bool = false

## Additional directions this cell can accept tiles from (diagonal fill).
## Each entry is a direction vector pointing to the source cell.
## E.g., Vector2i(-1, -1) means "accept tiles from the cell above-left."
var fill_sources: Array[Vector2i] = []

## Extensible metadata for cell modifiers (ice, lava, conveyor, etc.).
var tags: Dictionary = {}
## Minimal movement lock; matching is independent. Seal lifecycle is deferred.
var lock: Dictionary = {}


static func open() -> CellState:
	return CellState.new()


static func hole() -> CellState:
	var cell := CellState.new()
	cell.blocked = true
	return cell


static func configured(gravity: Vector2i, spawn_entry: bool = false) -> CellState:
	var cell := CellState.new()
	cell.gravity_direction = gravity
	cell.is_spawn_entry = spawn_entry
	return cell


func is_empty() -> bool:
	return tile == null and not blocked


func is_occupied() -> bool:
	return tile != null


func clear_tile() -> void:
	tile = null


func to_dict() -> Dictionary:
	var tile_data: Variant = null
	if tile != null:
		tile_data = tile.to_dict()
	return {
		"blocked": blocked,
		"gravity_direction": {"x": gravity_direction.x, "y": gravity_direction.y},
		"is_spawn_entry": is_spawn_entry,
		"fill_sources": fill_sources.duplicate(),
		"tags": tags.duplicate(),
		"lock": lock.duplicate(true),
		"tile": tile_data,
	}
