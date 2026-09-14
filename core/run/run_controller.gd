class_name RunController
extends RefCounted
## Session owner and composition boundary. Rule work occurs in ActionTransaction.
signal run_state_changed(run_state: RunState)
signal board_changed(board: BoardState)
var run_state: RunState
var rng: SeededRng
var event_log := EventLog.new()
var last_result: Dictionary = {}
var last_error := ""
var generation := 0
var _initial: Dictionary = {}
var _commands: Array = []
var _adapter_result: Dictionary = {}
var _adapter_acknowledged := true

func start_new_run(config: Dictionary = {}) -> bool:
	var admitted: Dictionary
	if config.get("catalog") is GameCatalog: admitted = GameCatalog.admit(config.catalog.to_dict())
	else: admitted = GameBootstrap.catalog()
	if not admitted.ok: last_error = admitted.code; return false
	var catalog: GameCatalog = admitted.catalog
	if config.has("spawn_table"):
		if not config.spawn_table is SpawnTableResource: last_error = "invalid_supply"; return false
		var data := catalog.to_dict()
		data.targets = Array(config.spawn_table.allowed_tiers); data.weights = Array(config.spawn_table.weights)
		admitted = GameCatalog.admit(data)
		if not admitted.ok: last_error = admitted.code; return false
		catalog = admitted.catalog
	var layout: BoardLayoutResource = config.get("board_layout")
	if layout == null:
		layout = BoardLayoutResource.new()
		layout.board_size = config.get("board_size",Vector2i(8,8))
	var seed_value: Variant = config.get("seed",1001)
	var budget: Variant = config.get("starting_moves",20)
	if not seed_value is int or not budget is int or budget < 1 or budget > 1000000000: last_error = "invalid_run_config"; return false
	var rules: RuleSet = config.get("rules",RuleSet.new())
	var validated := RuleSet.admit(rules.to_dict())
	if not validated.ok: last_error = validated.code; return false
	var opening := OpeningGenerator.generate(layout,catalog,RngStreamBank.new(seed_value),rules)
	if not opening.ok: last_error = opening.code; return false
	var state := RunState.new()
	state.board = opening.board; state.catalog = catalog; state.rules = rules
	state.streams = opening.streams; state.moves_remaining = budget; state.opening_attempts = opening.attempts
	state.sync_adapters()
	_publish_session(state)
	return true

func start_room(resource: RoomDefinitionResource = null, seed_value: int = 1001, profile: RuleSet = null) -> bool:
	if resource == null: resource = load("res://data/game/rooms/open_seam.tres")
	var catalog_result := GameBootstrap.catalog()
	if not catalog_result.ok: last_error = catalog_result.code; return false
	var admitted := RoomDefinition.compile(resource,catalog_result.catalog)
	if not admitted.ok: last_error = admitted.code; return false
	var rules := profile if profile != null else RuleSet.for_room()
	var rule_result := RuleSet.admit(rules.to_dict())
	if not rule_result.ok or not rules.is_room(): last_error = "invalid_room_rules"; return false
	var opening := OpeningGenerator.generate(admitted.board.layout_resource(),catalog_result.catalog,RngStreamBank.new(seed_value),rules,admitted.board)
	if not opening.ok: last_error = opening.code; return false
	var state := RunState.new()
	state.board = opening.board; state.catalog = catalog_result.catalog; state.rules = rules
	state.streams = opening.streams; state.opening_attempts = opening.attempts
	state.moves_remaining = admitted.definition.data.work; state.phase = "briefing"
	state.room = RoomState.new(); state.room.definition = admitted.definition; state.room.craft = admitted.definition.data.craft
	state.sync_adapters()
	var restored := RunState.restored(state.to_dict())
	if not restored.ok: last_error = restored.code; return false
	_publish_session(state)
	return true

func _publish_session(state: RunState) -> void:
	run_state = state; rng = state.streams.stream("board")
	generation += 1; last_error = ""; last_result = {}; _adapter_result = {}; _adapter_acknowledged = true
	event_log = EventLog.new(); _commands.clear(); _initial = GameValue.freeze(state.to_dict())
	board_changed.emit(state.board.duplicate_board())
	run_state_changed.emit(state)

func reroll_board(seed_override: int = -1) -> bool:
	if run_state == null: return start_new_run()
	if run_state.room != null: last_error = "room_reroll_unsupported"; return false
	var next_seed := seed_override if seed_override >= 0 else run_state.run_seed + 1
	return start_new_run({"catalog":run_state.catalog,"rules":run_state.rules,"board_layout":run_state.board.layout_resource(),
		"starting_moves":maxi(1,run_state.moves_remaining),"seed":next_seed})

func restart() -> bool:
	return restore_snapshot(_initial)

func can_apply_action(command: Variant) -> Dictionary:
	if run_state == null: return {"ok":false,"code":"no_session"}
	if run_state.room != null: return RoomActionLegality.can_apply(run_state,command)
	if not command is SwapCommand: return {"ok":false,"code":"invalid_command"}
	return ActionLegality.can_apply(run_state.board,command,run_state.moves_remaining,run_state.phase)

func enumerate_legal_swaps() -> Array[SwapCommand]:
	if run_state == null: return []
	return ActionLegality.enumerate_legal_swaps(run_state.board,run_state.moves_remaining,run_state.phase)

func apply_action(command: Variant, expected_revision: int = -1, fail_at: String = "") -> Dictionary:
	if run_state == null: return {"ok":false,"status":"rejected","code":"no_session"}
	if expected_revision >= 0 and expected_revision != run_state.revision: return {"ok":false,"status":"rejected","code":"stale_revision"}
	var result := ActionTransaction.resolve(run_state,command,fail_at)
	if not result.ok:
		last_error = result.code
		return result
	run_state = result.state; rng = run_state.streams.stream("board")
	result.erase("state")
	result.generation = generation
	_commands.append(GameValue.freeze({"command":command.to_dict(),"state_digest":result.state_digest,"event_digest":result.event_digest}))
	for fact in result.facts: event_log.push(StringName(fact.type),fact)
	last_error = ""; last_result = result
	run_state_changed.emit(run_state)
	return result

func restore_snapshot(snapshot: Variant) -> bool:
	var result := RunState.restored(snapshot)
	if not result.ok: last_error = result.code; return false
	_publish_session(result.state)
	return true

func restore_bytes(bytes: PackedByteArray) -> bool:
	var decoded := CanonicalCodec.decode(bytes)
	if not decoded.ok: last_error = decoded.code; return false
	return restore_snapshot(decoded.value)

func export_replay() -> Dictionary:
	return {"version":"facets-replay-v2" if run_state != null and run_state.room != null else "facets-replay-v1","initial":_initial.duplicate(true),"initial_digest":CanonicalCodec.digest(_initial),"commands":_commands.duplicate(true)}

## Transitional API: begin commits once; resolve/finalize never run rules.
func begin_swap(a: Vector2i, b: Vector2i) -> bool:
	if not _adapter_acknowledged: return false
	_adapter_result = apply_action(SwapCommand.new(a,b))
	_adapter_acknowledged = not _adapter_result.ok
	return _adapter_result.ok

func resolve_remaining_cascades() -> EventTimeline:
	return _adapter_result.get("timeline")

func finalize_swap() -> void:
	_adapter_acknowledged = true

func attempt_swap(a: Vector2i, b: Vector2i) -> EventTimeline:
	var result := apply_action(SwapCommand.new(a,b))
	return result.get("timeline")

func acknowledge(action_id: int, session_generation: int) -> bool:
	return not last_result.is_empty() and last_result.action_id == action_id and session_generation == generation

func get_run_state() -> RunState:
	return run_state

func get_board() -> BoardState:
	return run_state.board if run_state != null else null
