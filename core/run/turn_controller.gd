class_name TurnController
extends RefCounted

## Owns the single-turn resolution loop:
## swap → detect → classify → plan → conflict → resolve → physics → spawn → cascade
##
## This is the core gameplay pipeline. RunController delegates to this for turn execution.
##
## Two usage modes:
##   1. Monolithic: execute_turn() runs the full cascade loop at once (tests, initial board).
##   2. Incremental: prepare_turn() + step_cascade() loop — one cascade step per call,
##      allowing callers to build the authoritative timeline in smaller chunks when desired.

var match_detector := MatchDetector.new()
var match_classifier := MatchClassifier.new()
var effect_planner := EffectPlanner.new()
var conflict_resolver := ConflictResolver.new()
var effect_resolver := EffectResolver.new()
var board_physics := BoardPhysics.new()
var spawn_resolver := SpawnResolver.new()

## Maximum cascade depth to prevent infinite loops.
const MAX_CASCADE_DEPTH := 50

## Maximum upgrade chain depth within a single cascade step.
## Upgrade chains re-match after upgrades but before gravity.
const MAX_CHAIN_DEPTH := 20

# ---- Incremental cascade state ----

var _inc_board: BoardState
var _inc_rng: SeededRng
var _inc_spawn_table: SpawnTableResource
var _inc_event_log: EventLog
var _inc_swap_cells: Array[Vector2i] = []
var _inc_cascade_depth: int = 0
var _inc_active: bool = false


## Prepares for incremental cascade resolution.
## Call step_cascade() repeatedly until it returns null.
func prepare_turn(
	board: BoardState,
	rng: SeededRng,
	spawn_table: SpawnTableResource,
	event_log: EventLog,
	swap_cells: Array[Vector2i] = [],
) -> void:
	_inc_board = board
	_inc_rng = rng
	_inc_spawn_table = spawn_table
	_inc_event_log = event_log
	_inc_swap_cells = swap_cells
	_inc_cascade_depth = 0
	_inc_active = true


## Returns true if the incremental cascade still has potential work to do.
func is_cascade_active() -> bool:
	return _inc_active


## Executes one cascade step: detect → classify → plan → resolve → chain → gravity → spawn.
## Returns the step Dictionary (same format as EventTimeline.cascade_steps entries),
## or null if no matches remain (turn is complete).
func step_cascade() -> Variant:
	if not _inc_active or _inc_cascade_depth >= MAX_CASCADE_DEPTH:
		_inc_active = false
		return null

	# Step 1: Detect matches
	var raw_matches := match_detector.find_matches(_inc_board)
	if raw_matches.is_empty():
		_inc_active = false
		return null

	# Step 2: Classify matches
	var classified := match_classifier.classify(raw_matches)
	if classified.is_empty():
		_inc_active = false
		return null

	# Build match events for timeline
	var match_events: Array[Dictionary] = []
	for m in classified:
		match_events.append({
			"type": &"match_formed",
			"cells": m.get("cells", []),
			"match_group": m.get("match_group", &""),
			"tier": m.get("tier", 0),
			"semantic_type": m.get("semantic_type", &""),
		})

	# Step 3: Plan effects (swap_cells only applies to the first cascade)
	var active_swap: Array[Vector2i] = []
	if _inc_cascade_depth == 0:
		active_swap = _inc_swap_cells
	var effect_plan := effect_planner.build_base_plan(classified, active_swap)

	# Step 4: Resolve conflicts
	effect_plan = conflict_resolver.resolve(effect_plan, _inc_board)

	# Step 5: Apply effects (mutate board)
	effect_resolver.apply(_inc_board, effect_plan, _inc_event_log)
	var first_round_effects := _snapshot_last_effect_events()

	# Collect first round into chain_steps
	var chain_steps: Array[Dictionary] = []
	chain_steps.append({
		"match_events": match_events,
		"remove_events": first_round_effects["remove_events"],
		"upgrade_events": first_round_effects["upgrade_events"],
	})

	# Aggregate flat event arrays for stats and timeline consumers that still read
	# the top-level step arrays.
	var all_match_events: Array[Dictionary] = []
	all_match_events.append_array(match_events)
	var all_remove_events: Array[Dictionary] = []
	all_remove_events.append_array(first_round_effects["remove_events"])
	var all_upgrade_events: Array[Dictionary] = []
	all_upgrade_events.append_array(first_round_effects["upgrade_events"])

	# Step 5b: Upgrade chain loop — re-match after upgrades, before gravity.
	# An upgrade may land next to same-tier tiles, forming a new match instantly.
	var chain_depth := 0
	while chain_depth < MAX_CHAIN_DEPTH:
		var chain_matches := match_detector.find_matches(_inc_board)
		if chain_matches.is_empty():
			break
		var chain_classified := match_classifier.classify(chain_matches)
		if chain_classified.is_empty():
			break

		var chain_match_events: Array[Dictionary] = []
		for m in chain_classified:
			chain_match_events.append({
				"type": &"match_formed",
				"cells": m.get("cells", []),
				"match_group": m.get("match_group", &""),
				"tier": m.get("tier", 0),
				"semantic_type": m.get("semantic_type", &""),
			})

		# Chain matches never use swap_cells (those only affect the initial match)
		var chain_plan := effect_planner.build_base_plan(chain_classified)
		chain_plan = conflict_resolver.resolve(chain_plan, _inc_board)
		effect_resolver.apply(_inc_board, chain_plan, _inc_event_log)
		var chain_effects := _snapshot_last_effect_events()

		chain_steps.append({
			"match_events": chain_match_events,
			"remove_events": chain_effects["remove_events"],
			"upgrade_events": chain_effects["upgrade_events"],
		})
		all_match_events.append_array(chain_match_events)
		all_remove_events.append_array(chain_effects["remove_events"])
		all_upgrade_events.append_array(chain_effects["upgrade_events"])

		chain_depth += 1
		_inc_event_log.push(&"upgrade_chain", {
			"cascade_depth": _inc_cascade_depth,
			"chain_depth": chain_depth,
			"matches_found": chain_classified.size(),
		})

	# Step 6: Gravity collapse (iterative settling)
	board_physics.resolve_gravity(_inc_board)

	# Step 7: Refill empty cells (spawn-entry-aware)
	var spawn_cells := board_physics.find_spawn_eligible_cells(_inc_board)
	spawn_resolver.refill_spawn_entries(_inc_board, _inc_rng, _inc_spawn_table, spawn_cells)

	# Build cascade step
	var step := {
		"cascade_index": _inc_cascade_depth,
		"chain_steps": chain_steps,
		"match_events": all_match_events,
		"remove_events": all_remove_events,
		"upgrade_events": all_upgrade_events,
		"gravity_events": board_physics.last_move_events.duplicate(),
		"spawn_events": spawn_resolver.last_spawn_events.duplicate(),
		"board_hash": _inc_board.compute_hash(),
	}

	_inc_cascade_depth += 1

	_inc_event_log.push(&"cascade_step", {
		"depth": _inc_cascade_depth,
		"matches_found": classified.size(),
		"tiles_removed": all_remove_events.size(),
	})

	return step


# ---- Monolithic API (backward compat for tests and initial board resolution) ----


## Executes a full turn: resolve all matches, apply effects, cascade until stable.
## Returns an EventTimeline with structured per-tile events for animation.
##
## swap_cells: optional [from, to] pair from a player swap. Passed to the
## effect planner for the first cascade only so the upgrade survivor spawns
## at the swapped cell rather than the default bottom-right position.
func execute_turn(
	board: BoardState,
	rng: SeededRng,
	spawn_table: SpawnTableResource,
	event_log: EventLog,
	swap_cells: Array[Vector2i] = [],
) -> EventTimeline:
	prepare_turn(board, rng, spawn_table, event_log, swap_cells)
	var timeline := EventTimeline.new()

	while is_cascade_active():
		var step = step_cascade()
		if step == null:
			break
		timeline.add_cascade_step(step)

	event_log.push(&"turn_completed", timeline.to_stats())

	return timeline

func _snapshot_last_effect_events() -> Dictionary:
	return {
		"remove_events": effect_resolver.last_remove_events.duplicate(),
		"upgrade_events": effect_resolver.last_upgrade_events.duplicate(),
	}
