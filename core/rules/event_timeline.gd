class_name EventTimeline
extends RefCounted

## A structured record of everything that happened during a turn.
## Produced by the simulation layer (TurnController) and consumed by
## the rendering layer (AnimationSequencer) for animation playback.
##
## Structure:
##   cascade_steps: Array of cascade step Dictionaries, each containing:
##     - cascade_index: int
##     - chain_steps: Array[Dict]    — sequential match/remove/upgrade rounds
##     - match_events: Array[Dict]   — flattened match events for the full step
##     - remove_events: Array[Dict]  — flattened remove events for the full step
##     - upgrade_events: Array[Dict] — flattened upgrade events for the full step
##     - gravity_events: Array[Dict] — tiles moved by gravity
##     - spawn_events: Array[Dict]   — new tiles spawned
##     - board_hash: int             — board state hash after this step

var cascade_steps: Array[Dictionary] = []
var failure_code: String = ""
var rule_facts: Array = []
var work_count := 0

## Presentation is derived solely from canonical facts; no rule evaluation here.
static func from_facts(facts: Array) -> EventTimeline:
	var result := EventTimeline.new()
	result.rule_facts = facts
	for fact in facts:
		if fact.type == "action_settled": result.work_count = fact.work
		if fact.step < 0 or fact.type in ["action_settled","tile_consumed"]: continue
		var step := result._projection_step(fact.step)
		match fact.type:
			"match_committed":
				step.cascade_index = fact.cascade; step.chain_index = fact.round
				step.match_events.append(fact)
			"tile_removed": step.remove_events.append({"cell":fact.cell,"instance_id":fact.instance_id,"tile_id":fact.source.tile_id,"tier":fact.source.tier})
			"tile_promoted": step.upgrade_events.append({"cell":fact.cell,"instance_id":fact.instance_id,"tile_id":fact.new.tile_id,"new_tier":fact.new.tier,"old":fact.old,"new":fact.new})
			"tile_spawned": step.spawn_events.append({"cell":fact.cell,"instance_id":fact.instance_id,"tile_id":fact.source.tile_id,"tier":fact.source.tier,"direction":fact.direction,"source":fact.source})
			"tile_moved":
				if fact.movement != "settling": continue
				for segment in fact.path:
					var physical := result._projection_step(segment.step)
					var event: Dictionary = segment.duplicate(true)
					event.instance_id = fact.instance_id; event.tile_id = fact.tile_id; event.tier = fact.tier
					physical.gravity_events.append(event)
	for step in result.cascade_steps:
		step.gravity_events.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.sequence < b.sequence)
		for field in ["match_events","remove_events","upgrade_events","gravity_events","spawn_events"]: step[field] = GameValue.freeze(step[field])
		step.make_read_only()
	result.cascade_steps.make_read_only()
	return result

func _projection_step(index: int) -> Dictionary:
	while cascade_steps.size() <= index:
		cascade_steps.append({"cascade_index":0,"chain_index":0,"match_events":[],"remove_events":[],"upgrade_events":[],"gravity_events":[],"spawn_events":[]})
	return cascade_steps[index]

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
	if not rule_facts.is_empty():
		events.assign(rule_facts)
		return events
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
