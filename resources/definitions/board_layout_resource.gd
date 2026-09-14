class_name BoardLayoutResource
extends Resource

## Defines the complete topology of a board — shape, gravity, portals, spawn entries.
## Can be authored as a .tres file for hand-designed levels, or constructed
## programmatically for procedural generation.

## Unique identifier for this layout.
@export var layout_id: StringName = &"default"
@export var schema_version: int = 1
@export_enum("fill_empty_cells", "entry_only") var spawn_policy: String = "fill_empty_cells"

## Board dimensions (width x height). All cells within this rectangle exist;
## use blocked_cells to carve out holes/shapes.
@export var board_size: Vector2i = Vector2i(8, 8)

## Cells that are blocked (holes/walls). Coordinates as Vector2i.
@export var blocked_cells: Array[Vector2i] = []

## Per-cell gravity direction overrides. Key: "x,y" string, Value: Vector2i direction.
## Cells not listed default to Vector2i.DOWN.
## Use string keys because Godot .tres serialization handles Dictionary[String, Variant]
## cleanly but not Dictionary[Vector2i, Vector2i].
@export var gravity_overrides: Dictionary = {}

## Cells where new tiles enter the board during spawn.
## If empty, the engine falls back to filling all empty cells after gravity
## (standard match-3 behavior for simple boards).
@export var spawn_entries: Array[Vector2i] = []

## Per-cell diagonal fill source directions. Key: "x,y" string, Value: Array of Vector2i.
## When a cell is empty after primary gravity, these directions are checked for tiles
## that can slide diagonally into the cell.
@export var fill_source_overrides: Dictionary = {}

## Portal connections that override normal grid adjacency for gravity.
## Each entry: { "from": Vector2i, "direction": Vector2i, "to": Vector2i }
## When a tile at "from" follows gravity in "direction", it arrives at "to"
## instead of the normal grid neighbor.
@export var portals: Array[Dictionary] = []


# ---- Builder API for programmatic / procedural construction ----


## Sets the gravity direction for a specific cell.
func set_gravity(cell: Vector2i, direction: Vector2i) -> void:
	gravity_overrides[_cell_key(cell)] = direction


## Returns the gravity direction for a cell (default: DOWN).
func get_gravity(cell: Vector2i) -> Vector2i:
	return gravity_overrides.get(_cell_key(cell), Vector2i.DOWN)


## Marks a cell as blocked (hole/wall).
func add_blocked(cell: Vector2i) -> void:
	if cell not in blocked_cells:
		blocked_cells.append(cell)


## Marks a cell as a spawn entry point.
func add_spawn_entry(cell: Vector2i) -> void:
	if cell not in spawn_entries:
		spawn_entries.append(cell)


## Adds a portal connection.
func add_portal(from: Vector2i, direction: Vector2i, to: Vector2i) -> void:
	portals.append({"from": from, "direction": direction, "to": to})


## Sets the diagonal fill source directions for a cell.
func set_fill_sources(cell: Vector2i, sources: Array[Vector2i]) -> void:
	fill_source_overrides[_cell_key(cell)] = sources


## Converts a Vector2i to a string key for dictionary storage.
static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


## Parses a string key back to a Vector2i.
static func _parse_cell_key(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
