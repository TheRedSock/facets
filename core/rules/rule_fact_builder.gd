class_name RuleFactBuilder
extends RefCounted
var _state: RunState
var _facts: Array = []
var _depths := {}
var _root := 0
var _action := 0
var _segment := 0
var _step := -1

func build(state: RunState, command: SwapCommand, before: BoardState, timeline: EventTimeline) -> Array:
	_state = state; _action = state.next_action
	_root = emit_fact("action_started", {"command": command.to_dict(), "cost": 1}, null)
	for pair in [[command.origin,command.destination],[command.destination,command.origin]]:
		var tile := before.get_tile(pair[0])
		emit_fact("tile_moved", {"instance_id": tile.instance_id, "tile_id": str(tile.tile_id), "tier": tile.tier, "from": pair[0], "to": pair[1], "movement": "swap", "path": [{"from": pair[0],"to": pair[1],"kind": "swap","sequence": _segment}]}, _root)
		_segment += 1
	var initial: Array = timeline.cascade_steps[0].get("match_events", []) if not timeline.cascade_steps.is_empty() else []
	var matched := {}
	for component in initial:
		for source in component.sources: matched[source.tile.instance_id] = true
	var a := before.get_tile(command.origin); var b := before.get_tile(command.destination)
	if matched.has(a.instance_id) != matched.has(b.instance_id):
		var helper := b if matched.has(a.instance_id) else a
		emit_fact("swap_assisted", {"instance_id": helper.instance_id, "source": helper.to_dict()}, _root)
	var component_index := 0
	var parent := _root
	var journeys := {}
	for step in timeline.cascade_steps:
		_step += 1
		if not step.get("match_events", []).is_empty(): journeys.clear()
		var step_parent := parent
		for component in step.get("match_events", []):
			component_index += 1
			var match_id := emit_fact("match_committed", {"component_id": component_index, "round": step.get("chain_index",0), "cascade": step.cascade_index,
				"sources": component.sources, "cells": component.cells, "tier": component.tier, "line_lengths": component.line_lengths,
				"intersection": component.intersection, "size_class": component.size_class, "survivor": component.survivor, "survivor_id": component.survivor_id}, step_parent)
			for source in component.sources:
				if source.tile.instance_id == component.survivor_id: continue
				var removal := _state.next_removal; _state.next_removal += 1
				var terminal: bool = component.tier == 8
				var payload := {"instance_id": source.tile.instance_id, "cell": source.cell, "source": source.tile, "removal_id": removal,
					"reason": "terminal_recovery" if terminal else "merge_consumption", "survivor_id": component.survivor_id}
				var removed_id := emit_fact("tile_removed", payload, match_id)
				if terminal: _state.terminal_recovered["8"] = _state.terminal_recovered.get("8",0) + 1
				else: emit_fact("tile_consumed", payload, removed_id)
			for promoted in step.get("upgrade_events", []):
				if promoted.instance_id == component.survivor_id:
					emit_fact("tile_promoted", {"instance_id": promoted.instance_id, "cell": promoted.cell, "old": promoted.old, "new": promoted.new}, match_id)
			parent = match_id
		for segment in step.get("gravity_events", []):
			var path_segment := {"from": segment.from, "to": segment.to, "kind": segment.kind, "round": segment.round, "sequence": _segment, "step": _step}
			_segment += 1
			if not journeys.has(segment.instance_id):
				emit_fact("tile_moved", {"instance_id": segment.instance_id, "tile_id": str(segment.tile_id), "tier": segment.tier,
					"from": segment.from, "to": segment.to, "movement": "settling", "path": []}, parent)
				journeys[segment.instance_id] = _facts.size() - 1
			var journey: Dictionary = _facts[journeys[segment.instance_id]]
			journey.to = segment.to; journey.path.append(path_segment)
		for spawned in step.get("spawn_events", []):
			emit_fact("tile_spawned", {"instance_id": spawned.instance_id, "cell": spawned.cell, "source": spawned.source, "direction": spawned.direction}, parent)
	emit_fact("action_settled", {"budget": state.moves_remaining, "phase": state.phase, "work": timeline.work_count}, parent)
	return GameValue.freeze(_facts)

func emit_fact(kind: String, payload: Dictionary, parent: Variant) -> int:
	var id := _state.next_event; _state.next_event += 1
	var data := payload.duplicate(true)
	data["type"] = kind; data["event_id"] = id; data["root_action_id"] = _action
	data["parent_event_id"] = parent; data["causal_depth"] = 0 if parent == null else int(_depths[parent]) + 1
	data["cause"] = "normal_swap"; data["reward_eligible"] = true
	data["step"] = _step
	_depths[id] = data.causal_depth
	_facts.append(data)
	return id
