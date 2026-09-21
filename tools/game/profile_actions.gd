extends "res://tests/game/game_test.gd"
## Independent stage-cost samples; do not sum repeated microbenchmarks as a
## complete-action measurement. RunController.apply_action is the total witness.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var report := {"schema":1,"godot":Engine.get_version_info().string,"editor":OS.has_feature("editor"),"cpu":OS.get_processor_name(),"profiles":[]}
	for room in [false,true]:
		var game := RunController.new()
		check(game.start_room(null,7) if room else game.start_new_run({"seed":7}),"profile starts")
		if room: check(game.apply_action(RoomCommand.begin(0)).ok,"profile Begin")
		var initial := game.run_state
		var swap := game.enumerate_legal_swaps()[0]
		var command: Variant = RoomCommand.exchange(initial,swap.origin,swap.destination) if room else swap
		var result: Dictionary = game.apply_action(command)
		check(result.ok,"profile action")
		if not result.ok: continue
		var state := game.run_state
		var snapshot := state.to_dict()
		var tests := {
			"clone":func(): return initial.duplicate_state(),
			"state_projection":func(): return state.to_dict(),
			"external_admission":func(): return RunState.restored(snapshot),
			"state_digest":func(): return state.digest(),
			"event_digest":func(): return CanonicalCodec.digest(result.facts),
			"event_freeze":func(): return GameValue.freeze(result.facts),
			"timeline_projection":func(): return EventTimeline.from_facts(result.facts),
			"legality":func(): return RoomActionLegality.can_apply(initial,command) if room else ActionLegality.can_apply(initial.board,command,initial.moves_remaining,initial.phase),
			"enumeration":func(): return ActionLegality.enumerate_legal_swaps(initial.board,initial.moves_remaining,initial.phase),
			"transaction":func(): return ActionTransaction.resolve(initial,command),
		}
		var timings := {}
		for key in tests:
			var values: Array = []
			for i in 30:
				var started := Time.get_ticks_usec()
				tests[key].call()
				values.append((Time.get_ticks_usec()-started)/1000.0)
			timings[key] = ActionProbe._stats(values)
		report.profiles.append({"mode":"p2" if room else "p1","seed":7,"facts":result.facts.size(),"work":result.timeline.work_count,"stages":timings})
	write_report("profile.json",report)
	finish("profile_actions")
