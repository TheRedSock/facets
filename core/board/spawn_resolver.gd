class_name SpawnResolver
extends RefCounted

## Per-tile spawn events from the last refill operation.
## Each entry: { type: "tile_spawned", cell: Vector2i, tile_id: StringName, tier: int }
## Consumed by the EventTimeline for animation sequencing.
var last_spawn_events: Array[Dictionary] = []

var catalog: GameCatalog
var last_error := ""

func _init(admitted_catalog: GameCatalog = null) -> void:
	catalog = admitted_catalog


## Populates the entire board using a spawn table for weighted tier selection.
func populate_board(board: BoardState, rng: SeededRng, spawn_table: SpawnTableResource) -> bool:
	if not _admit_supply(spawn_table): return false
	for cell in board.all_cells():
		board.set_tile(cell, _spawn_tile(rng, spawn_table))
	return true


## Fills spawn-eligible empty cells using a spawn table.
## Call with the result of BoardPhysics.find_spawn_eligible_cells() for
## topology-aware spawning. An empty eligible list always remains empty.
## Returns the number of tiles spawned.
func refill_spawn_entries(
	board: BoardState,
	rng: SeededRng,
	spawn_table: SpawnTableResource,
	spawn_cells: Array[Vector2i],
) -> int:
	last_spawn_events.clear()
	if not _admit_supply(spawn_table): return -1
	var spawned := 0
	for pos in spawn_cells:
		if not board.is_blocked(pos) and board.get_tile(pos) == null:
			var tile := _spawn_tile(rng, spawn_table)
			board.set_tile(pos, tile)
			last_spawn_events.append({
				"type": &"tile_spawned",
				"cell": pos,
				"tile_id": tile.tile_id,
				"tier": tile.tier,
				"instance_id": tile.instance_id,
				"source": tile.to_dict(),
				"direction": board.get_effective_gravity(pos),
			})
			spawned += 1
	return spawned


## Legacy refill: fills all empty non-blocked cells.
## Kept for backward compatibility with simple boards.
## Returns the number of tiles spawned.
func refill_empty_cells(board: BoardState, rng: SeededRng, spawn_table: SpawnTableResource) -> int:
	return refill_spawn_entries(board, rng, spawn_table, board.all_cells())

func _admit_supply(spawn_table: SpawnTableResource) -> bool:
	last_error = ""
	if catalog == null: last_error = "missing_catalog"
	elif spawn_table == null: last_error = "missing_supply"
	else: last_error = GameCatalog.validate_supply(Array(spawn_table.allowed_tiers), Array(spawn_table.weights))
	return last_error.is_empty()

## Creates a single tile using weighted random selection from the spawn table.
## Uses only the admitted roster; missing/invalid inputs fail before drawing.
func _spawn_tile(rng: SeededRng, spawn_table: SpawnTableResource) -> TileState:
	last_error = ""
	if catalog == null:
		last_error = "missing_catalog"
		return null
	if spawn_table == null:
		last_error = "missing_supply"
		return null
	last_error = GameCatalog.validate_supply(Array(spawn_table.allowed_tiers), Array(spawn_table.weights))
	if not last_error.is_empty(): return null
	var tier := _weighted_pick_int(rng, spawn_table.allowed_tiers, spawn_table.weights)
	return catalog.create_tile(tier)


## Integer-only weighted random selection. No floating point operations.
## Eliminates cross-platform determinism risk from float multiplication/comparison.
func _weighted_pick_int(rng: SeededRng, values: Array[int], weights: Array[int]) -> int:
	if not GameCatalog.validate_supply(Array(values), Array(weights)).is_empty(): return -1

	var total_weight := 0
	for w in weights:
		total_weight += w


	var roll := rng.randi_range(0, total_weight - 1)
	var cumulative := 0
	for i in values.size():
		cumulative += weights[i]
		if roll < cumulative:
			return values[i]

	# Fallback (should not reach here)
	return values[values.size() - 1]


## Legacy debug helper — populates with uniform distribution.
func populate_debug_board(board: BoardState, rng: SeededRng, visible_tiers: int) -> void:
	for cell in board.all_cells():
		board.set_tile(cell, TileState.from_debug_tier(rng.randi_range(1, max(1, visible_tiers))))
