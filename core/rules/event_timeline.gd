class_name EventTimeline
extends RefCounted

## A structured record of everything that happened during a turn.
## Produced by the simulation layer (TurnController) and consumed by
## the rendering layer (AnimationSequencer) for animation playback.
##
## Structure:
##   cascade_steps: Array of cascade step Dictionaries, each containing:
##     - cascade_index: int
##     - match_events: Array[Dict]   — matches formed
##     - remove_events: Array[Dict]  — tiles removed
##     - upgrade_events: Array[Dict] — tiles upgraded
##     - gravity_events: Array[Dict] — tiles moved by gravity
##     - spawn_events: Array[Dict]   — new tiles spawned
##     - board_hash: int             — board state hash after this step

var cascade_steps: Array[Dictionary] = []

## Total cascade depth (number of cascade steps).
var cascade_depth: int:
	get:
		return cascade_steps.size()


func add_cascade_step(step: Dictionary) -> void:
	cascade_steps.append(step)


func is_empty() -> bool:
	return cascade_steps.is_empty()


## Returns the board hash after the final cascade step, or -1 if no steps.
func final_board_hash() -> int:
	if cascade_steps.is_empty():
		return -1
	return cascade_steps[-1].get("board_hash", -1)


## Returns a flat array of all events across all phases and cascade steps.
func all_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for step in cascade_steps:
		for phase_key in ["match_events", "remove_events", "upgrade_events",
						  "gravity_events", "spawn_events"]:
			var phase_events: Array = step.get(phase_key, [])
			events.append_array(phase_events)
	return events


## Returns aggregate statistics for the full turn (for backward compatibility).
func to_stats() -> Dictionary:
	var total_matches := 0
	var total_tiles_removed := 0
	for step in cascade_steps:
		total_matches += step.get("match_events", []).size()
		total_tiles_removed += step.get("remove_events", []).size()
	return {
		"total_matches": total_matches,
		"total_tiles_removed": total_tiles_removed,
		"cascade_depth": cascade_depth,
	}
