extends Node

## Headless simulation for balance testing.
## Run: godot --headless res://tests/test_simulation.tscn
##
## Runs N games with a greedy AI that evaluates all possible swaps and picks
## the best one (5+ > 4 > 3, ties broken by lowest position on the grid).
## Prints per-run and aggregate statistics.

const NUM_RUNS := 10  ## Increase for more statistical confidence (100+ takes minutes in GDScript)
const MAX_TOTAL_MOVES := 1000
const BOARD_SIZE := Vector2i(8, 8)
const STARTING_MOVES := 20
const BASE_SEED := 1001

var _match_detector := MatchDetector.new()
var _match_classifier := MatchClassifier.new()


func _ready() -> void:
	print("\n=== Facets Simulation (%d runs) ===\n" % NUM_RUNS)

	var all_stats: Array[Dictionary] = []

	for run_idx: int in NUM_RUNS:
		var stats: Dictionary = _run_single_game(run_idx)
		all_stats.append(stats)

	_print_aggregate(all_stats)
	get_tree().quit()


func _run_single_game(run_idx: int) -> Dictionary:
	var controller := RunController.new()
	var seed_val := BASE_SEED + run_idx

	var t_start := Time.get_ticks_msec()
	controller.start_new_run({
		"seed": seed_val,
		"starting_moves": STARTING_MOVES,
		"board_size": BOARD_SIZE,
	})
	var t_init := Time.get_ticks_msec()

	var stats: Dictionary = {
		"seed": seed_val,
		"moves_spent": 0,
		"matches_by_type": {
			&"base_match": 0,
			&"match_4": 0,
			&"match_5_plus": 0,
			&"match_lt": 0,
		},
		"matches_by_tier": {},
		"total_tiles_removed": 0,
		"total_cascades": 0,
		"total_chain_rounds": 0,
		"highest_tier_seen": 0,
		"moves_awarded": 0,
		"moves_saved": 0,
	}

	var total_moves_used := 0
	var time_finding := 0
	var time_executing := 0
	var time_stats := 0

	while controller.run_state.moves_remaining > 0 and total_moves_used < MAX_TOTAL_MOVES:
		var t0 := Time.get_ticks_usec()
		var best_swap: Array = _find_best_swap(controller.run_state.board)
		var t1 := Time.get_ticks_usec()
		if best_swap.is_empty():
			time_finding += t1 - t0
			break

		var timeline: EventTimeline = controller.attempt_swap(best_swap[0], best_swap[1])
		var t2 := Time.get_ticks_usec()
		if timeline == null:
			break

		_accumulate_stats(stats, timeline)
		var t3 := Time.get_ticks_usec()

		time_finding += t1 - t0
		time_executing += t2 - t1
		time_stats += t3 - t2
		total_moves_used += 1

		# Per-move timing for first 5 moves of first run
		if run_idx == 0 and total_moves_used <= 5:
			print("    move %d: find=%dms exec=%dms cascades=%d" % [
				total_moves_used, (t1 - t0) / 1000, (t2 - t1) / 1000,
				timeline.cascade_steps.size(),
			])

	var t_end := Time.get_ticks_msec()

	stats["moves_spent"] = total_moves_used
	stats["final_moves_remaining"] = controller.run_state.moves_remaining

	print("  Run %3d | seed=%d | moves=%d | total=%dms | init=%dms | find=%dms | exec=%dms | stats=%dms" % [
		run_idx, seed_val, total_moves_used,
		t_end - t_start, t_init - t_start,
		time_finding / 1000, time_executing / 1000, time_stats / 1000,
	])

	return stats


func _find_best_swap(board: BoardState) -> Array:
	var best_swap: Array = []
	var best_score := -1
	var best_row := -1
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN]
	var last_checked_row := -1

	for cell: Vector2i in board.all_cells():
		if cell.y != last_checked_row:
			if best_score == 3 and best_row >= last_checked_row and last_checked_row >= 0:
				break
			last_checked_row = cell.y

		var tile_a: TileState = board.get_tile(cell)
		if tile_a == null:
			continue

		for dir: Vector2i in directions:
			var neighbor := Vector2i(cell.x + dir.x, cell.y + dir.y)
			if not board.in_bounds(neighbor) or board.is_blocked(neighbor):
				continue
			var tile_b: TileState = board.get_tile(neighbor)
			if tile_b == null:
				continue
			# Swapping identical match groups can never create a new match
			if tile_a.get_match_group() == tile_b.get_match_group():
				continue

			board.swap_cells(cell, neighbor)
			var matches: Array[Dictionary] = _match_detector.find_matches(board)
			board.swap_cells(cell, neighbor)

			if matches.is_empty():
				continue

			var classified: Array[Dictionary] = _match_classifier.classify(matches)
			var score := 0
			var lowest_row := 0
			for m: Dictionary in classified:
				var st: StringName = m.get("semantic_type", &"base_match")
				var match_score: int = _score_for_type(st)
				if match_score > score:
					score = match_score
				var match_cells: Array = m.get("cells", [])
				for c: Vector2i in match_cells:
					if c.y > lowest_row:
						lowest_row = c.y

			if score > best_score or (score == best_score and lowest_row > best_row):
				best_score = score
				best_row = lowest_row
				best_swap = [cell, neighbor]

	return best_swap


func _score_for_type(semantic_type: StringName) -> int:
	match semantic_type:
		&"match_lt", &"match_5_plus":
			return 3
		&"match_4":
			return 2
		_:
			return 1


func _compute_move_delta(timeline: EventTimeline) -> int:
	var best: StringName = &"base_match"
	for step: Dictionary in timeline.cascade_steps:
		var match_events: Array = step.get("match_events", [])
		for event: Dictionary in match_events:
			var st: StringName = event.get("semantic_type", &"base_match")
			if st == &"match_5_plus" or st == &"match_lt":
				return 1
			if st == &"match_4":
				best = st
	if best == &"match_4":
		return 0
	return -1


func _accumulate_stats(stats: Dictionary, timeline: EventTimeline) -> void:
	for step: Dictionary in timeline.cascade_steps:
		stats["total_cascades"] += 1

		var chain_steps: Array = step.get("chain_steps", [])
		if chain_steps.size() > 1:
			stats["total_chain_rounds"] += chain_steps.size() - 1

		var match_events: Array = step.get("match_events", [])
		for event: Dictionary in match_events:
			var st: StringName = event.get("semantic_type", &"base_match")
			var tier: int = event.get("tier", 0)

			if stats["matches_by_type"].has(st):
				stats["matches_by_type"][st] += 1
			else:
				stats["matches_by_type"][st] = 1

			if not stats["matches_by_tier"].has(tier):
				stats["matches_by_tier"][tier] = 0
			stats["matches_by_tier"][tier] += 1

			if tier > stats["highest_tier_seen"]:
				stats["highest_tier_seen"] = tier

		stats["total_tiles_removed"] += step.get("remove_events", []).size()

	var delta: int = _compute_move_delta(timeline)
	if delta == 1:
		stats["moves_awarded"] += 1
	elif delta == 0:
		stats["moves_saved"] += 1


func _print_run_summary(run_idx: int, stats: Dictionary) -> void:
	print("  Run %3d | seed=%d | moves=%d | removed=%d | highest_tier=%d | cascades=%d | chains=%d" % [
		run_idx, stats["seed"], stats["moves_spent"],
		stats["total_tiles_removed"], stats["highest_tier_seen"],
		stats["total_cascades"], stats["total_chain_rounds"],
	])


func _print_aggregate(all_stats: Array[Dictionary]) -> void:
	var n := all_stats.size()
	if n == 0:
		print("No runs completed.")
		return

	var total_moves := 0
	var total_removed := 0
	var total_cascades := 0
	var total_chains := 0
	var total_awarded := 0
	var total_saved := 0
	var highest_tier_ever := 0
	var agg_match_types: Dictionary = {}
	var agg_match_tiers: Dictionary = {}
	var moves_list: Array[int] = []

	for stats: Dictionary in all_stats:
		var m: int = stats["moves_spent"]
		total_moves += m
		moves_list.append(m)
		total_removed += stats["total_tiles_removed"]
		total_cascades += stats["total_cascades"]
		total_chains += stats["total_chain_rounds"]
		total_awarded += stats["moves_awarded"]
		total_saved += stats["moves_saved"]
		if stats["highest_tier_seen"] > highest_tier_ever:
			highest_tier_ever = stats["highest_tier_seen"]

		var by_type: Dictionary = stats["matches_by_type"]
		for key: StringName in by_type:
			if not agg_match_types.has(key):
				agg_match_types[key] = 0
			agg_match_types[key] += by_type[key]

		var by_tier: Dictionary = stats["matches_by_tier"]
		for key: int in by_tier:
			if not agg_match_tiers.has(key):
				agg_match_tiers[key] = 0
			agg_match_tiers[key] += by_tier[key]

	moves_list.sort()
	var median_moves: int = moves_list[n / 2]
	var min_moves: int = moves_list[0]
	var max_moves: int = moves_list[n - 1]

	print("\n=== Aggregate Statistics (%d runs) ===" % n)
	print("")
	print("  Moves per run:")
	print("    Mean:   %.1f" % [float(total_moves) / n])
	print("    Median: %d" % median_moves)
	print("    Min:    %d" % min_moves)
	print("    Max:    %d" % max_moves)
	print("")
	print("  Move economy:")
	print("    Moves awarded (+1 from 5+/LT): %d (%.1f per run)" % [
		total_awarded, float(total_awarded) / n])
	print("    Moves saved (free from 4x):    %d (%.1f per run)" % [
		total_saved, float(total_saved) / n])
	print("")
	print("  Matches by type (total across all runs):")
	for key: StringName in [&"base_match", &"match_4", &"match_5_plus", &"match_lt"]:
		var count: int = agg_match_types.get(key, 0)
		print("    %-14s %6d  (%.1f per run)" % [String(key), count, float(count) / n])
	print("")
	print("  Matches by tier:")
	var tier_keys: Array = agg_match_tiers.keys()
	tier_keys.sort()
	for tier: int in tier_keys:
		var count: int = agg_match_tiers[tier]
		print("    T%-2d  %6d  (%.1f per run)" % [tier, count, float(count) / n])
	print("")
	print("  Highest tier reached across all runs: T%d" % highest_tier_ever)
	print("  Avg tiles removed per run: %.1f" % [float(total_removed) / n])
	print("  Avg cascades per run:      %.1f" % [float(total_cascades) / n])
	print("  Avg chain rounds per run:  %.1f" % [float(total_chains) / n])
	print("")
