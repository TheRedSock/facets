class_name RunState
extends RefCounted

var board: BoardState
var moves_remaining := 0
var run_seed := 0
var visible_tiers := 4 # Legacy display adapter, not a separate supply policy.
var board_size := Vector2i.ZERO
var spawn_table: SpawnTableResource
var tier_tile_ids: Dictionary = {}
var catalog: GameCatalog
var rules := RuleSet.new()
var streams := RngStreamBank.new()
var phase := "ready"
var revision := 0
var next_action := 1
var next_event := 1
var next_removal := 1
var opening_attempts := 0
var terminal_recovered := {}
var room: RoomState
var settings: Array = []
var room_uses := {}
var run_uses := {}

func sync_adapters() -> void:
	board_size = board.size
	run_seed = streams.master_seed
	spawn_table = catalog.supply()
	tier_tile_ids.clear()
	for i in 8: tier_tile_ids[i + 1] = StringName(catalog.roster()[i])

func to_dict() -> Dictionary:
	var data := {"schema": 4 if rules.is_p3() else (2 if room != null else 1), "rules": rules.to_dict(), "catalog": catalog.to_dict(), "board": board.to_dict(),
		"resource.action_budget": moves_remaining, "rng": streams.capture(), "phase": phase,
		"revision": revision, "next_action": next_action, "next_event": next_event, "next_removal": next_removal,
		"opening_attempts": opening_attempts, "terminal_recovered": terminal_recovered.duplicate(true)}
	if room != null: data.room = room.to_dict()
	if rules.is_p3(): data.merge({"settings":settings.duplicate(),"room_uses":room_uses.duplicate(true),"run_uses":run_uses.duplicate(true)})
	return data

func digest() -> String:
	return CanonicalCodec.digest(to_dict())

func duplicate_state() -> RunState:
	var copy := RunState.new()
	copy.board = board.duplicate_board(); copy.catalog = catalog; copy.rules = rules
	copy.streams = RngStreamBank.restored(streams.capture()).bank
	copy.moves_remaining = moves_remaining; copy.phase = phase; copy.revision = revision
	copy.next_action = next_action; copy.next_event = next_event; copy.next_removal = next_removal
	copy.opening_attempts = opening_attempts; copy.terminal_recovered = terminal_recovered.duplicate(true)
	if room != null: copy.room = room.duplicate_state()
	copy.settings = settings.duplicate(); copy.room_uses = room_uses.duplicate(true); copy.run_uses = run_uses.duplicate(true)
	copy.sync_adapters()
	return copy

static func restored(data: Variant, require_stable: bool = true) -> Dictionary:
	var keys := ["schema","rules","catalog","board","resource.action_budget","rng","phase","revision","next_action","next_event","next_removal","opening_attempts","terminal_recovered"]
	var is_room: bool = data is Dictionary and data.get("schema") is int and data.schema in [2,4]
	if is_room: keys.append("room")
	if data is Dictionary and data.get("schema") == 4: keys.append_array(["settings","room_uses","run_uses"])
	if not StateAdmission.exact(data,keys): return StateAdmission.fail("state_schema")
	var phases := ["briefing","ready","complete","failed"] if is_room else ["ready","budget_exhausted","no_legal_swaps"]
	if not data.schema is int or data.schema not in [1,2,4] or data.phase not in phases: return StateAdmission.fail("state_version_or_phase")
	for field in ["resource.action_budget","revision","next_action","next_event","next_removal","opening_attempts"]:
		if not data[field] is int or data[field] < 0 or data[field] > 1000000000: return StateAdmission.fail("state_counter")
	if data.next_action < 1 or data.next_event < 1 or data.next_removal < 1 or data.revision != data.next_action - 1 or data.next_event < data.next_action or data.next_removal > data.next_event or data.opening_attempts > 64: return StateAdmission.fail("state_allocator")
	if not data.terminal_recovered is Dictionary or data.terminal_recovered.size() > 8: return StateAdmission.fail("recovery_records")
	for key in data.terminal_recovered:
		if key != "8" or not data.terminal_recovered[key] is int or data.terminal_recovered[key] < 0: return StateAdmission.fail("recovery_records")
	var rules_result := RuleSet.admit(data.rules)
	if not rules_result.ok: return rules_result
	if rules_result.rules.is_p3() != (data.schema == 4): return StateAdmission.fail("state_profile_mismatch")
	if data.schema == 4:
		if not P3Content.valid_settings(data.settings) or not data.room_uses is Dictionary or not data.run_uses is Dictionary: return StateAdmission.fail("p3_settings")
		for key in data.room_uses:
			if key != "steady_hand" or data.room_uses[key] != true or not data.room_uses[key] is bool or "steady_hand" not in data.settings: return StateAdmission.fail("p3_room_uses")
		if not data.run_uses.is_empty(): return StateAdmission.fail("p3_run_uses")
	var catalog_result := GameCatalog.admit(data.catalog)
	if not catalog_result.ok: return catalog_result
	var streams_result := RngStreamBank.restored(data.rng)
	if not streams_result.ok: return streams_result
	var board_result := StateAdmission.board(data.board,catalog_result.catalog)
	if not board_result.ok: return board_result
	var state := RunState.new()
	state.board = board_result.board; state.catalog = catalog_result.catalog; state.rules = rules_result.rules
	state.streams = streams_result.bank; state.moves_remaining = data["resource.action_budget"]; state.phase = data.phase
	state.revision = data.revision; state.next_action = data.next_action; state.next_event = data.next_event; state.next_removal = data.next_removal
	state.opening_attempts = data.opening_attempts; state.terminal_recovered = data.terminal_recovered.duplicate(true)
	if data.schema == 4:
		state.settings = data.settings.duplicate(); state.room_uses = data.room_uses.duplicate(true); state.run_uses = data.run_uses.duplicate(true)
	if state.rules.is_room() != is_room or state.board.room_board != is_room: return StateAdmission.fail("state_profile_mismatch")
	if is_room:
		var room_result := RoomState.restored(data.room,state.catalog,state.board)
		if not room_result.ok: return room_result
		state.room = room_result.room
		if state.moves_remaining + state.room.normal_turns != state.room.definition.data.work: return StateAdmission.fail("room_turn_budget")
		if state.room.normal_turns > state.revision or state.room.recovery_count > state.revision or state.room.recovery_attempts > state.room.recovery_count * 64: return StateAdmission.fail("room_counter_consistency")
	state.sync_adapters()
	if require_stable:
		var physics := BoardPhysics.new()
		if physics._has_move(state.board,state.board.all_cells()) or not physics.find_spawn_eligible_cells(state.board).is_empty() or not MatchDetector.new().find_matches(state.board).is_empty(): return StateAdmission.fail("unstable_snapshot")
		if is_room:
			var issue := RoomBoundaryResolver.validate(state)
			if not issue.is_empty(): return StateAdmission.fail(issue)
		else:
			var expected_phase := "budget_exhausted" if state.moves_remaining == 0 else ("no_legal_swaps" if not ActionLegality.has_legal_swap(state.board) else "ready")
			if state.phase != expected_phase: return StateAdmission.fail("inconsistent_phase")
	return {"ok": true, "state": state}
