class_name ExpeditionState
extends RefCounted
## Authoritative expedition owner. Selection/entry are detached transactions;
## a live MergeSession owns only the current room's incremental resolution.
const STAGING := [Vector2i(3,0),Vector2i(4,0)]
var seed_value := 0
var run_id := ""
var room_index := 0
var phase := "empty"
var state: RunState
var session: MergeSession
var carry: Array = []
var entry_bonus := 0
var offers: Array = []
var selected_reward := ""
var route_cards: Array = []
var selected_route := ""
var history: Array = []
var room_entry := {}

func current() -> RunState:
	return session.state if session != null else state

func revision() -> int:
	return current().revision if current() != null else 0

static func create(seed: int) -> Dictionary:
	var run := ExpeditionState.new(); run.seed_value = seed; run.run_id = "expedition/"+str(seed)
	var catalog_result := P3Content.catalog()
	if not catalog_result.ok: return catalog_result
	var room := P3Rooms.definition("open_seam",catalog_result.catalog)
	if not room.ok: return room
	var prepared := run.prepare_entry(room.definition)
	if not prepared.ok: return prepared
	if not run.publish_entry(prepared): return StateAdmission.fail("entry_publication")
	return {"ok":true,"run":run}

func prepare_entry(definition: RoomDefinition, fail_at: String = "", staging: Array = STAGING) -> Dictionary:
	if phase not in ["empty","next_room_ready"]: return StateAdmission.fail("entry_phase")
	var prior := current()
	var settings: Array = prior.settings if prior != null else []
	var catalog_result := P3Content.catalog(settings)
	if not catalog_result.ok: return catalog_result
	var admitted := RoomDefinition.admit(definition.data,catalog_result.catalog)
	if not admitted.ok: return admitted
	var board: BoardState = admitted.board
	board.id_namespace = "expedition"; board.next_instance = prior.board.next_instance if prior != null else 1
	if carry.size() > 2 or staging.size() < carry.size(): return StateAdmission.fail("staging_capacity")
	var seen := {}; var cells := {}
	for index in carry.size():
		var source: Dictionary = carry[index]; var cell: Variant = staging[index]
		if not cell is Vector2i or not board.can_enter(cell) or board.get_tile(cell) != null or cells.has(cell): return StateAdmission.fail("staging_cell")
		if seen.has(source.instance_id) or source.tier < 4: return StateAdmission.fail("carry_identity")
		seen[source.instance_id] = true; cells[cell] = true
		board.set_tile(cell,P3Content.carry_tile(source,catalog_result.catalog))
	# Admission validates every ID/allocator before any stream is drawn.
	var checked := StateAdmission.board(board.to_dict(),catalog_result.catalog)
	if not checked.ok: return checked
	var streams := prior.streams if prior != null else RngStreamBank.new(seed_value)
	var rules := prior.rules if prior != null else RuleSet.for_p3()
	var opening := OpeningGenerator.generate(board.layout_resource(),catalog_result.catalog,streams,rules,board)
	if not opening.ok: return opening
	if fail_at == "after_opening": return StateAdmission.fail("injected_after_opening")
	var candidate := prior.duplicate_state() if prior != null else RunState.new()
	candidate.board = opening.board; candidate.streams = opening.streams; candidate.catalog = catalog_result.catalog; candidate.rules = rules
	candidate.room = RoomState.new(); candidate.room.definition = admitted.definition
	candidate.room.craft = mini(6,clampi(prior.room.craft,1,3)+entry_bonus) if prior != null else 1
	candidate.moves_remaining = admitted.definition.data.work; candidate.phase = "ready"
	candidate.room_uses = {}; candidate.opening_attempts = opening.attempts
	candidate.sync_adapters()
	var validated := RunState.restored(candidate.to_dict(),false)
	if not validated.ok: return validated
	return {"ok":true,"candidate":candidate,"base":CanonicalCodec.digest(snapshot()),"index":room_index+(1 if prior != null else 0)}

func publish_entry(prepared: Dictionary, assets_ready: bool = true) -> bool:
	if not assets_ready or not prepared.get("ok",false) or prepared.get("base") != CanonicalCodec.digest(snapshot()): return false
	state = prepared.candidate; session = null; room_index = prepared.index
	phase = "briefing"; entry_bonus = 0; carry = []; offers = []; selected_reward = ""; route_cards = []
	_record({"kind":"enter_room","room_id":state.room.definition.data.id})
	room_entry = GameValue.freeze(state.to_dict())
	return true

func begin(expected_revision: int) -> Dictionary:
	if phase != "briefing" or expected_revision != revision(): return StateAdmission.fail("begin_phase_or_revision")
	phase = "playing"; _record({"kind":"begin_room"})
	session = MergeSession.new()
	if not session.start(state.to_dict()): return StateAdmission.fail("entry_session")
	return {"ok":true}

func finish_room() -> Dictionary:
	if phase != "playing" or session == null or session.phase not in ["complete","failed"]: return StateAdmission.fail("outcome_phase")
	var resolution := session.snapshot()
	state = session.state.duplicate_state(); session = null
	phase = "carry_selection" if state.phase == "complete" and room_index < 2 else "results"
	_record({"kind":"room_outcome","resolution":resolution})
	return {"ok":true}

func eligible_carry() -> Array:
	var result: Array = []
	if phase != "carry_selection": return result
	for cell in state.board.all_cells():
		var tile := state.board.get_tile(cell)
		if tile != null and tile.tier >= 4: result.append(tile.to_dict())
	return result

func confirm_carry(ids: Array, expected_revision: int) -> Dictionary:
	if phase != "carry_selection" or expected_revision != revision() or ids.size() > 2: return StateAdmission.fail("carry_phase_or_revision")
	var available := {}; var chosen: Array = []
	for tile in eligible_carry(): available[tile.instance_id] = tile
	for id in ids:
		if not id is String or not available.has(id): return StateAdmission.fail("carry_stale_or_duplicate")
		chosen.append(available[id]); available.erase(id)
	var pool := reward_pool()
	if pool.size() < 3: return StateAdmission.fail("reward_pool_exhausted")
	var streams: RngStreamBank = RngStreamBank.restored(state.streams.capture()).bank
	var choices := streams.stream("rewards").shuffle(pool).slice(0,3)
	carry = chosen; phase = "reward_selection"; offers = choices; state.streams = streams
	_record({"kind":"confirm_carry","ids":ids.duplicate()})
	return {"ok":true}

func reward_pool() -> Array:
	var result: Array = ["next_room_craft"]
	for id in ["aquamarine","steady_hand","beryl_bridge"]:
		if id not in current().settings: result.append(id)
	result.sort()
	return result

func choose_reward(id: String, expected_revision: int, assets_ready: bool = true) -> Dictionary:
	if phase != "reward_selection" or expected_revision != revision() or id not in offers: return StateAdmission.fail("reward_phase_or_choice")
	if not assets_ready: return StateAdmission.fail("reward_assets")
	selected_reward = id
	if id == "next_room_craft": entry_bonus += 1
	else: state.settings.append(id)
	if room_index == 0:
		route_cards = ["deep_seam","commission"]; phase = "route_selection"
	else: phase = "next_room_ready"
	_record({"kind":"choose_reward","id":id})
	return {"ok":true}

func choose_route(id: String, expected_revision: int) -> Dictionary:
	if phase != "route_selection" or expected_revision != revision() or id not in route_cards: return StateAdmission.fail("route_phase_or_choice")
	selected_route = id; phase = "next_room_ready"
	_record({"kind":"choose_route","id":id})
	return {"ok":true}

func prepare_next(fail_at: String = "") -> Dictionary:
	if phase != "next_room_ready": return StateAdmission.fail("entry_phase")
	var catalog_result := P3Content.catalog(state.settings)
	if not catalog_result.ok: return catalog_result
	var room := P3Rooms.definition(selected_route if room_index == 0 else "vault",catalog_result.catalog)
	if not room.ok: return room
	return prepare_entry(room.definition,fail_at)

static func restored(value: Variant, pause_timed: bool = true) -> Dictionary:
	if not StateAdmission.exact(value,["mechanical","history","session","room_entry"]) or not value.mechanical is Dictionary or not value.history is Array or value.history.is_empty() or value.history.size() > 32 or not value.session is Dictionary or not value.room_entry is Dictionary: return StateAdmission.fail("expedition_schema")
	if not value.mechanical.get("seed") is int or value.mechanical.get("schema") != 4 or value.mechanical.get("simulation") != P3Content.SIMULATION or value.mechanical.get("content") != P3Content.CONTENT: return StateAdmission.fail("expedition_version")
	var original := CanonicalCodec.encode(value)
	if original.is_empty(): return StateAdmission.fail("expedition_codec")
	var created := create(value.mechanical.seed)
	if not created.ok: return created
	var run: ExpeditionState = created.run
	if CanonicalCodec.encode(run.history[0]) != CanonicalCodec.encode(value.history[0]): return StateAdmission.fail("expedition_initial")
	for index in range(1,value.history.size()):
		var entry: Variant = value.history[index]
		if not entry is Dictionary or not entry.get("command") is Dictionary or not entry.command.get("kind") is String: return StateAdmission.fail("expedition_command")
		var command: Dictionary = entry.command; var result := {"ok":false}
		match command.kind:
			"begin_room": result = run.begin(run.revision())
			"room_outcome":
				if run.session == null or not command.get("resolution") is Dictionary: return StateAdmission.fail("expedition_outcome")
				var restored_session := MergeReplay.restored(command.resolution,false)
				if not restored_session.ok: return restored_session
				if CanonicalCodec.encode(restored_session.session.initial) != CanonicalCodec.encode(run.session.initial): return StateAdmission.fail("expedition_room_initial")
				run.session = restored_session.session; result = run.finish_room()
			"confirm_carry":
				if not command.get("ids") is Array: return StateAdmission.fail("expedition_carry")
				result = run.confirm_carry(command.ids,run.revision())
			"choose_reward":
				if not command.get("id") is String: return StateAdmission.fail("expedition_reward")
				result = run.choose_reward(command.id,run.revision())
			"choose_route":
				if not command.get("id") is String: return StateAdmission.fail("expedition_route")
				result = run.choose_route(command.id,run.revision())
			"enter_room": result = {"ok":run.publish_entry(run.prepare_next())}
		if not result.ok: return StateAdmission.fail("expedition_rejected/"+command.kind)
		if CanonicalCodec.encode(run.history.back()) != CanonicalCodec.encode(entry): return StateAdmission.fail("expedition_checkpoint")
	if run.session != null:
		var restored_session := MergeReplay.restored(value.session,false)
		if not restored_session.ok: return restored_session
		if CanonicalCodec.encode(restored_session.session.initial) != CanonicalCodec.encode(run.session.initial): return StateAdmission.fail("expedition_current_initial")
		run.session = restored_session.session
	elif not value.session.is_empty(): return StateAdmission.fail("expedition_unexpected_session")
	if CanonicalCodec.encode(run.snapshot()) != original: return StateAdmission.fail("expedition_mismatch")
	if pause_timed and run.session != null:
		run.session = MergeReplay.restored(value.session,true).session
	return {"ok":true,"run":run}

func _record(command: Dictionary) -> void:
	state.revision += 1; state.next_action += 1
	var fact := {"type":"expedition_decision","event_id":state.next_event,"action_id":state.next_action-1,"command":command.get("kind"),"room_index":room_index}
	state.next_event += 1
	var entry := {"command":command,"revision":state.revision,"event":fact,"event_digest":CanonicalCodec.digest([fact]),"state_digest":CanonicalCodec.digest(mechanical())}
	history.append(GameValue.freeze(entry))

func mechanical() -> Dictionary:
	return {"schema":4,"profile":P3Content.PROFILE,"simulation":P3Content.SIMULATION,"content":P3Content.CONTENT,
		"run_id":run_id,"seed":seed_value,"room_index":room_index,"phase":phase,"state":current().to_dict() if current() != null else {},
		"carry":carry,"entry_bonus":entry_bonus,"offers":offers,"selected_reward":selected_reward,"route_cards":route_cards,"selected_route":selected_route}

func snapshot() -> Dictionary:
	return GameValue.freeze({"mechanical":mechanical(),"history":history,"session":session.snapshot() if session != null else {},"room_entry":room_entry})
