extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _game(craft: int = 6) -> RunController:
	return RoomTestSupport.controller(RoomTestSupport.fixture([[2,1,3],[1,2,1],[3,0,4]],
		[{"cell":Vector2i(1,2),"durability":2}],16,craft))

func _run() -> void:
	for fixture in GameFixtureAdapter.read_cases():
		if fixture.id not in ["match_4","match_5"]: continue
		# Preserve the frozen board/swap and add a supporting row of rubble.
		var rows: Array = fixture.board.duplicate(true); var support: Array = []; var rubble: Array = []
		for x in rows[0].size(): support.append(0); rubble.append({"cell":Vector2i(x,rows.size())})
		rows.append(support)
		var state := RoomTestSupport.fixture(rows,rubble,16,1)
		state.streams = RngStreamBank.new(int(fixture.seed)); state.sync_adapters()
		var game := RoomTestSupport.controller(state)
		var result := game.apply_action(RoomCommand.exchange(game.run_state,GameFixtureAdapter.cell(fixture.swap[0]),GameFixtureAdapter.cell(fixture.swap[1])))
		check(result.ok,fixture.id+" room transaction")
		if not result.ok: continue
		var components: Array = result.facts.filter(func(f: Dictionary) -> bool: return f.type == "match_committed")
		var initial: Dictionary = components[0]
		var context := ActionContext.new(state,RoomCommand.exchange(state,GameFixtureAdapter.cell(fixture.swap[0]),GameFixtureAdapter.cell(fixture.swap[1])))
		var first := initial.duplicate(true); first.obstacle_targets = []
		context.match_step({"match_events":[first],"upgrade_events":[],"chain_index":0,"cascade_index":0})
		check(context.best_craft == int(fixture.expected.base_craft_candidate),fixture.id+" frozen first-component Craft candidate")
		var earnings: Array = result.facts.filter(func(f: Dictionary) -> bool: return f.type == "craft_settled")
		check(earnings.size() == 1 and earnings[0].base_candidate >= int(fixture.expected.base_craft_candidate),fixture.id+" settles strongest award once")
		check(game.run_state.room.craft == 1+int(earnings[0].gain),fixture.id+" actual Craft credited")
	for kind in ["action.clear_target","action.exchange","action.promote_target"]:
		var game := _game()
		var command := RoomCommand.target(game.run_state,kind,Vector2i(0,0))
		if kind == "action.exchange": command = RoomCommand.exchange(game.run_state,Vector2i.ZERO,Vector2i.RIGHT,true)
		var old_craft := game.run_state.room.craft
		var result := game.apply_action(command)
		check(result.ok,kind+" accepted: "+str(result.get("code")))
		if not result.ok: continue
		check(game.run_state.moves_remaining == 16 and game.run_state.room.normal_turns == 0,kind+" no Work/turn")
		check(game.run_state.room.craft == old_craft-RoomActionLegality.cost(kind,game.run_state.rules),kind+" exact cost/no earnings")
		check(not game.run_state.room.tool_available,kind+" consumes allowance")
		check(result.facts.all(func(f: Dictionary) -> bool: return not f.reward_eligible and f.cause == "tool"),kind+" inherited suppression")
		var verified := ReplayRecord.verify(game.export_replay())
		check(verified.ok,kind+" exact replay: "+str(verified.get("code")))
		var bytes := CanonicalCodec.encode(game.run_state.to_dict())
		check(game.restore_bytes(bytes),kind+" restore")
		var second := game.apply_action(RoomCommand.target(game.run_state,"action.clear_target",Vector2i(1,2),"obstacle"))
		check(not second.ok and second.code == "tool_already_used",kind+" second tool refused")
		for injection in ["after_cost","after_target","after_spawn","after_craft","before_commit"]:
			var failing := _game(); var before := failing.run_state.digest(); var replay := CanonicalCodec.digest(failing.export_replay())
			var failure := failing.apply_action(command,-1,injection)
			check(not failure.ok and failure.status == "failed" and before == failing.run_state.digest() and replay == CanonicalCodec.digest(failing.export_replay()),kind+" rollback "+injection)
	var game := _game()
	var before := game.run_state.digest()
	var no_clear := game.apply_action(RoomCommand.target(game.run_state,"action.clear_target",Vector2i(2,2)))
	check(not no_clear.ok and no_clear.code == "clear_tier_limit" and before == game.run_state.digest(),"Chisel T4 pure rejection")
	var refine_id := game.run_state.board.get_tile(Vector2i(2,2)).instance_id
	var refine := game.apply_action(RoomCommand.target(game.run_state,"action.promote_target",Vector2i(2,2)))
	check(refine.ok,"Refine T4 accepted")
	check(refine.facts.any(func(f: Dictionary) -> bool: return f.type == "tile_promoted" and f.instance_id == refine_id and f.old.tier == 4 and f.new.tier == 5),"Refine T4 to T5 keeps ID")
	game = _game(1)
	before = game.run_state.digest()
	check(not game.apply_action(RoomCommand.target(game.run_state,"action.clear_target",Vector2i(1,2),"obstacle")).ok and before == game.run_state.digest(),"unaffordable target pure")
	game = _game(2)
	var chisel := game.apply_action(RoomCommand.target(game.run_state,"action.clear_target",Vector2i(1,2),"obstacle"))
	check(chisel.ok and game.run_state.board.obstacle_at(Vector2i(1,2)).durability == 1 and game.run_state.room.craft == 0,"Chisel damages exactly one")
	check(chisel.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_removed").is_empty(),"rubble Chisel does not clear neighboring gem")
	var invalid := game.apply_action(RoomCommand.exchange(game.run_state,Vector2i.ZERO,Vector2i(2,2)))
	check(not invalid.ok and not game.run_state.room.tool_available,"invalid swap never reopens tools")
	var swaps := game.enumerate_legal_swaps()
	var swap := game.apply_action(RoomCommand.exchange(game.run_state,swaps[0].origin,swaps[0].destination))
	check(swap.ok and game.run_state.room.tool_available and game.run_state.room.normal_turns == 1,"accepted swap reopens allowance")
	game = _game()
	var stale := RoomCommand.target(game.run_state,"action.clear_target",Vector2i(1,2),"obstacle")
	stale = RoomCommand.new(stale.to_dict().merged({"target_id":"wrong"},true))
	before = game.run_state.digest()
	check(not game.apply_action(stale).ok and before == game.run_state.digest(),"replaced target rejected")
	check(RoomCommand.parse({"kind":"action.promote_target","revision":0,"cell":Vector2i.ZERO,"layer":"gem","target_id":"a","extra":1}) == null,"unknown command fields reject")
	# Tool-induced promotion chains produce facts and objectives but cannot earn Craft.
	var chain := RoomTestSupport.fixture([[1,2,2,3],[3,4,1,4],[4,3,0,2]],[{"cell":Vector2i(2,2)}],16,6)
	game = RoomTestSupport.controller(chain)
	var chain_result := game.apply_action(RoomCommand.target(game.run_state,"action.promote_target",Vector2i.ZERO))
	check(chain_result.ok,"Refine chain accepted")
	check(chain_result.facts.any(func(f: Dictionary) -> bool: return f.type == "match_committed"),"Refine actually triggers a match")
	check(game.run_state.room.craft == 3 and chain_result.facts.all(func(f: Dictionary) -> bool: return not f.reward_eligible),"chain cannot launder tool rewards")
	# Movement lock targets are explicit; lock damage leaves the gem in place.
	var locked := _game().run_state.duplicate_state()
	locked.board.get_cell(Vector2i.ZERO).lock = {"kind":"movement_lock","durability":1}
	game = RoomTestSupport.controller(locked)
	var locked_id := game.run_state.board.get_tile(Vector2i.ZERO).instance_id
	var unlock := game.apply_action(RoomCommand.target(game.run_state,"action.clear_target",Vector2i.ZERO,"lock"))
	check(unlock.ok and game.run_state.board.get_tile(Vector2i.ZERO).instance_id == locked_id and game.run_state.board.get_cell(Vector2i.ZERO).lock.is_empty(),"lock Chisel preserves gem")
	# Direct award policy includes intersections, final capacity and once-only settlement.
	for candidate in [0,1,2]:
		var award_state := _game(5).run_state
		var context := ActionContext.new(award_state,RoomCommand.exchange(award_state,Vector2i.ZERO,Vector2i.RIGHT))
		context.best_craft = candidate
		CraftPolicy.settle(context)
		check(award_state.room.craft == mini(6,5+candidate),"Craft capacity candidate %d" % candidate)
	finish("test_game_tools")
