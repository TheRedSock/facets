extends SceneTree

## Headless smoke test for the core pipeline.
## Run from command line: godot --headless --script tests/test_smoke.gd
##
## Tests the full pipeline: board creation → topology → match detection →
## gravity → spawn → turn resolution → determinism.

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	print("\n=== Facets Smoke Test ===\n")

	# Phase 1: Data layer
	test_board_creation()
	test_tile_state()
	test_cell_state_properties()
	test_tile_state_properties()
	test_board_layout_resource()
	test_get_neighbor_standard()
	test_get_neighbor_out_of_bounds()
	test_get_neighbor_portal()
	test_effective_gravity_default()
	test_effective_gravity_cell_override()
	test_effective_gravity_tile_override()
	test_swap_immovable()
	test_board_hash_deterministic()
	test_board_hash_changes()
	test_conflict_resolver_vector_key()

	# Phase 2: Match detection
	test_match_detection()
	test_match_detection_with_unmatchable()
	test_match_detection_with_holes()
	test_match_classification()

	# Merge mechanic
	test_merge_base_match()
	test_merge_removes_correct_count()
	test_merge_max_tier_removes_all()

	# Phase 3: Board physics
	test_gravity_standard_down()
	test_gravity_over_blocked()
	test_gravity_custom_direction()
	test_gravity_tile_override()
	test_gravity_immovable()
	test_gravity_iterative_convergence()
	test_gravity_diagonal_fill()
	test_gravity_portal()
	test_gravity_move_events()
	test_gravity_determinism()
	test_gravity_max_rounds_safety()

	# Phase 4: Pipeline
	test_effect_planning()
	test_conflict_resolution()
	test_effect_resolution()
	test_gradient_strength_without_texture()
	test_spawn_integer_weighted_pick()
	test_spawn_integer_determinism()
	test_event_timeline_structure()
	test_turn_controller()
	test_seeded_rng_determinism()

	# Phase 6: Determinism verification
	test_replay_determinism()
	test_board_validator_cycle_detection()
	test_board_validator_portal_validation()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])

	if _fail_count > 0:
		quit(1)
	else:
		quit(0)


# ---- Phase 1: Data Layer Tests ----


func test_board_creation() -> void:
	var board := BoardState.new(Vector2i(8, 8))
	assert_eq(board.size, Vector2i(8, 8), "Board size should be 8x8")
	assert_true(board.in_bounds(Vector2i(0, 0)), "Origin should be in bounds")
	assert_true(board.in_bounds(Vector2i(7, 7)), "Corner should be in bounds")
	assert_false(board.in_bounds(Vector2i(8, 8)), "Out of bounds should be false")
	assert_false(board.in_bounds(Vector2i(-1, 0)), "Negative should be false")


func test_tile_state() -> void:
	var tile := TileState.from_debug_tier(3)
	assert_eq(tile.tier, 3, "Tier should be 3")
	assert_eq(tile.get_match_group(), &"debug_tier_3", "match_group should default to tile_id")
	assert_false(tile.protected, "Should not be protected by default")


func test_cell_state_properties() -> void:
	var cell := CellState.open()
	assert_eq(cell.gravity_direction, Vector2i.DOWN, "Default gravity should be DOWN")
	assert_false(cell.is_spawn_entry, "Should not be spawn entry by default")
	assert_eq(cell.fill_sources.size(), 0, "Should have no fill sources by default")
	assert_eq(cell.tags.size(), 0, "Should have no tags by default")

	var configured := CellState.configured(Vector2i.LEFT, true)
	assert_eq(configured.gravity_direction, Vector2i.LEFT, "Configured gravity should be LEFT")
	assert_true(configured.is_spawn_entry, "Configured should be spawn entry")


func test_tile_state_properties() -> void:
	var tile := TileState.from_debug_tier(2)
	assert_eq(tile.gravity_override, Vector2i.ZERO, "Default gravity_override should be ZERO")
	assert_false(tile.immovable, "Should not be immovable by default")
	assert_false(tile.unmatchable, "Should not be unmatchable by default")

	tile.gravity_override = Vector2i.LEFT
	tile.immovable = true
	tile.unmatchable = true
	var dup := tile.duplicate_tile()
	assert_eq(dup.gravity_override, Vector2i.LEFT, "Duplicate should copy gravity_override")
	assert_true(dup.immovable, "Duplicate should copy immovable")
	assert_true(dup.unmatchable, "Duplicate should copy unmatchable")


func test_board_layout_resource() -> void:
	var layout := BoardLayoutResource.new()
	layout.board_size = Vector2i(4, 4)
	layout.add_blocked(Vector2i(1, 1))
	layout.set_gravity(Vector2i(0, 0), Vector2i.LEFT)
	layout.add_spawn_entry(Vector2i(3, 0))
	layout.add_portal(Vector2i(0, 3), Vector2i.DOWN, Vector2i(3, 0))
	layout.set_fill_sources(Vector2i(2, 2), [Vector2i(-1, -1), Vector2i(1, -1)])

	var board := BoardState.new()
	board.apply_layout(layout)

	assert_eq(board.size, Vector2i(4, 4), "Board size should be 4x4")
	assert_true(board.is_blocked(Vector2i(1, 1)), "Cell (1,1) should be blocked")
	assert_false(board.is_blocked(Vector2i(0, 0)), "Cell (0,0) should not be blocked")
	assert_eq(board.get_cell(Vector2i(0, 0)).gravity_direction, Vector2i.LEFT, "(0,0) gravity should be LEFT")
	assert_eq(board.get_cell(Vector2i(2, 2)).gravity_direction, Vector2i.DOWN, "(2,2) gravity should be default DOWN")
	assert_true(board.get_cell(Vector2i(3, 0)).is_spawn_entry, "(3,0) should be spawn entry")
	assert_true(board.has_portal(Vector2i(0, 3), Vector2i.DOWN), "Portal should exist from (0,3) DOWN")
	assert_eq(board.get_neighbor(Vector2i(0, 3), Vector2i.DOWN), Vector2i(3, 0), "Portal should route to (3,0)")
	assert_eq(board.get_cell(Vector2i(2, 2)).fill_sources.size(), 2, "(2,2) should have 2 fill sources")


func test_get_neighbor_standard() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	assert_eq(board.get_neighbor(Vector2i(2, 2), Vector2i.RIGHT), Vector2i(3, 2), "Right neighbor of (2,2)")
	assert_eq(board.get_neighbor(Vector2i(2, 2), Vector2i.DOWN), Vector2i(2, 3), "Down neighbor of (2,2)")
	assert_eq(board.get_neighbor(Vector2i(2, 2), Vector2i.LEFT), Vector2i(1, 2), "Left neighbor of (2,2)")
	assert_eq(board.get_neighbor(Vector2i(2, 2), Vector2i.UP), Vector2i(2, 1), "Up neighbor of (2,2)")


func test_get_neighbor_out_of_bounds() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	assert_eq(board.get_neighbor(Vector2i(4, 2), Vector2i.RIGHT), Vector2i(-1, -1), "Right edge should be OOB")
	assert_eq(board.get_neighbor(Vector2i(0, 2), Vector2i.LEFT), Vector2i(-1, -1), "Left edge should be OOB")
	assert_eq(board.get_neighbor(Vector2i(2, 0), Vector2i.UP), Vector2i(-1, -1), "Top edge should be OOB")
	assert_eq(board.get_neighbor(Vector2i(2, 4), Vector2i.DOWN), Vector2i(-1, -1), "Bottom edge should be OOB")


func test_get_neighbor_portal() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.add_portal(Vector2i(2, 4), Vector2i.DOWN, Vector2i(0, 0))
	assert_eq(board.get_neighbor(Vector2i(2, 4), Vector2i.DOWN), Vector2i(0, 0), "Portal should override neighbor")
	assert_eq(board.get_neighbor(Vector2i(2, 4), Vector2i.RIGHT), Vector2i(3, 4), "Non-portal direction should be normal")


func test_effective_gravity_default() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	assert_eq(board.get_effective_gravity(Vector2i(2, 2)), Vector2i.DOWN, "Default effective gravity should be DOWN")


func test_effective_gravity_cell_override() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.get_cell(Vector2i(2, 2)).gravity_direction = Vector2i.LEFT
	assert_eq(board.get_effective_gravity(Vector2i(2, 2)), Vector2i.LEFT, "Cell gravity override should be LEFT")


func test_effective_gravity_tile_override() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.get_cell(Vector2i(2, 2)).gravity_direction = Vector2i.LEFT
	var tile := TileState.from_debug_tier(1)
	tile.gravity_override = Vector2i.RIGHT
	board.set_tile(Vector2i(2, 2), tile)
	assert_eq(board.get_effective_gravity(Vector2i(2, 2)), Vector2i.RIGHT, "Tile gravity override should take priority")


func test_swap_immovable() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	var tile_a := TileState.from_debug_tier(1)
	tile_a.immovable = true
	var tile_b := TileState.from_debug_tier(2)
	board.set_tile(Vector2i(0, 0), tile_a)
	board.set_tile(Vector2i(1, 0), tile_b)
	board.swap_cells(Vector2i(0, 0), Vector2i(1, 0))
	# Swap should be rejected — tile_a is still at (0,0)
	assert_eq(board.get_tile(Vector2i(0, 0)).tier, 1, "Immovable tile should not be swapped")
	assert_eq(board.get_tile(Vector2i(1, 0)).tier, 2, "Other tile should remain in place")


func test_board_hash_deterministic() -> void:
	var board_a := BoardState.new(Vector2i(3, 3))
	var board_b := BoardState.new(Vector2i(3, 3))
	board_a.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board_a.set_tile(Vector2i(1, 1), TileState.from_debug_tier(3))
	board_b.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board_b.set_tile(Vector2i(1, 1), TileState.from_debug_tier(3))
	assert_eq(board_a.compute_hash(), board_b.compute_hash(), "Identical boards should have identical hashes")


func test_board_hash_changes() -> void:
	var board := BoardState.new(Vector2i(3, 3))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	var hash_before := board.compute_hash()
	board.get_tile(Vector2i(0, 0)).tier = 5
	var hash_after := board.compute_hash()
	assert_true(hash_before != hash_after, "Hash should change when tile tier changes")


func test_conflict_resolver_vector_key() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))

	var plan: Array[Dictionary] = [
		{"effect": EffectPlanner.EFFECT_REMOVE, "cell": Vector2i(0, 0), "reason": &"test"},
		{"effect": EffectPlanner.EFFECT_REMOVE, "cell": Vector2i(0, 0), "reason": &"test_dup"},
	]

	var resolver := ConflictResolver.new()
	var resolved := resolver.resolve(plan, board)
	assert_eq(resolved.size(), 1, "Should deduplicate to 1 removal with Vector2i key")


# ---- Phase 2: Match Detection Tests ----


func test_match_detection() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(2, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(3, 0), TileState.from_debug_tier(2))

	var detector := MatchDetector.new()
	var matches := detector.find_matches(board)
	assert_true(matches.size() >= 1, "Should find at least 1 match")
	assert_eq(matches[0]["cells"].size(), 3, "Match should have 3 cells")


func test_match_detection_with_unmatchable() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	var unmatchable_tile := TileState.from_debug_tier(1)
	unmatchable_tile.unmatchable = true
	board.set_tile(Vector2i(1, 0), unmatchable_tile)
	board.set_tile(Vector2i(2, 0), TileState.from_debug_tier(1))

	var detector := MatchDetector.new()
	var matches := detector.find_matches(board)
	assert_eq(matches.size(), 0, "Unmatchable tile should break the run — no match found")


func test_match_detection_with_holes() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))
	board.set_blocked(Vector2i(2, 0), true)  # Hole breaks the run
	board.set_tile(Vector2i(3, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(4, 0), TileState.from_debug_tier(1))

	var detector := MatchDetector.new()
	var matches := detector.find_matches(board)
	assert_eq(matches.size(), 0, "Hole should break the run — no 3-match on either side")


func test_match_classification() -> void:
	var raw_matches: Array[Dictionary] = [
		{
			"type": &"line_horizontal",
			"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i],
			"match_group": &"debug_tier_1",
			"tier": 1,
		},
	]
	var classifier := MatchClassifier.new()
	var classified := classifier.classify(raw_matches)
	assert_eq(classified.size(), 1, "Should classify 1 match")
	assert_eq(classified[0].get("semantic_type"), &"base_match", "Should be a base_match")


# ---- Merge Mechanic Tests ----


func test_merge_base_match() -> void:
	# A 3-match of T1 tiles should remove 2 and upgrade 1 to T2
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(2, 0), TileState.from_debug_tier(1))

	var planner := EffectPlanner.new()
	var classified: Array[Dictionary] = [{
		"semantic_type": &"base_match",
		"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"match_group": &"debug_tier_1",
		"tier": 1,
	}]
	var plan := planner.build_base_plan(classified)

	var event_log := EventLog.new()
	var resolver := EffectResolver.new()
	resolver.apply(board, plan, event_log)

	# (0,0) and (1,0) should be removed, (2,0) should be upgraded to T2
	assert_true(board.get_tile(Vector2i(0, 0)) == null, "First cell should be removed")
	assert_true(board.get_tile(Vector2i(1, 0)) == null, "Second cell should be removed")
	assert_true(board.get_tile(Vector2i(2, 0)) != null, "Survivor cell should still exist")
	assert_eq(board.get_tile(Vector2i(2, 0)).tier, 2, "Survivor should be upgraded to T2")


func test_merge_removes_correct_count() -> void:
	# A 4-match should remove 3 and upgrade 1
	var planner := EffectPlanner.new()
	var classified: Array[Dictionary] = [{
		"semantic_type": &"match_4",
		"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
		"match_group": &"debug_tier_2",
		"tier": 2,
	}]
	var plan := planner.build_base_plan(classified)

	var removes := 0
	var upgrades := 0
	for entry in plan:
		if entry.get("effect") == EffectPlanner.EFFECT_REMOVE:
			removes += 1
		elif entry.get("effect") == EffectPlanner.EFFECT_UPGRADE:
			upgrades += 1
	assert_eq(removes, 3, "4-match should produce 3 removes")
	assert_eq(upgrades, 1, "4-match should produce 1 upgrade")


func test_merge_max_tier_removes_all() -> void:
	# A match at max tier (T8) should remove all tiles (no upgrade possible)
	var planner := EffectPlanner.new()
	var classified: Array[Dictionary] = [{
		"semantic_type": &"base_match",
		"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"match_group": &"debug_tier_8",
		"tier": 8,
	}]
	var plan := planner.build_base_plan(classified)

	var removes := 0
	var upgrades := 0
	for entry in plan:
		if entry.get("effect") == EffectPlanner.EFFECT_REMOVE:
			removes += 1
		elif entry.get("effect") == EffectPlanner.EFFECT_UPGRADE:
			upgrades += 1
	assert_eq(removes, 3, "Max-tier match should remove all 3 tiles")
	assert_eq(upgrades, 0, "Max-tier match should have no upgrades")


# ---- Phase 3: Board Physics Tests ----


func test_gravity_standard_down() -> void:
	var board := BoardState.new(Vector2i(3, 3))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))

	var physics := BoardPhysics.new()
	var moves := physics.resolve_gravity(board)

	assert_true(moves > 0, "Should have moved tiles down")
	assert_true(board.get_tile(Vector2i(1, 2)) != null, "Tile should have fallen to bottom")
	assert_true(board.get_tile(Vector2i(1, 0)) == null, "Top cell should be empty")


func test_gravity_over_blocked() -> void:
	var board := BoardState.new(Vector2i(3, 4))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))
	board.set_blocked(Vector2i(1, 2), true)  # Hole at row 2

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	assert_true(board.get_tile(Vector2i(1, 1)) != null, "Tile should rest above the hole")
	assert_true(board.get_tile(Vector2i(1, 0)) == null, "Original position should be empty")


func test_gravity_custom_direction() -> void:
	var board := BoardState.new(Vector2i(5, 3))
	# Configure the whole lane so the tile settles at the right edge
	# instead of dropping when it reaches the default-DOWN cell.
	board.get_cell(Vector2i(0, 1)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(1, 1)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(2, 1)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(3, 1)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(4, 1)).gravity_direction = Vector2i.RIGHT
	board.set_tile(Vector2i(0, 1), TileState.from_debug_tier(1))

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	assert_true(board.get_tile(Vector2i(4, 1)) != null, "Tile should have moved right to (4,1)")
	assert_true(board.get_tile(Vector2i(0, 1)) == null, "Original position should be empty")


func test_gravity_tile_override() -> void:
	var board := BoardState.new(Vector2i(5, 3))
	# Cell gravity is DOWN, but tile overrides to LEFT
	var tile := TileState.from_debug_tier(1)
	tile.gravity_override = Vector2i.LEFT
	board.set_tile(Vector2i(3, 1), tile)

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	assert_true(board.get_tile(Vector2i(0, 1)) != null, "Tile should have moved left to (0,1)")
	assert_true(board.get_tile(Vector2i(3, 1)) == null, "Original position should be empty")


func test_gravity_immovable() -> void:
	var board := BoardState.new(Vector2i(3, 4))
	var immovable := TileState.from_debug_tier(1)
	immovable.immovable = true
	board.set_tile(Vector2i(1, 1), immovable)
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(2))

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	assert_eq(board.get_tile(Vector2i(1, 1)).tier, 1, "Immovable tile should stay at (1,1)")
	# The tile above the immovable one can't fall past it, but it shouldn't be at (1,0)
	# It should stay at (1,0) because (1,1) is occupied by the immovable tile
	assert_true(board.get_tile(Vector2i(1, 0)) != null, "Tile above immovable should stack on top")


func test_gravity_iterative_convergence() -> void:
	# L-shaped gravity: down then right
	var board := BoardState.new(Vector2i(4, 4))
	# Column 0 has DOWN gravity (default)
	# Row 3 has RIGHT gravity
	board.get_cell(Vector2i(0, 3)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(1, 3)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(2, 3)).gravity_direction = Vector2i.RIGHT
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	# Tile should fall to (0,3) then slide right to (3,3)
	assert_true(board.get_tile(Vector2i(3, 3)) != null, "Tile should reach (3,3) via L-path")
	assert_true(board.get_tile(Vector2i(0, 0)) == null, "Original position should be empty")


func test_gravity_diagonal_fill() -> void:
	var board := BoardState.new(Vector2i(3, 3))
	# Block all orthogonal neighbors of (1,2) except diagonals
	board.set_blocked(Vector2i(0, 2), true)
	board.set_blocked(Vector2i(2, 2), true)
	board.set_blocked(Vector2i(1, 1), true)
	# Enable diagonal fill on (1,2) from upper-left direction
	board.get_cell(Vector2i(1, 2)).fill_sources = [Vector2i(-1, -1), Vector2i(1, -1)]
	# Place a tile at (0,1) — diagonally above-left of (1,2)
	board.set_tile(Vector2i(0, 1), TileState.from_debug_tier(1))
	# (0,1) has DOWN gravity but (0,2) is blocked, so it can't fall.
	# (1,2) has diagonal fill from (-1,-1), which points to (0,1). Should slide in.

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	assert_true(board.get_tile(Vector2i(1, 2)) != null, "Tile should have filled diagonally into (1,2)")
	assert_true(board.get_tile(Vector2i(0, 1)) == null, "Source cell should be empty")


func test_gravity_portal() -> void:
	var board := BoardState.new(Vector2i(3, 4))
	# Portal from bottom of col 0 to top of col 2
	board.add_portal(Vector2i(0, 3), Vector2i.DOWN, Vector2i(2, 0))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	# Tile falls from (0,0) to (0,3), then portal sends it to (2,0),
	# then it falls from (2,0) to (2,3)
	assert_true(board.get_tile(Vector2i(2, 3)) != null, "Tile should have fallen through portal to (2,3)")
	assert_true(board.get_tile(Vector2i(0, 0)) == null, "Original position should be empty")


func test_gravity_move_events() -> void:
	var board := BoardState.new(Vector2i(3, 3))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))

	var physics := BoardPhysics.new()
	physics.resolve_gravity(board)

	assert_true(physics.last_move_events.size() > 0, "Should have recorded move events")
	# The tile should have moved through (1,0)->(1,1) and (1,1)->(1,2)
	# (two single-step moves across two rounds)
	var first_event: Dictionary = physics.last_move_events[0]
	assert_eq(first_event.get("type"), &"tile_moved", "Event type should be tile_moved")
	assert_eq(first_event.get("from"), Vector2i(1, 0), "First move should be from (1,0)")
	assert_eq(first_event.get("to"), Vector2i(1, 1), "First move should be to (1,1)")


func test_gravity_determinism() -> void:
	var board_a := BoardState.new(Vector2i(5, 5))
	var board_b := BoardState.new(Vector2i(5, 5))
	var rng := SeededRng.new()
	rng.reseed(42)
	var spawn_table := SpawnTableResource.new()
	spawn_table.allowed_tiers = [1, 2, 3]
	spawn_table.weights = [3, 2, 1]
	var resolver := SpawnResolver.new()
	resolver.populate_board(board_a, rng, spawn_table)
	rng.reseed(42)
	resolver.populate_board(board_b, rng, spawn_table)

	# Remove some tiles to create gravity work
	board_a.remove_tile(Vector2i(2, 4))
	board_a.remove_tile(Vector2i(2, 3))
	board_b.remove_tile(Vector2i(2, 4))
	board_b.remove_tile(Vector2i(2, 3))

	var physics_a := BoardPhysics.new()
	var physics_b := BoardPhysics.new()
	physics_a.resolve_gravity(board_a)
	physics_b.resolve_gravity(board_b)

	assert_eq(board_a.compute_hash(), board_b.compute_hash(), "Identical boards should produce identical gravity results")
	assert_eq(physics_a.last_move_events.size(), physics_b.last_move_events.size(), "Should have same number of move events")


func test_gravity_max_rounds_safety() -> void:
	# Create a circular gravity configuration (cycle)
	var board := BoardState.new(Vector2i(2, 2))
	board.get_cell(Vector2i(0, 0)).gravity_direction = Vector2i.RIGHT
	board.get_cell(Vector2i(1, 0)).gravity_direction = Vector2i.DOWN
	board.get_cell(Vector2i(1, 1)).gravity_direction = Vector2i.LEFT
	board.get_cell(Vector2i(0, 1)).gravity_direction = Vector2i.UP
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))

	var physics := BoardPhysics.new()
	# This should terminate (not hang) due to MAX_SETTLE_ROUNDS
	var moves := physics.resolve_gravity(board)
	assert_true(moves >= 0, "Gravity with cycle should terminate safely")


# ---- Phase 4: Pipeline Tests ----


func test_effect_planning() -> void:
	var classified: Array[Dictionary] = [
		{
			"semantic_type": &"base_match",
			"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i],
			"match_group": &"debug_tier_1",
			"tier": 1,
		},
	]
	var planner := EffectPlanner.new()
	var plan := planner.build_base_plan(classified)
	# Merge mechanic: 3 cells → 2 removes + 1 upgrade
	assert_eq(plan.size(), 3, "Should plan 3 effects (2 removes + 1 upgrade)")
	var removes := 0
	var upgrades := 0
	for entry in plan:
		if entry.get("effect") == EffectPlanner.EFFECT_REMOVE:
			removes += 1
		elif entry.get("effect") == EffectPlanner.EFFECT_UPGRADE:
			upgrades += 1
	assert_eq(removes, 2, "Should have 2 remove effects")
	assert_eq(upgrades, 1, "Should have 1 upgrade effect")
	# Survivor should be the last cell (2,0)
	assert_eq(plan[2].get("cell"), Vector2i(2, 0), "Upgrade should target last cell in match")


func test_conflict_resolution() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))

	var plan: Array[Dictionary] = [
		{"effect": EffectPlanner.EFFECT_REMOVE, "cell": Vector2i(0, 0), "reason": &"test"},
		{"effect": EffectPlanner.EFFECT_REMOVE, "cell": Vector2i(0, 0), "reason": &"test_dup"},
	]

	var resolver := ConflictResolver.new()
	var resolved := resolver.resolve(plan, board)
	assert_eq(resolved.size(), 1, "Should deduplicate to 1 removal")


func test_effect_resolution() -> void:
	var board := BoardState.new(Vector2i(5, 5))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(2))

	var plan: Array[Dictionary] = [
		{"effect": EffectPlanner.EFFECT_REMOVE, "cell": Vector2i(0, 0), "reason": &"test"},
		{"effect": EffectPlanner.EFFECT_UPGRADE, "cell": Vector2i(1, 0)},
	]

	var event_log := EventLog.new()
	var resolver := EffectResolver.new()
	var removed := resolver.apply(board, plan, event_log)

	assert_eq(removed, 1, "Should remove 1 tile")
	assert_true(board.get_tile(Vector2i(0, 0)) == null, "Cell should be empty after removal")
	assert_eq(board.get_tile(Vector2i(1, 0)).tier, 3, "Tile should be upgraded to tier 3")
	assert_eq(resolver.last_remove_events.size(), 1, "Should have 1 remove event")
	assert_eq(resolver.last_upgrade_events.size(), 1, "Should have 1 upgrade event")


func test_gradient_strength_without_texture() -> void:
	var cut = GemCutGenerators.generate_from_spec_id(&"cushion")
	var base_visual := GemVisualResource.new()
	base_visual.base_color = Color(0.32, 0.6, 0.82, 1)
	base_visual.gradient_color = Color(0.9, 0.2, 0.35, 1)
	base_visual.gradient_strength = 0.0

	var gradient_visual := GemVisualResource.new()
	gradient_visual.base_color = base_visual.base_color
	gradient_visual.gradient_color = base_visual.gradient_color
	gradient_visual.gradient_strength = 0.7

	var base_colors := GemRenderer.compute_all_facet_colors(cut, base_visual)
	var gradient_colors := GemRenderer.compute_all_facet_colors(cut, gradient_visual)
	var changed := false
	for i in base_colors.size():
		var a := base_colors[i]
		var b := gradient_colors[i]
		if absf(a.r - b.r) > 0.0001 or absf(a.g - b.g) > 0.0001 or absf(a.b - b.b) > 0.0001:
			changed = true
			break
	assert_true(changed, "Gradient strength should affect non-textured gems")


func test_spawn_integer_weighted_pick() -> void:
	var rng := SeededRng.new()
	rng.reseed(42)
	var spawn_table := SpawnTableResource.new()
	spawn_table.allowed_tiers = [1, 2, 3]
	spawn_table.weights = [6, 3, 1]  # 60% T1, 30% T2, 10% T3

	var resolver := SpawnResolver.new()
	var counts := {1: 0, 2: 0, 3: 0}
	for i in 1000:
		var board := BoardState.new(Vector2i(1, 1))
		resolver.populate_board(board, rng, spawn_table)
		var tile := board.get_tile(Vector2i(0, 0))
		counts[tile.tier] += 1

	# T1 should be most common, T3 least common
	assert_true(counts[1] > counts[2], "T1 should be more common than T2")
	assert_true(counts[2] > counts[3], "T2 should be more common than T3")
	assert_true(counts[1] > 400, "T1 should appear >400 times out of 1000 (got %d)" % counts[1])


func test_spawn_integer_determinism() -> void:
	var spawn_table := SpawnTableResource.new()
	spawn_table.allowed_tiers = [1, 2, 3]
	spawn_table.weights = [3, 2, 1]

	var board_a := BoardState.new(Vector2i(3, 3))
	var board_b := BoardState.new(Vector2i(3, 3))
	var rng_a := SeededRng.new()
	var rng_b := SeededRng.new()
	rng_a.reseed(42)
	rng_b.reseed(42)

	var resolver := SpawnResolver.new()
	resolver.populate_board(board_a, rng_a, spawn_table)
	resolver.populate_board(board_b, rng_b, spawn_table)

	assert_eq(board_a.compute_hash(), board_b.compute_hash(), "Same seed should produce identical boards")


func test_event_timeline_structure() -> void:
	var board := BoardState.new(Vector2i(5, 1))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(2, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(3, 0), TileState.from_debug_tier(2))
	board.set_tile(Vector2i(4, 0), TileState.from_debug_tier(3))

	var rng := SeededRng.new()
	rng.reseed(42)
	var event_log := EventLog.new()
	var spawn_table := SpawnTableResource.new()
	spawn_table.allowed_tiers = [1, 2, 3]
	spawn_table.weights = [3, 2, 1]

	var tc := TurnController.new()
	var timeline := tc.execute_turn(board, rng, spawn_table, event_log)

	assert_true(not timeline.is_empty(), "Timeline should have at least 1 cascade step")
	var step: Dictionary = timeline.cascade_steps[0]
	assert_true(step.has("match_events"), "Step should have match_events")
	assert_true(step.has("remove_events"), "Step should have remove_events")
	assert_true(step.has("gravity_events"), "Step should have gravity_events")
	assert_true(step.has("spawn_events"), "Step should have spawn_events")
	assert_true(step.has("board_hash"), "Step should have board_hash")
	assert_true(step["remove_events"].size() >= 2, "Should remove at least 2 tiles")

	var stats := timeline.to_stats()
	assert_true(stats["total_matches"] >= 1, "Stats should report at least 1 match")


func test_turn_controller() -> void:
	var board := BoardState.new(Vector2i(5, 1))
	board.set_tile(Vector2i(0, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(1, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(2, 0), TileState.from_debug_tier(1))
	board.set_tile(Vector2i(3, 0), TileState.from_debug_tier(2))
	board.set_tile(Vector2i(4, 0), TileState.from_debug_tier(3))

	var rng := SeededRng.new()
	rng.reseed(42)
	var event_log := EventLog.new()
	var spawn_table := SpawnTableResource.new()
	spawn_table.allowed_tiers = [1, 2, 3]
	spawn_table.weights = [3, 2, 1]

	var tc := TurnController.new()
	var timeline := tc.execute_turn(board, rng, spawn_table, event_log)

	var stats := timeline.to_stats()
	assert_true(stats["total_matches"] >= 1, "Should find at least 1 match")
	assert_true(stats["total_tiles_removed"] >= 2, "Should remove at least 2 tiles")


func test_seeded_rng_determinism() -> void:
	var rng_a := SeededRng.new()
	var rng_b := SeededRng.new()
	rng_a.reseed(12345)
	rng_b.reseed(12345)

	var values_a: Array[int] = []
	var values_b: Array[int] = []
	for i in 10:
		values_a.append(rng_a.randi_range(0, 100))
		values_b.append(rng_b.randi_range(0, 100))

	assert_eq(values_a, values_b, "Same seed should produce same sequence")


# ---- Phase 6: Verification Tests ----


func test_replay_determinism() -> void:
	var hashes_a := _run_determinism_sequence(1001)
	var hashes_b := _run_determinism_sequence(1001)
	assert_eq(hashes_a, hashes_b, "Same seed + actions should produce identical board hashes")


func _run_determinism_sequence(run_seed: int) -> Array[int]:
	var board := BoardState.new(Vector2i(8, 8))
	var rng := SeededRng.new()
	rng.reseed(run_seed)
	var event_log := EventLog.new()
	var spawn_table := SpawnTableResource.new()
	spawn_table.allowed_tiers = [1, 2, 3, 4]
	spawn_table.weights = [4, 3, 2, 1]
	var tc := TurnController.new()
	tc.spawn_resolver.populate_board(board, rng, spawn_table)

	var hashes: Array[int] = [board.compute_hash()]
	# Simulate 5 auto-resolve turns
	for i in 5:
		tc.execute_turn(board, rng, spawn_table, event_log)
		hashes.append(board.compute_hash())
	return hashes


func test_board_validator_cycle_detection() -> void:
	var layout := BoardLayoutResource.new()
	layout.board_size = Vector2i(2, 2)
	layout.set_gravity(Vector2i(0, 0), Vector2i.RIGHT)
	layout.set_gravity(Vector2i(1, 0), Vector2i.DOWN)
	layout.set_gravity(Vector2i(1, 1), Vector2i.LEFT)
	layout.set_gravity(Vector2i(0, 1), Vector2i.UP)

	var validator := BoardValidator.new()
	var issues := validator.validate(layout)
	var has_cycle_error := false
	for issue in issues:
		if "cycle" in issue.to_lower():
			has_cycle_error = true
			break
	assert_true(has_cycle_error, "Validator should detect gravity cycle")


func test_board_validator_portal_validation() -> void:
	var layout := BoardLayoutResource.new()
	layout.board_size = Vector2i(4, 4)
	layout.add_portal(Vector2i(0, 0), Vector2i.DOWN, Vector2i(10, 10))  # Out of bounds target

	var validator := BoardValidator.new()
	var issues := validator.validate(layout)
	var has_portal_error := false
	for issue in issues:
		if "portal" in issue.to_lower() and "out of bounds" in issue.to_lower():
			has_portal_error = true
			break
	assert_true(has_portal_error, "Validator should detect out-of-bounds portal target")


# ---- Assertion helpers ----


func assert_true(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s" % msg)


func assert_false(condition: bool, msg: String) -> void:
	assert_true(not condition, msg)


func assert_eq(a: Variant, b: Variant, msg: String) -> void:
	if a == b:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s (got %s, expected %s)" % [msg, str(a), str(b)])
