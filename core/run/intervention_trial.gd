class_name InterventionTrial
extends RefCounted
## Isolated experiment. No production RunController or disk-save integration.
const VERSION := "facets-intervention-trial-v1"
const PROFILES := {"trial-paused-v1":0,"trial-24-v1":24,"trial-48-v1":48}
var state: RunState
var context: ActionContext
var cursor := {}
var pair: Array[Vector2i] = []
var phase := "empty"
var offered := false
var interventions := 0
var offers: Array = []
var clock := {"started":false,"paused":false,"tick":0,"sequence":0,"deadline":0}
var last_error := ""
var _initial := {}
var _command := {}
var _profile := ""
var _transcript: Array = []

func start(snapshot: Dictionary, command_data: Dictionary, profile: String) -> bool:
	if profile not in PROFILES: last_error = "trial_profile"; return false
	var admitted := RunState.restored(snapshot)
	var command := RoomCommand.parse(command_data)
	if not admitted.ok or command == null or command.data.kind != "swap": last_error = "trial_initial"; return false
	var initial: RunState = admitted.state
	if initial.room == null or not RoomActionLegality.can_apply(initial,command).ok: last_error = "trial_root_command"; return false
	var candidate := InterventionTrial.new()
	candidate._initial = GameValue.freeze(snapshot); candidate._command = command.to_dict(); candidate._profile = profile
	candidate.state = initial; candidate.context = ActionContext.new(initial,command)
	candidate.clock.deadline = PROFILES[profile]
	initial.moves_remaining -= 1; initial.room.normal_turns += 1; initial.room.tool_available = true
	candidate.context.emit("resource_spent",{"resource":"resource.action_budget","amount":1,"remaining":initial.moves_remaining})
	candidate.context.emit("tool_allowance",{"available":true})
	if not ToolResolver.apply(candidate.context,command): last_error = "trial_root_effect"; return false
	candidate.pair.assign([command.data.origin,command.data.destination])
	if not candidate._drive(): last_error = candidate.last_error; return false
	_adopt(candidate)
	return true

func _drive(fail_at: String = "") -> bool:
	var resolver := TurnController.new(state.catalog)
	resolver.rules = state.rules; resolver.capture_step_hashes = false; resolver.fail_at = fail_at
	while true:
		var timeline := resolver.execute_turn(state.board,state.streams.stream("board"),state.catalog.supply(),EventLog.new(),pair,context,cursor,true)
		if not timeline.failure_code.is_empty(): last_error = timeline.failure_code; return false
		if cursor.phase == "done": break
		if not offered and state.moves_remaining > 0:
			offers = _find_offers()
			if not offers.is_empty():
				if not _admitted(false): return false
				offered = true; phase = "window"
				return true
	CraftPolicy.settle(context)
	if not RoomBoundaryResolver.finish(context): last_error = context.budget.error; return false
	context.emit("action_settled",{"budget":state.moves_remaining,"phase":state.phase,"work":context.budget.work})
	if not context.budget.error.is_empty(): last_error = context.budget.error; return false
	state.next_action += 1; state.revision += 1
	if fail_at == "before_commit": last_error = "injected_before_commit"; return false
	if not _admitted(true): return false
	phase = "stable"
	return true

func _admitted(stable: bool) -> bool:
	# P2's Work+normal-turn accounting is retained inside the envelope. Trial-only
	# extra Work is explicit and restored before checking its structural invariant.
	var raw := state.to_dict()
	raw["resource.action_budget"] += interventions
	# Boundary phase depends on actual remaining Work, not the normalized total.
	var admitted := RunState.restored(raw,false)
	if not admitted.ok: last_error = "trial_invariant/"+admitted.code; return false
	if stable:
		var physics := BoardPhysics.new()
		if physics._has_move(state.board,state.board.all_cells()) or not physics.find_spawn_eligible_cells(state.board).is_empty() or not MatchDetector.new().find_matches(state.board).is_empty(): last_error = "trial_unstable"; return false
		var issue := RoomBoundaryResolver.validate(state)
		if not issue.is_empty(): last_error = "trial_invariant/"+issue; return false
	return true

func _find_offers() -> Array:
	var promoted := {}
	for fact in context.facts:
		if fact.type == "tile_promoted": promoted[fact.instance_id] = true
	# Board-owned order is (y,x); a cell has only one ID, so the final ID tie is
	# vacuous. Automatic chains have already removed all consumed instances.
	for pos in state.board.all_cells():
		var tile := state.board.get_tile(pos)
		if tile == null or not promoted.has(tile.instance_id) or not state.board.can_move_occupant(pos): continue
		var result: Array = []
		for direction in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
			var target := state.board.neighbor_for(pos,direction,"swap")
			if target == Vector2i(-1,-1): continue
			var command := RoomCommand.exchange(state,pos,target)
			if RoomActionLegality.can_apply(state,command).ok: result.append(command.to_dict())
		if not result.is_empty(): return result
	return []

func event(kind: String, payload: Dictionary = {}) -> Dictionary:
	return {"kind":kind,"window":1,"revision":int(_command.revision)+1,"sequence":int(clock.sequence)+1,"tick":clock.tick}.merged(payload,true)

func apply(input: Dictionary, fail_at: String = "") -> Dictionary:
	if phase != "window": return _reject("trial_not_waiting")
	if _transcript.size() >= 512 or (_transcript.size() >= 511 and input.get("kind") != "decide"): return _reject("trial_transcript_limit")
	if fail_at not in ["","after_spawn","after_promotion","after_obstacle","before_commit"]: return _reject("trial_injection")
	var issue := _validate_input(input)
	if not issue.is_empty(): return _reject(issue)
	var candidate := _clone_pending()
	if candidate == null: return _reject("trial_clone")
	candidate._transcript.append({"input":GameValue.freeze(input),"injection":fail_at})
	var result := candidate._apply_validated(input,fail_at)
	if not result.ok:
		# Committed prefix remains exactly intact; only diagnostic/transcript state
		# changes. Replay reproduces the failed segment, including cap failures.
		phase = "diagnostic"; last_error = result.code
		_transcript = candidate._transcript
		return result
	_adopt(candidate)
	return result

func _validate_input(input: Dictionary) -> String:
	var keys := ["kind","window","revision","sequence","tick"]
	match input.get("kind"):
		"presented", "advance": pass
		"pause": keys.append_array(["paused","reason"])
		"decide": keys.append("command")
		_: return "trial_command"
	if not StateAdmission.exact(input,keys): return "trial_command_schema"
	for key in ["window","revision","sequence","tick"]:
		if not input[key] is int or input[key] < 0 or input[key] > 1000000000: return "trial_command_integer"
	if input.window != 1 or input.revision != int(_command.revision)+1 or input.sequence != int(clock.sequence)+1: return "trial_stale"
	if input.kind == "presented": return "" if not clock.started and input.tick == 0 else "trial_already_started"
	if not clock.started: return "trial_not_presented"
	if input.tick < int(clock.tick): return "trial_past_tick"
	if input.kind == "pause":
		if input.tick != clock.tick or not input.paused is bool or input.reason not in ["manual","focus","render_stall"]: return "trial_pause"
		return ""
	if clock.paused: return "trial_paused"
	if _expired(input.tick): return "" # Expiry wins ties before target admission.
	if input.kind == "decide" and input.command != null:
		var parsed := RoomCommand.parse(input.command)
		if parsed == null: return "trial_target"
		var legal := false
		for option in offers:
			if CanonicalCodec.encode(option) == CanonicalCodec.encode(parsed.to_dict()): legal = true
		if not legal or not RoomActionLegality.can_apply(state,parsed).ok: return "trial_target"
	return ""

func _expired(tick: int) -> bool:
	return int(clock.deadline) > 0 and tick >= int(clock.deadline)

func _apply_validated(input: Dictionary, fail_at: String) -> Dictionary:
	clock.sequence = input.sequence
	if input.kind == "presented": clock.started = true; return {"ok":true,"status":"window"}
	if input.kind == "pause": clock.paused = input.paused; return {"ok":true,"status":"window"}
	clock.tick = mini(input.tick,clock.deadline) if int(clock.deadline) > 0 else input.tick
	var expired := _expired(input.tick)
	if input.kind == "advance" and not expired: return {"ok":true,"status":"window"}
	if input.kind == "decide" and input.command != null and not expired:
		var command := RoomCommand.parse(input.command)
		state.moves_remaining -= 1; interventions += 1
		context.emit("resource_spent",{"resource":"resource.action_budget","amount":1,"remaining":state.moves_remaining})
		context.emit("intervention_committed",{"window":1,"command":command.to_dict()})
		if not ToolResolver.apply(context,command,false): return ActionTransaction.failure("trial_effect")
		pair.assign([command.data.origin,command.data.destination])
		cursor.phase = "scan"; cursor.first = true
	if not _drive(fail_at): return ActionTransaction.failure(last_error)
	return {"ok":true,"status":"expired" if expired else "stable"}

func _clone_pending() -> InterventionTrial:
	var raw := state.to_dict(); raw["resource.action_budget"] += interventions
	var admitted := RunState.restored(raw,false)
	if not admitted.ok: return null
	var copy := InterventionTrial.new()
	copy.state = admitted.state; copy.state.moves_remaining -= interventions
	copy.context = ActionContext.new(copy.state,RoomCommand.parse(_command))
	# Constructing context emits a root; replace every affected counter and field.
	copy.state.next_event = state.next_event
	for key in ["cause","reward_eligible","best_craft","root","parent","step","component_index","segment"]: copy.context.set(key,context.get(key))
	copy.context.facts = context.facts.duplicate(true)
	copy.context._depths = context._depths.duplicate(true); copy.context._journeys = context._journeys.duplicate(true)
	copy.context.budget.work = context.budget.work; copy.context.budget.facts = context.budget.facts; copy.context.budget.error = context.budget.error
	copy.cursor = cursor.duplicate(true); copy.pair.assign(pair); copy.phase = phase; copy.offered = offered; copy.interventions = interventions
	copy.offers = offers.duplicate(true); copy.clock = clock.duplicate(true)
	copy._initial = _initial; copy._command = _command; copy._profile = _profile; copy._transcript = _transcript.duplicate(true)
	return copy

func _adopt(other: InterventionTrial) -> void:
	for key in ["state","context","cursor","pair","phase","offered","interventions","offers","clock","last_error","_initial","_command","_profile","_transcript"]: set(key,other.get(key))

func snapshot() -> Dictionary:
	var depths: Array = []
	var ids := context._depths.keys(); ids.sort()
	for id in ids: depths.append([id,context._depths[id]])
	var pending := {"facts":context.facts,"depths":depths,"journeys":context._journeys,
		"work":context.budget.work,"fact_count":context.budget.facts,"budget_error":context.budget.error}
	for key in ["cause","reward_eligible","best_craft","root","parent","step","component_index","segment"]: pending[key] = context.get(key)
	return GameValue.freeze({"version":VERSION,"profile":_profile,"initial":_initial,"command":_command,
		"transcript":_transcript,"state":state.to_dict(),"context":pending,"cursor":cursor,"pair":pair,
		"phase":phase,"offered":offered,"interventions":interventions,"offers":offers,"clock":clock,"error":last_error})

static func restored(value: Variant) -> Dictionary:
	if not StateAdmission.exact(value,["version","profile","initial","command","transcript","state","context","cursor","pair","phase","offered","interventions","offers","clock","error"]): return StateAdmission.fail("trial_snapshot_schema")
	if value.version != VERSION or not value.profile is String or not value.initial is Dictionary or not value.command is Dictionary or not value.transcript is Array or value.transcript.size() > 512: return StateAdmission.fail("trial_snapshot_value")
	var bytes := CanonicalCodec.encode(value)
	if bytes.is_empty(): return StateAdmission.fail("trial_snapshot_codec")
	var result := InterventionTrial.new()
	if not result.start(value.initial,value.command,value.profile): return StateAdmission.fail(result.last_error)
	for item in value.transcript:
		if not StateAdmission.exact(item,["input","injection"]) or not item.input is Dictionary or not item.injection is String: return StateAdmission.fail("trial_transcript")
		var applied := result.apply(item.input,item.injection)
		if not applied.ok and applied.status != "failed": return StateAdmission.fail("trial_transcript_rejected")
	if CanonicalCodec.encode(result.snapshot()) != bytes: return StateAdmission.fail("trial_snapshot_mismatch")
	return {"ok":true,"trial":result}

func presentation_result(before: BoardState, from_fact: int = 0, command_data: Dictionary = {}) -> Dictionary:
	var facts: Array = GameValue.freeze(context.facts.slice(from_fact))
	return {"ok":true,"before":before.duplicate_board(),"after":state.board.duplicate_board(),
		"facts":facts,"timeline":EventTimeline.from_facts(facts),"command":command_data,
		"action_id":int(_initial.next_action),"revision":state.revision,"generation":0,
		"state_digest":CanonicalCodec.digest(snapshot()),"event_digest":CanonicalCodec.digest(facts)}

func _reject(code: String) -> Dictionary:
	return {"ok":false,"status":"rejected","code":code}
