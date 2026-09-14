extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var controller := RunController.new()
	check(controller.start_room(null,7),"authored room starts")
	if controller.run_state == null: finish("test_game_room"); return
	var state := controller.run_state
	check(state.phase == "briefing" and state.moves_remaining == 16 and state.room.craft == 1,"briefing economy")
	check(state.board.obstacles.size() == 4 and state.room.remaining(state.board) == 4,"four marked rubble")
	check(state.room.definition.data.is_read_only(),"definition detached immutable")
	for pos in state.board.all_cells():
		check((state.board.get_tile(pos) != null) != (not state.board.obstacle_at(pos).is_empty()),"exclusive occupant at %s" % pos)
	var initial := state.digest()
	var rejected := controller.apply_action(RoomCommand.exchange(state,Vector2i.ZERO,Vector2i.RIGHT))
	check(not rejected.ok and state.digest() == initial,"briefing rejects gameplay purely")
	var started := controller.apply_action(RoomCommand.begin(0))
	check(started.ok and controller.run_state.moves_remaining == 16 and controller.run_state.room.normal_turns == 0,"begin is free boundary")
	var clone := controller.run_state.duplicate_state()
	clone.room.craft += 1
	check(clone.digest() != controller.run_state.digest() and controller.run_state.room.craft == 1,"clone economy isolated")
	var bad := controller.run_state.to_dict(); bad.room["resource.tactic_charge"] = 7
	check(not RunState.restored(bad).ok,"invalid Craft restore")
	bad = controller.run_state.to_dict(); bad.schema = 1
	check(not RunState.restored(bad).ok,"room cannot masquerade as v1")
	bad = controller.run_state.to_dict(); bad.phase = "presenting"
	check(not RunState.restored(bad).ok,"cosmetic phase not saved")
	bad = controller.run_state.to_dict(); bad.room.definition.marked_ids.append("unknown")
	check(not RunState.restored(bad).ok,"missing marked target rejected")
	var obstacle: Dictionary = controller.run_state.board.obstacles.values()[0]
	bad = controller.run_state.to_dict()
	bad.board.obstacles[obstacle.id].durability = 3
	check(not RunState.restored(bad).ok,"durability rejected")
	check(not controller.run_state.board.can_enter(obstacle.cell),"rubble blocks entry")
	check(controller.run_state.board.neighbor_for(obstacle.cell,Vector2i.UP,"match") != Vector2i(-1,-1),"rubble is active topology")
	var board_copy := controller.run_state.board.duplicate_board()
	board_copy.set_tile(obstacle.cell,state.catalog.create_tile(1))
	check(board_copy.get_tile(obstacle.cell) == null,"set_tile cannot bypass obstacle")
	for c in GameFixtureAdapter.read_cases():
		if c.id not in ["first_action_win","last_action_win"]: continue
		var fixture := RoomTestSupport.fixture(c.board,c.obstacles,int(c.work),int(c.craft))
		fixture.streams = RngStreamBank.new(int(c.seed)); fixture.sync_adapters()
		var game := RoomTestSupport.controller(fixture)
		var result := game.apply_action(RoomCommand.exchange(game.run_state,GameFixtureAdapter.cell(c.swap[0]),GameFixtureAdapter.cell(c.swap[1])))
		check(result.ok,c.id+" commits: "+str(result.get("code")))
		if not result.ok: continue
		check(game.run_state.phase == c.expected.room_result and game.run_state.moves_remaining == int(c.expected.work),c.id+" completion/Work")
		check(game.run_state.room.remaining(game.run_state.board) == 0,c.id+" clears marked rubble")
		check(result.facts.filter(func(f: Dictionary) -> bool: return f.type == "room_result").size() == 1,c.id+" completes once")
		var terminal := game.run_state.digest()
		check(not game.apply_action(RoomCommand.begin(game.run_state.revision)).ok and terminal == game.run_state.digest(),"terminal input pure")
		check(ReplayRecord.verify(game.export_replay()).ok,c.id+" replay")
		for injection in ["after_cost","after_target","after_promotion","after_obstacle","after_spawn","after_craft","before_commit"]:
			var failing := RoomTestSupport.controller(fixture)
			var before := failing.run_state.digest(); var record := CanonicalCodec.digest(failing.export_replay())
			var failure := failing.apply_action(RoomCommand.exchange(failing.run_state,GameFixtureAdapter.cell(c.swap[0]),GameFixtureAdapter.cell(c.swap[1])),-1,injection)
			check(not failure.ok and failure.status == "failed" and before == failing.run_state.digest() and record == CanonicalCodec.digest(failing.export_replay()),"atomic "+c.id+"/"+injection)
	# Source-cell damage includes a survivor, deduplicates contacts and ignores diagonal cells.
	var damage_state := RoomTestSupport.fixture([[1,2,3],[2,0,1],[3,1,2]],[{"cell":Vector2i(1,1)}])
	var targets := damage_state.board.obstacle_neighbors([Vector2i(0,1),Vector2i(1,0),Vector2i(2,1)])
	check(targets.size() == 1,"multiple component contacts deduplicated")
	check(damage_state.board.obstacle_neighbors([Vector2i(0,0)]).is_empty(),"diagonal no damage")
	var context := ActionContext.new(damage_state,RoomCommand.exchange(damage_state,Vector2i.ZERO,Vector2i.RIGHT))
	ObstacleResolver.damage(context,targets[0].id,1,context.root)
	check(damage_state.board.obstacles[targets[0].id].durability == 1,"one component one hit")
	ObstacleResolver.damage(context,targets[0].id,1,context.root)
	ObstacleResolver.damage(context,targets[0].id,1,context.root)
	check(context.facts.filter(func(f: Dictionary) -> bool: return f.type == "obstacle_broken").size() == 1,"break once after second component")
	check(damage_state.board.can_enter(Vector2i(1,1)),"broken rubble opens refill")
	check(controller.restart() and controller.run_state.digest() == initial,"restart restores briefing")
	finish("test_game_room")
