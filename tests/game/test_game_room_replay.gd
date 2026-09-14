extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var actions := 0
	var tools := {}
	var outcomes := {}
	for seed_value in range(1,101):
		var game := RunController.new()
		check(game.start_room(null,seed_value),"room seed %d" % seed_value)
		check(game.apply_action(RoomCommand.begin(0)).ok,"Begin %d" % seed_value)
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
			var result := game.apply_action(command)
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
		if seed_value % 10 == 0: print("ROOM_REPLAY_PROGRESS: ",seed_value,"/100")
	for kind in ["action.exchange","action.clear_target","action.promote_target"]: check(tools.get(kind,0)>0,"corpus exercises "+kind)
	var folder := "res://artifacts/game/p2/simulation"
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder+"/room-corpus.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"seeds":100,"actions":actions,"tools":tools,"outcomes":outcomes,"failures":failures},"\t"))
	finish("test_game_room_replay")
