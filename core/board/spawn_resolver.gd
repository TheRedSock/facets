class_name SpawnResolver
extends RefCounted

## Per-tile spawn events from the last refill operation.
## Each entry: { type: "tile_spawned", cell: Vector2i, tile_id: StringName, tier: int }
## Consumed by the EventTimeline for animation sequencing.
var last_spawn_events: Array[Dictionary] = []


## Populates the entire board using a spawn table for weighted tier selection.
func populate_board(board: BoardState, rng: SeededRng, spawn_table: SpawnTableResource) -> void:
	for cell in board.all_cells():
		board.set_tile(cell, _spawn_tile(rng, spawn_table))


## Fills spawn-eligible empty cells using a spawn table.
## Call with the result of BoardPhysics.find_spawn_eligible_cells() for
## topology-aware spawning, or with an empty array to fall back to all empties.
## Returns the number of tiles spawned.
func refill_spawn_entries(
	board: BoardState,
	rng: SeededRng,
	spawn_table: SpawnTableResource,
	spawn_cells: Array[Vector2i],
) -> int:
	last_spawn_events.clear()
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
			})
			spawned += 1
	return spawned


## Legacy refill: fills all empty non-blocked cells.
## Kept for backward compatibility with simple boards.
## Returns the number of tiles spawned.
func refill_empty_cells(board: BoardState, rng: SeededRng, spawn_table: SpawnTableResource) -> int:
	last_spawn_events.clear()
	var spawned := 0
	for y in board.size.y:
		for x in board.size.x:
			var pos := Vector2i(x, y)
			if not board.is_blocked(pos) and board.get_tile(pos) == null:
				var tile := _spawn_tile(rng, spawn_table)
				board.set_tile(pos, tile)
				last_spawn_events.append({
					"type": &"tile_spawned",
					"cell": pos,
					"tile_id": tile.tile_id,
					"tier": tile.tier,
				})
				spawned += 1
	return spawned


## Creates a single tile using weighted random selection from the spawn table.
## Uses TileRegistry for named tiles if available, falls back to debug tiles.
func _spawn_tile(rng: SeededRng, spawn_table: SpawnTableResource) -> TileState:
	var tier := _weighted_pick_int(rng, spawn_table.allowed_tiers, spawn_table.weights)
	# Use TileRegistry for proper named tiles if definitions are loaded
	var tile_registry: Node = _get_tile_registry()
	if tile_registry != null and tile_registry.has_definitions():
		return tile_registry.create_tile_for_tier(tier, rng)
	return TileState.from_debug_tier(tier)


## Integer-only weighted random selection. No floating point operations.
## Eliminates cross-platform determinism risk from float multiplication/comparison.
func _weighted_pick_int(rng: SeededRng, values: Array[int], weights: Array[int]) -> int:
	if values.is_empty():
		return 1

	# If weights are missing or mismatched, fall back to uniform
	if weights.size() != values.size():
		return values[rng.randi_range(0, values.size() - 1)]

	var total_weight := 0
	for w in weights:
		total_weight += w

	if total_weight <= 0:
		return values[rng.randi_range(0, values.size() - 1)]

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


func _get_tile_registry() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop.root.get_node_or_null("/root/TileRegistry")
	return null
