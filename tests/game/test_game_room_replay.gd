extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var actions := 0
	var tools := {}
	var outcomes := {}
	var records: Array = []
	var timings: Array = []
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/p2-reference.json"))
	for seed_value in range(1,101):
		var game := RunController.new()
		var opened := game.start_room(null,seed_value)
		check(opened,"room seed %d" % seed_value)
		if not opened: continue
		var begun: Dictionary = game.apply_action(RoomCommand.begin(0))
		check(begun.ok,"Begin %d" % seed_value)
		if not begun.ok: continue
		var midpoint: RunController
		for turn in 40:
			if game.run_state.phase != "ready": break
			var choices := RoomActionLegality.tools(game.run_state)
			var swaps := game.enumerate_legal_swaps()
			var command: RoomCommand
			if not choices.is_empty() and (turn % 3 == 0 or swaps.is_empty()):
				command = choices[(seed_value+turn*17) % choices.size()]
				tools[command.data.kind] = tools.get(command.data.kind,0)+1
			else:
				check(not swaps.is_empty(),"ready always offers an action")
				if swaps.is_empty(): break
				var swap := swaps[(seed_value+turn*13) % swaps.size()]
				command = RoomCommand.exchange(game.run_state,swap.origin,swap.destination)
			var started := Time.get_ticks_usec()
			var result := game.apply_action(command)
			timings.append(Time.get_ticks_usec()-started)
			check(result.ok,"seed %d action %d: %s" % [seed_value,turn,result.get("code")])
			if not result.ok: break
			actions += 1
			if midpoint != null:
				var second := midpoint.apply_action(RoomCommand.parse(command.to_dict()))
				check(second.ok and second.get("state_digest") == result.state_digest and second.get("event_digest") == result.event_digest,"restored suffix exact")
			elif turn == 7:
				midpoint = RunController.new()
				check(midpoint.restore_bytes(CanonicalCodec.encode(game.run_state.to_dict())),"midpoint canonical restore")
			var before := game.run_state.digest()
			check(not game.apply_action(command).ok and game.run_state.digest() == before,"stale command pure")
		check(game.run_state.phase in ["complete","failed"],"room reaches terminal within bound")
		outcomes[game.run_state.phase] = outcomes.get(game.run_state.phase,0)+1
		check(ReplayRecord.verify(game.export_replay()).ok,"full replay seed %d" % seed_value)
		var replay := game.export_replay()
		var expected: Dictionary = reference.records[seed_value-1]
		check(replay.initial_digest == expected.initial_digest,"frozen P2 initial identity %d" % seed_value)
		# Compare string identities directly: diagnostic JSON parses numbers as floats.
		check(replay.commands.size() == expected.checkpoints.size(),"frozen P2 action count %d" % seed_value)
		for i in mini(replay.commands.size(),expected.checkpoints.size()):
			check(replay.commands[i].state_digest == expected.checkpoints[i].state_digest and replay.commands[i].event_digest == expected.checkpoints[i].event_digest,"frozen P2 checkpoint %d/%d" % [seed_value,i])
		check(game.run_state.phase == expected.phase and game.run_state.room.failure_reason == expected.reason,"frozen P2 outcome %d" % seed_value)
		write_report("seed-%03d.replay" % seed_value,replay,true)
		records.append({"seed":seed_value,"initial_digest":replay.initial_digest,"checkpoints":replay.commands,
			"phase":game.run_state.phase,"reason":game.run_state.room.failure_reason})
		if seed_value % 10 == 0: print("ROOM_REPLAY_PROGRESS: ",seed_value,"/100")
	for kind in ["action.exchange","action.clear_target","action.promote_target"]: check(tools.get(kind,0)>0,"corpus exercises "+kind)
	check(actions == int(reference.actions) and records.size() == 100,"complete P2 reference corpus")
	timings.sort()
	write_report("room-corpus.json",{"schema":2,"policy":"p2-mixed-v1","protocol":"facets-replay-v2",
		"godot":Engine.get_version_info().string,"seeds":100,"actions":actions,"tools":tools,"outcomes":outcomes,
		"records":records,"failures":failures,"p95_action_ms":timings[mini(timings.size()-1,int(ceil(timings.size()*0.95))-1)]/1000.0 if not timings.is_empty() else null,
		"max_action_ms":timings[-1]/1000.0 if not timings.is_empty() else null})
	finish("test_game_room_replay")
