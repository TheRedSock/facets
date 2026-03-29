class_name RunController
extends RefCounted

signal run_state_changed(run_state: RunState)
signal board_changed(board: BoardState)
signal turn_resolved(timeline: EventTimeline)

var run_state := RunState.new()
var rng := SeededRng.new()
var event_log := EventLog.new()
var turn_controller := TurnController.new()

## Default spawn table used when no specific table is provided.
var _default_spawn_table: SpawnTableResource = null


func _init() -> void:
	_default_spawn_table = _create_default_spawn_table()


func start_new_run(config: Dictionary = {}) -> void:
	var merged_config := GameConfig.default_run_config()
	for key in config.keys():
		merged_config[key] = config[key]

	run_state = RunState.new()
	run_state.board_size = merged_config["board_size"]
	run_state.visible_tiers = merged_config["visible_tiers"]
	run_state.moves_remaining = merged_config["starting_moves"]
	run_state.seed = merged_config["seed"]
	run_state.board = BoardState.new(run_state.board_size)

	# Apply board layout if provided
	var layout: BoardLayoutResource = merged_config.get("board_layout", null)
	if layout != null:
		run_state.board.apply_layout(layout)

	# Set up spawn table
	var spawn_table: SpawnTableResource = merged_config.get("spawn_table", null)
	if spawn_table == null:
		spawn_table = _default_spawn_table
	run_state.spawn_table = spawn_table

	rng.reseed(run_state.seed)
	event_log.clear()

	# Populate board using spawn table
	turn_controller.spawn_resolver.populate_board(run_state.board, rng, spawn_table)

	# Resolve any initial matches so the board starts in a stable state.
	# This runs the cascade loop (detect → clear → gravity → spawn → repeat)
	# until no matches remain. Does not consume player moves.
	var _initial_timeline := turn_controller.execute_turn(
		run_state.board, rng, spawn_table, event_log
	)

	ReplayService.begin(run_state.seed)

	board_changed.emit(run_state.board)
	run_state_changed.emit(run_state)


func reroll_board(seed_override: int = -1) -> void:
	var next_seed := seed_override if seed_override >= 0 else run_state.seed + 1
	start_new_run({
		"board_size": run_state.board_size,
		"visible_tiers": run_state.visible_tiers,
		"starting_moves": run_state.moves_remaining,
		"seed": next_seed,
		"spawn_table": run_state.spawn_table,
	})


## Attempts a swap between two adjacent cells and resolves the turn.
## Returns the EventTimeline, or null if the swap was invalid.
func attempt_swap(cell_a: Vector2i, cell_b: Vector2i) -> EventTimeline:
	if not run_state.board.in_bounds(cell_a) or not run_state.board.in_bounds(cell_b):
		return null

	if run_state.moves_remaining <= 0:
		return null

	# Perform the swap
	run_state.board.swap_cells(cell_a, cell_b)

	# Check if the swap creates any matches
	var test_matches := turn_controller.match_detector.find_matches(run_state.board)
	if test_matches.is_empty():
		# No matches — revert the swap
		run_state.board.swap_cells(cell_a, cell_b)
		return null

	# Valid swap — record for replay before executing the turn
	ReplayService.record_action(&"swap", {
		"a_x": cell_a.x, "a_y": cell_a.y,
		"b_x": cell_b.x, "b_y": cell_b.y,
	})

	# Execute the full turn (cascade loop).
	# Pass the swap cells so the first cascade upgrades at the swapped position.
	var spawn_table := run_state.spawn_table if run_state.spawn_table != null else _default_spawn_table
	var swap_pair: Array[Vector2i] = [cell_a, cell_b]
	var timeline := turn_controller.execute_turn(
		run_state.board, rng, spawn_table, event_log, swap_pair
	)

	# Adjust moves based on the best match type in the first cascade:
	#   base_match (3)  → costs 1 move
	#   match_4   (4)   → free (no move cost)
	#   match_5_plus / match_lt (5+) → awards 1 extra move
	run_state.moves_remaining += _compute_move_delta(timeline)

	# Record checkpoint for anti-cheat verification
	ReplayService.record_checkpoint(run_state.board.compute_hash())

	# NOTE: Do NOT emit board_changed here — the timeline animation handles
	# the visual transition from pre-swap to post-cascade state.
	# board_changed is only for full rebuilds (start_new_run, reroll_board).
	run_state_changed.emit(run_state)

	return timeline


## Debug: evaluate the current board without consuming a move.
func evaluate_current_board() -> Array[Dictionary]:
	return turn_controller.evaluate_board(run_state.board, event_log)


## Debug: execute a full turn resolution on the current board (with cascades).
func resolve_current_board() -> EventTimeline:
	var spawn_table := run_state.spawn_table if run_state.spawn_table != null else _default_spawn_table
	var timeline := turn_controller.execute_turn(
		run_state.board, rng, spawn_table, event_log
	)
	board_changed.emit(run_state.board)
	run_state_changed.emit(run_state)
	turn_resolved.emit(timeline)
	return timeline


func get_run_state() -> RunState:
	return run_state


func get_board() -> BoardState:
	return run_state.board


## Creates a default spawn table with weighted T1-T4 distribution.
## Biased toward lower tiers to match expected exponential distribution.
func _create_default_spawn_table() -> SpawnTableResource:
	var table := SpawnTableResource.new()
	table.table_id = &"default_phase1"
	table.allowed_tiers = [1, 2, 3, 4]
	table.weights = [4, 3, 2, 1]  # T1 is 4x more likely than T4
	return table


## Computes the move delta from the best match across all cascade steps.
## The highest match type found anywhere in the turn determines the cost:
##   base_match (3-match)  → -1  (costs a move)
##   match_4    (4-match)  →  0  (free move)
##   match_5_plus / match_lt (5+) → +1  (awards a move)
func _compute_move_delta(timeline: EventTimeline) -> int:
	if timeline.cascade_steps.is_empty():
		return -1
	var best := &"base_match"
	for step in timeline.cascade_steps:
		var match_events: Array = step.get("match_events", [])
		for event in match_events:
			var st: StringName = event.get("semantic_type", &"base_match")
			if st == &"match_5_plus" or st == &"match_lt":
				return 1  # Can't do better — early out
			if st == &"match_4":
				best = st
	if best == &"match_4":
		return 0
	return -1
