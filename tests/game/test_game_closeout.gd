extends "res://tests/game/game_test.gd"

## Boundary double only: real RNG determinism is covered by recovery/replay suites.
class LastCandidateRng extends SeededRng:
	var calls := 0
	var final_ids: Array = []
	func shuffle(values: Array) -> Array:
		calls += 1
		if calls < 64: return values.duplicate()
		var by_id := {}
		for tile in values: by_id[tile.instance_id] = tile
		var result: Array = []
		for id in final_ids: result.append(by_id[id])
		return result

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var coverage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/closeout-audit-fields.json"))
	var field_ids := {}
	for row in coverage.fields: field_ids[row.requirement] = true
	var observed := 0
	for item in GameFixtureAdapter.inventory(GameFixtureAdapter.read_cases()).cases:
		for field in item.fields:
			observed += 1
			check(field_ids.has(item.id+"."+field),"cumulative frozen field owned: "+item.id+"."+field)
	check(observed == field_ids.size(),"no stale cumulative fields")
	_identity_and_admission()
	_tools_and_availability()
	_component_damage()
	_final_recovery_candidate()
	var samples: Array = []
	for i in range(1,11): samples.append(float(i))
	check(ActionProbe._stats(samples).p95 == 10.0,"nearest-rank p95 of ten includes maximum")
	check(ActionProbe._stats(samples).p50 == 5.0,"nearest-rank median convention")
	finish("test_game_closeout")

func _identity_and_admission() -> void:
	var game := RunController.new()
	check(game.start_room(null,7),"identity room starts")
	if game.run_state == null: return
	check(game.apply_action(RoomCommand.begin(0)).ok,"identity room begins")
	var snapshot := game.run_state.to_dict()
	var paths: Array = []
	_leaves(snapshot.room,["room"],paths)
	_leaves(snapshot.board.obstacles,["board","obstacles"],paths)
	var digest := CanonicalCodec.digest(snapshot)
	for path in paths:
		var changed := snapshot.duplicate(true)
		var container: Variant = changed
		for i in path.size()-1: container = container[path[i]]
		var key: Variant = path[-1]; var value: Variant = container[key]
		if value is int: container[key] = value+1
		elif value is bool: container[key] = not value
		elif value is Vector2i: container[key] = value+Vector2i.RIGHT
		elif value is String: container[key] = value+"x"
		elif value == null: container[key] = "changed"
		elif value is Dictionary: container[key] = {"probe":1}
		elif value is Array: container[key] = ["probe"]
		check(CanonicalCodec.digest(changed) != digest,"P2 leaf identity "+str(path))
	var invalid: Array = []
	for field in ["normal_turns","recovery_count","recovery_attempts"]:
		for value in [-1,1.5,1000001]:
			var bad := snapshot.duplicate(true); bad.room[field] = value; invalid.append(bad)
	for pair in [["tool_available",1],["resource.tactic_charge",-1],["resource.tactic_charge",7],["failure_reason","unknown"],["normal_turns",1],["recovery_attempts",1]]:
		var bad := snapshot.duplicate(true); bad.room[pair[0]] = pair[1]; invalid.append(bad)
	var bad := snapshot.duplicate(true); bad.room.extra = 1; invalid.append(bad)
	bad = snapshot.duplicate(true); bad.board.next_instance = 1; invalid.append(bad)
	bad = snapshot.duplicate(true); bad.room.definition.initial_board.cells[0].tile = snapshot.board.cells[0].tile; invalid.append(bad)
	for value in invalid:
		check(not game.restore_snapshot(value),"malformed P2 snapshot rejected")
		check(game.run_state.digest() == digest,"failed admission retains active room")

func _leaves(value: Variant, path: Array, result: Array) -> void:
	if value is Dictionary and not value.is_empty():
		for key in value: _leaves(value[key],path+[key],result)
	elif value is Array and not value.is_empty():
		for i in value.size(): _leaves(value[i],path+[i],result)
	else: result.append(path)

func _tools_and_availability() -> void:
	var state := RoomTestSupport.fixture([[1,1,2],[2,3,4],[3,0,5]],[{"cell":Vector2i(1,2)}],16,6)
	var game := RoomTestSupport.controller(state)
	var before := game.run_state.digest()
	var rejected := game.apply_action(RoomCommand.target(game.run_state,"action.promote_target",Vector2i(2,2)))
	check(not rejected.ok and game.run_state.digest() == before,"Refine T5 rejects without cost or mutation")
	var command := RoomCommand.exchange(game.run_state,Vector2i.ZERO,Vector2i.RIGHT,true)
	check(game.can_apply_action(command).ok,"distinct same-tier instances may Reposition")
	var result := game.apply_action(command)
	check(result.ok and game.run_state.room.craft == 4,"same-tier Reposition commits exact cost")
	state = RoomTestSupport.fixture([[1,2],[3,1],[2,3],[0,0]],[{"cell":Vector2i(0,3)},{"cell":Vector2i(1,3)}],16,2)
	check(not ActionLegality.has_legal_swap(state.board),"tool-only fixture has no normal swap")
	var rng_before := state.streams.capture()
	var context := ActionContext.new(state,RoomCommand.begin(state.revision))
	check(RoomBoundaryResolver.finish(context) and state.phase == "ready","affordable tool keeps room ready")
	check(state.room.recovery_count == 0 and state.streams.capture() == rng_before,"tool-only readiness never reshuffles")
	check(RunState.restored(state.to_dict()).ok,"tool-only state admitted")

func _component_damage() -> void:
	var state := RoomTestSupport.fixture([[1,1,1,4,5],[3,0,4,5,6],[4,2,2,2,7]],[{"cell":Vector2i(1,1)}])
	var context := ActionContext.new(state,RoomCommand.exchange(state,Vector2i.ZERO,Vector2i.RIGHT))
	var resolver := TurnController.new(state.catalog); resolver.rules = state.rules; resolver.capture_step_hashes = false
	var timeline := resolver.execute_turn(state.board,state.streams.stream("board"),state.catalog.supply(),EventLog.new(),[],context)
	check(timeline.failure_code.is_empty(),"two-component damage resolves")
	var hits := context.facts.filter(func(f: Dictionary) -> bool: return f.type == "obstacle_damaged")
	var broken := context.facts.filter(func(f: Dictionary) -> bool: return f.type == "obstacle_broken")
	check(hits.size() == 2 and broken.size() == 1,"two simultaneous components hit shared rubble exactly twice")
	if hits.size() == 2: check(hits[0].parent_event_id != hits[1].parent_event_id,"each hit belongs to its own frozen component")

func _final_recovery_candidate() -> void:
	var fixture: Dictionary
	for item in GameFixtureAdapter.read_cases():
		if item.id == "recovery_possible": fixture = item
	var rows: Array = fixture.board.duplicate(true); rows.append([0,0,0]); rows.append([8,0,2])
	var original := RoomTestSupport.fixture(rows,[{"cell":Vector2i(1,3)}],16,0)
	original.board.set_blocked(Vector2i(0,3),true); original.board.set_blocked(Vector2i(2,3),true)
	original.board.set_blocked(Vector2i(1,4),true)
	original.board.get_cell(Vector2i(2,4)).lock = {"kind":"movement_lock","durability":1}
	original.room.tool_available = false
	original.streams = RngStreamBank.new(int(fixture.seed))
	var witness := original.duplicate_state()
	check(RecoveryResolver.recover(ActionContext.new(witness,RoomCommand.begin(witness.revision))).recovered,"real-RNG candidate supplies legal permutation")
	for pos in [Vector2i(0,4),Vector2i(2,4)]:
		check(witness.board.get_cell(pos).to_dict() == original.board.get_cell(pos).to_dict(),"high-tier/locked cell survives recovery intact")
	var ids: Array = []
	for pos in witness.board.all_cells():
		if witness.board.can_move_occupant(pos) and witness.board.get_tile(pos).tier <= 3: ids.append(witness.board.get_tile(pos).instance_id)
	for limit in [63,64]:
		var state := original.duplicate_state()
		var rules := state.rules.to_dict(); rules.max_recoveries = limit; state.rules = RuleSet.new(rules)
		var controlled := LastCandidateRng.new(); controlled.final_ids = ids
		state.streams._streams.recovery = controlled
		var result := RecoveryResolver.recover(ActionContext.new(state,RoomCommand.begin(state.revision)))
		check(result.ok and result.recovered == (limit == 64),"final allowed candidate inclusion %d" % limit)
		check(controlled.calls == limit and state.room.recovery_attempts == limit,"exact bounded attempts %d" % limit)
		check(state.board.to_dict() == (witness.board.to_dict() if limit == 64 else original.board.to_dict()),"no candidate leaks before success %d" % limit)
