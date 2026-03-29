class_name TurnController
extends RefCounted

## Owns the single-turn resolution loop:
## swap → detect → classify → plan → conflict → resolve → physics → spawn → cascade
##
## This is the core gameplay pipeline. RunController delegates to this for turn execution.
## Returns a structured EventTimeline for rendering consumption.

signal turn_completed(timeline: EventTimeline)
signal cascade_step_completed(step: int, matches_found: int)

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
	var timeline := EventTimeline.new()
	var cascade_depth := 0

	while cascade_depth < MAX_CASCADE_DEPTH:
		# Step 1: Detect matches
		var raw_matches := match_detector.find_matches(board)
		if raw_matches.is_empty():
			break

		# Step 2: Classify matches
		var classified := match_classifier.classify(raw_matches)
		if classified.is_empty():
			break

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
		if cascade_depth == 0:
			active_swap = swap_cells
		var effect_plan := effect_planner.build_base_plan(classified, active_swap)

		# Step 4: Resolve conflicts
		effect_plan = conflict_resolver.resolve(effect_plan, board)

		# Step 5: Apply effects (mutate board)
		effect_resolver.apply(board, effect_plan, event_log)

		# Collect first round into chain_steps
		var chain_steps: Array[Dictionary] = []
		chain_steps.append({
			"match_events": match_events,
			"remove_events": effect_resolver.last_remove_events.duplicate(),
			"upgrade_events": effect_resolver.last_upgrade_events.duplicate(),
		})

		# Aggregate flat event arrays (for backward compat and stats)
		var all_match_events: Array[Dictionary] = match_events.duplicate()
		var all_remove_events: Array[Dictionary] = effect_resolver.last_remove_events.duplicate()
		var all_upgrade_events: Array[Dictionary] = effect_resolver.last_upgrade_events.duplicate()

		# Step 5b: Upgrade chain loop — re-match after upgrades, before gravity.
		# An upgrade may land next to same-tier tiles, forming a new match instantly.
		var chain_depth := 0
		while chain_depth < MAX_CHAIN_DEPTH:
			var chain_matches := match_detector.find_matches(board)
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
			chain_plan = conflict_resolver.resolve(chain_plan, board)
			effect_resolver.apply(board, chain_plan, event_log)

			chain_steps.append({
				"match_events": chain_match_events,
				"remove_events": effect_resolver.last_remove_events.duplicate(),
				"upgrade_events": effect_resolver.last_upgrade_events.duplicate(),
			})
			all_match_events.append_array(chain_match_events)
			all_remove_events.append_array(effect_resolver.last_remove_events.duplicate())
			all_upgrade_events.append_array(effect_resolver.last_upgrade_events.duplicate())

			chain_depth += 1
			event_log.push(&"upgrade_chain", {
				"cascade_depth": cascade_depth,
				"chain_depth": chain_depth,
				"matches_found": chain_classified.size(),
			})

		# Step 6: Gravity collapse (iterative settling)
		board_physics.resolve_gravity(board)

		# Step 7: Refill empty cells (spawn-entry-aware)
		var spawn_cells := board_physics.find_spawn_eligible_cells(board)
		spawn_resolver.refill_spawn_entries(board, rng, spawn_table, spawn_cells)

		# Build cascade step for timeline
		timeline.add_cascade_step({
			"cascade_index": cascade_depth,
			"chain_steps": chain_steps,
			"match_events": all_match_events,
			"remove_events": all_remove_events,
			"upgrade_events": all_upgrade_events,
			"gravity_events": board_physics.last_move_events.duplicate(),
			"spawn_events": spawn_resolver.last_spawn_events.duplicate(),
			"board_hash": board.compute_hash(),
		})

		cascade_depth += 1
		cascade_step_completed.emit(cascade_depth, classified.size())

		event_log.push(&"cascade_step", {
			"depth": cascade_depth,
			"matches_found": classified.size(),
			"tiles_removed": all_remove_events.size(),
		})

	event_log.push(&"turn_completed", timeline.to_stats())
	turn_completed.emit(timeline)

	return timeline


## Evaluates the current board without consuming a move.
## Useful for debug inspection — runs the full pipeline once (no cascade).
func evaluate_board(
	board: BoardState,
	event_log: EventLog,
) -> Array[Dictionary]:
	var raw_matches := match_detector.find_matches(board)
	var classified := match_classifier.classify(raw_matches)
	var effect_plan := effect_planner.build_base_plan(classified)
	effect_plan = conflict_resolver.resolve(effect_plan, board)
	return effect_plan
