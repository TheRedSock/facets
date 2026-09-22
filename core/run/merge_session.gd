class_name MergeSession
extends RefCounted
## Single committed successor state; prepare() cannot mutate this object.
const VERSION := "facets-resolution-session-v1"
const SIMULATION := "facets-sim-merge-v1"
const PROFILE := "p3-ready-merge-v1"
const CONTENT := "facets-p2-merge-content-v1"
const REPLAY := "facets-replay-merge-v1"
const WINDOW_TICKS := 20
var state: RunState
var context: MergeMoveContext
var phase := "empty"
var cursor := {"cascade":0,"chain":0}
var move_id := 0
var batch_id := 0
var window_id := 0
var clock := {"started":false,"tick":0,"sequence":0,"paused":false,"assisted":false}
var error := ""
var history: Array = []
var initial := {}
var last_batch := {}
var discount_spent := 0
var discount_charges := 0
var reward_bonus := 0
var modifiers: Dictionary = MergeModifiers.DEFAULTS
var reservation := {}
var clock_notes: Array = []
var failure := {}

func start(value: Dictionary) -> bool:
	var admitted := RunState.restored(value)
	if not admitted.ok or admitted.state.room == null or admitted.state.phase != "ready": return false
	state = admitted.state
	initial = GameValue.freeze(value)
	phase = "ready"; context = null; cursor = {"cascade":0,"chain":0}
	move_id = 0; batch_id = 0; window_id = 0; error = ""; history = []; last_batch = {}
	if state.rules.is_p3(): move_id = state.revision; batch_id = state.revision; window_id = state.revision
	clock = {"started":false,"tick":0,"sequence":0,"paused":false,"assisted":false}
	discount_spent = 0; discount_charges = 0; reward_bonus = 0
	modifiers = GameValue.freeze(MergeModifiers.DEFAULTS)
	reservation = {}
	clock_notes = []; failure = {}
	return true

func configure_modifiers(value: Dictionary) -> bool:
	if phase != "ready" or (batch_id != 0 and not state.rules.is_p3()) or not history.is_empty() or context != null: return false
	var admitted := MergeModifiers.admit(value)
	if not admitted.ok: return false
	modifiers = admitted.value; discount_charges = modifiers.discount_charges; reward_bonus = modifiers.reward_bonus
	return true

func quote(command: RoomCommand) -> Dictionary:
	if not reservation.is_empty(): return StateAdmission.fail("input_reserved")
	if command == null: return StateAdmission.fail("invalid_command")
	if phase not in ["ready","merge_window"]: return StateAdmission.fail("invalid_phase")
	if phase == "merge_window" and (not clock.started or clock.paused or clock.tick >= WINDOW_TICKS): return StateAdmission.fail("window_closed")
	if phase == "merge_window" and command.data.kind != "swap": return StateAdmission.fail("window_swap_only")
	if command.data.kind == "begin_room": return StateAdmission.fail("already_started")
	var cost := MergeModifiers.price("intervention" if phase == "merge_window" else "equilibrium",discount_charges)
	# The small ready view changes only the admission budget; board identity stays exact.
	var query := RunState.new()
	query.board = state.board; query.room = state.room; query.rules = state.rules
	query.settings = state.settings; query.room_uses = state.room_uses
	query.revision = state.revision; query.phase = "ready"; query.moves_remaining = maxi(state.moves_remaining,1) if cost == 0 else state.moves_remaining
	var legal := RoomActionLegality.can_apply(query,command)
	if not legal.ok: return legal
	return {"ok":true,"cost":cost if command.data.kind == "swap" else RoomActionLegality.effective_cost(command.data.kind,state),
		"context":"intervention" if phase == "merge_window" else "equilibrium"}

func presented() -> bool:
	if phase != "merge_window" or clock.started: return false
	clock.started = true; clock.sequence += 1
	return true

func tick(value: int) -> bool:
	if not reservation.is_empty() or phase != "merge_window" or not clock.started or clock.paused or value < clock.tick or value > WINDOW_TICKS: return false
	clock.tick = value
	return true

func reserve(command: RoomCommand) -> Dictionary:
	var price := quote(command)
	if not price.ok: return price
	reservation = GameValue.freeze({"command":command.to_dict(),"revision":state.revision,"window":window_id,
		"tick":clock.tick,"sequence":clock.sequence,"cost":price.cost,"context":price.context})
	return {"ok":true,"ticket":reservation}

func prepare(command: RoomCommand = null, fail_at: String = "", cancelled: Callable = Callable()) -> Dictionary:
	if cancelled.is_valid() and cancelled.call(): return StateAdmission.fail("cancelled")
	var admission := quote(command) if command != null else {"ok":phase in ["merge_window","gravity"],"code":"invalid_continuation"}
	if not admission.ok: return admission
	var started := Time.get_ticks_usec()
	var copy := _detached()
	var copied := Time.get_ticks_usec()
	if cancelled.is_valid() and cancelled.call(): return StateAdmission.fail("cancelled")
	var before := state.board.duplicate_board()
	var first_fact := copy.context.facts.size() if copy.context != null else 0
	var pair: Array[Vector2i] = []
	if command != null:
		copy.move_id += 1
		var room_uses: Dictionary = copy.context.room_uses if copy.context != null else {}
		var run_uses: Dictionary = copy.context.run_uses if copy.context != null else {}
		copy.context = MergeMoveContext.new(copy.state,command,copy.move_id,admission.context)
		copy.context.room_uses = room_uses; copy.context.run_uses = run_uses
		copy.context.budget.cancelled = cancelled
		copy.cursor = {"cascade":0,"chain":0}; first_fact = 0
		if command.data.kind == "swap":
			copy.state.moves_remaining -= admission.cost; copy.state.room.normal_turns += 1; copy.state.room.tool_available = true
			if admission.cost == 0: copy.discount_charges -= 1; copy.discount_spent += 1
			copy.context.emit("resource_spent",{"resource":"resource.action_budget","amount":admission.cost,"remaining":copy.state.moves_remaining})
		else:
			copy.state.room.craft -= admission.cost; copy.state.room.tool_available = false
			if copy.state.rules.is_p3() and command.data.kind == "action.clear_target" and "steady_hand" in copy.state.settings: copy.state.room_uses.steady_hand = true
			copy.context.emit("tool_activated",{"kind":command.data.kind,"cost":admission.cost})
			copy.context.emit("resource_spent",{"resource":"resource.tactic_charge","amount":admission.cost,"remaining":copy.state.room.craft})
		copy.context.emit("tool_allowance",{"available":copy.state.room.tool_available})
		if fail_at == "after_cost": return StateAdmission.fail("injected_after_cost")
		if not ToolResolver.apply(copy.context,command): return StateAdmission.fail("root_effect")
		if command.data.kind in ["swap","action.exchange"]: pair.assign([command.data.origin,command.data.destination])
		copy.context.modifier_bonus = copy.reward_bonus; copy.context.modifier_trigger = copy.modifiers.reward_trigger
		copy.context.modifier_scope = copy.modifiers.reward_scope; copy.context.modifier_context = copy.modifiers.reward_context; copy.context.modifier_family = copy.modifiers.reward_family
	copy.context.direct_batch = command != null
	copy.context.budget.cancelled = cancelled
	var rooted := Time.get_ticks_usec()
	var result := copy._advance(pair,command == null and phase == "gravity",fail_at)
	var resolved := Time.get_ticks_usec()
	if not result.ok: return result
	copy.batch_id += 1; copy.state.revision += 1; copy.state.next_action += 1
	copy.context.emit("batch_committed",{"batch_id":copy.batch_id,"phase":copy.phase})
	if not copy.context.budget.error.is_empty(): return StateAdmission.fail(copy.context.budget.error)
	if fail_at == "before_commit": return StateAdmission.fail("injected_before_commit")
	var raw := copy.state.to_dict(); raw.room.normal_turns -= copy.discount_spent
	var validated := RunState.restored(raw,false)
	if not validated.ok: return StateAdmission.fail("merge_invariant/"+validated.code)
	var admitted_at := Time.get_ticks_usec()
	if cancelled.is_valid() and cancelled.call(): return StateAdmission.fail("cancelled")
	var facts: Array = GameValue.freeze(copy.context.facts.slice(first_fact))
	copy.last_batch = {"ok":true,"before":before,"after":copy.state.board.duplicate_board(),"facts":facts,
		"timeline":EventTimeline.from_facts(facts),"kind":result.kind,"command":command.to_dict() if command != null else {},
		"action_id":copy.move_id,"revision":copy.state.revision,"batch_id":copy.batch_id,
		"state_digest":CanonicalCodec.digest(copy.mechanical_snapshot()),"event_digest":CanonicalCodec.digest(facts)}
	if copy.last_batch.state_digest.is_empty() or copy.last_batch.event_digest.is_empty(): return StateAdmission.fail("merge_codec_failure")
	copy.context.budget.cancelled = Callable()
	if cancelled.is_valid() and cancelled.call(): return StateAdmission.fail("cancelled")
	return {"ok":true,"candidate":copy,"base_revision":state.revision,"base_window":window_id,
		"command":command.to_dict() if command != null else {},"compute_us":Time.get_ticks_usec()-started,
		"stages_us":{"copy":copied-started,"root":rooted-copied,"resolve":resolved-rooted,
			"admit":admitted_at-resolved,"project_hash":Time.get_ticks_usec()-admitted_at}}

func _advance(pair: Array[Vector2i], after_gravity: bool, fail_at: String) -> Dictionary:
	var matched := MergeKernel.resolve_match(context,cursor,pair,fail_at)
	if not matched.ok: return matched
	if matched.matched:
		if state.room.definition.data.objective == "clear_marked_rubble" and state.room.remaining(state.board) == 0:
			state.phase = "complete"; phase = "complete"
			context.emit("room_result",{"phase":"complete","reason":"","remaining":0})
		else:
			phase = "merge_window"; window_id += 1
			clock.started = false; clock.tick = 0
		return {"ok":true,"kind":"merge"}
	if not after_gravity:
		var gravity := MergeKernel.resolve_gravity(context,cursor,fail_at)
		if not gravity.ok: return gravity
		if gravity.moved:
			phase = "gravity"
			return {"ok":true,"kind":"gravity"}
	if state.rules.is_p3():
		var extracted := ExtractionResolver.collect(context)
		if not extracted.ok: return extracted
		if fail_at == "after_extraction": return StateAdmission.fail("injected_after_extraction")
		if extracted.removed and state.room.remaining(state.board) > 0:
			var gravity := MergeKernel.resolve_gravity(context,cursor,fail_at)
			if not gravity.ok: return gravity
			phase = "gravity"
			return {"ok":true,"kind":"gravity"}
	if not RoomBoundaryResolver.finish(context): return StateAdmission.fail(context.budget.error)
	phase = state.phase
	context.emit("action_settled",{"budget":state.moves_remaining,"phase":phase,"work":context.budget.work})
	return {"ok":true,"kind":"stable"}

func publish(prepared: Dictionary, pass_window: bool = false) -> bool:
	if not prepared.get("ok",false) or prepared.base_revision != state.revision or prepared.base_window != window_id: return false
	if not reservation.is_empty() and (prepared.command != reservation.command or reservation.revision != state.revision): return false
	if phase == "merge_window" and prepared.command.is_empty() and (not pass_window or not clock.started or clock.tick < WINDOW_TICKS): return false
	if not prepared.command.is_empty() and reservation.is_empty() and not quote(RoomCommand.parse(prepared.command)).ok: return false
	var receipt: Dictionary = reservation if not reservation.is_empty() else clock
	var entry := {"command":prepared.command,"window":window_id,"tick":receipt.tick,"sequence":receipt.sequence,
		"assisted":clock.assisted,"state_digest":prepared.candidate.last_batch.state_digest,"event_digest":prepared.candidate.last_batch.event_digest}
	entry.clock = clock.duplicate(true)
	entry.record_digest = CanonicalCodec.digest({"previous":history.back().record_digest if not history.is_empty() else "", "entry":entry})
	var old_clock := clock.duplicate(true)
	var candidate: MergeSession = prepared.candidate
	for key in ["state","context","phase","cursor","move_id","batch_id","window_id","last_batch","discount_spent","discount_charges","reward_bonus"]: set(key,candidate.get(key))
	# A default may have been copied before this window was first drawn. Its
	# private clock is never authority over the current presentation decision.
	clock = old_clock
	if phase == "merge_window" and window_id > prepared.base_window:
		clock.started = false; clock.tick = 0; clock.paused = false
	clock.sequence += 1
	history.append(GameValue.freeze(entry))
	reservation = {}
	return true

func record_failure(command: Dictionary, injection: String, code: String) -> void:
	failure = {"command":command,"injection":injection,"code":code,"phase":phase}
	reservation = {}; error = code; phase = "diagnostic"

func snapshot() -> Dictionary:
	return MergeReplay.capture(self)

func apply(command: RoomCommand = null, fail_at: String = "") -> Dictionary:
	var result := prepare(command,fail_at)
	if not result.ok: return result
	if not publish(result,command == null): return StateAdmission.fail("publication_rejected")
	return last_batch

func _detached() -> MergeSession:
	var result := MergeSession.new()
	result.state = state.duplicate_state()
	if context != null: result.context = MergeMoveContext.from_capture(result.state,context.capture())
	for key in ["phase","move_id","batch_id","window_id","discount_spent","discount_charges","reward_bonus","modifiers"]: result.set(key,get(key))
	result.cursor = cursor.duplicate(true); result.clock = clock.duplicate(true)
	return result

func mechanical_snapshot() -> Dictionary:
	return {"version":VERSION,"simulation":P3Content.SIMULATION if state.rules.is_p3() else SIMULATION,"profile":P3Content.PROFILE if state.rules.is_p3() else PROFILE,"content":P3Content.CONTENT if state.rules.is_p3() else CONTENT,"state":state.to_dict(),
		"phase":phase,"cursor":cursor.duplicate(true),"move_id":move_id,"batch_id":batch_id,"window_id":window_id,
		"context":context.capture() if context != null else {},"discount_spent":discount_spent,
		"discount_charges":discount_charges,"reward_bonus":reward_bonus,"modifiers":modifiers}
