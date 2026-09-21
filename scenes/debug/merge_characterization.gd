class_name MergeCharacterization
extends RefCounted
## Deliberately non-shipping content: bounded diagnostic dispatch on admitted
## maximum-size boards. Counts both applied and scope-suppressed candidates.
static func run() -> Dictionary:
	var records: Array = []; var errors: Array = []
	for multiplier in [1,2]:
		for label in ["last_work_completion","last_work_exhaustion","recovery","clear","promote","exchange"]:
			var state := terminal_fixture() if label == "last_work_completion" else (recovery_fixture() if label == "recovery" else InterventionFixture.create(1 if label == "last_work_exhaustion" else 16))
			var command := InterventionFixture.command(state)
			if label in ["clear","promote","exchange"]:
				# Recompile the authored budget so external admission retains equality.
				var definition := state.room.definition.data.duplicate(true); definition.craft = 6
				state.room.definition = RoomDefinition.new(definition); state.room.craft = 6
				if label == "clear": command = RoomCommand.target(state,"action.clear_target",Vector2i(3,5),"obstacle")
				elif label == "promote": command = RoomCommand.target(state,"action.promote_target",Vector2i(0,0))
				else: command = RoomCommand.exchange(state,Vector2i.ZERO,Vector2i.RIGHT,true)
			elif label == "recovery": command = RoomCommand.exchange(state,Vector2i.ZERO,Vector2i.RIGHT,true)
			var measured := measure(state,command,multiplier,label)
			records.append_array(measured.records); errors.append_array(measured.failures)
	for width in [8,12,16]:
		var room := RoomDefinitionResource.new(); room.room_id = "merge_load_%d" % width
		room.work = 1; room.craft = 6; room.layout = BoardLayoutResource.new(); room.layout.board_size = Vector2i(width,width)
		room.obstacles = [{"id":"rubble/load","cell":Vector2i(width-1,width-1),"kind":"rubble","durability":2}]; room.marked_ids = ["rubble/load"]
		var game := RunController.new()
		if not game.start_room(room,71): errors.append("load_start/"+str(width)); continue
		game.apply_action(RoomCommand.begin(0))
		var session := MergeSession.new()
		if not session.start(game.run_state.to_dict()): errors.append("load_admission/"+str(width)); continue
		var swap := ActionLegality.enumerate_legal_swaps(session.state.board)[0]
		var before := CanonicalCodec.digest(session.mechanical_snapshot())
		var began := Time.get_ticks_usec()
		var candidate := session.prepare(RoomCommand.exchange(session.state,swap.origin,swap.destination))
		if not candidate.ok: errors.append("load_candidate/"+candidate.code); continue
		var ready_us := Time.get_ticks_usec()-began
		records.append({"kind":"supported_board","size":width,"ready_us":ready_us,"stages_us":candidate.stages_us,
			"swap_150ms_ratio":ready_us/150000.0,"shortened_swap_50ms_ratio":ready_us/50000.0,
			"candidate_digest":candidate.candidate.last_batch.state_digest})
		for multiplier in [1,4,8]:
			var source := session._detached()
			var context := MergeMoveContext.new(source.state,RoomCommand.exchange(source.state,swap.origin,swap.destination),1,"intervention")
			var applied := 0; var suppressed := 0; var calls := 0
			began = Time.get_ticks_usec()
			for repeat in multiplier:
				for cell in source.state.board.all_cells():
					var tile := source.state.board.get_tile(cell)
					if tile == null: continue
					calls += 1
					var outcome := MergeReactionScope.promote_live(context,cell,tile.instance_id,"move","load/"+tile.instance_id)
					if not outcome.ok: errors.append("dispatch/"+outcome.code); break
					if outcome.applied: applied += 1
					else: suppressed += 1
			if not RunState.restored(source.state.to_dict(),false).ok: errors.append("dispatch_admission")
			var digest := CanonicalCodec.digest({"state":source.state.to_dict(),"context":context.capture()})
			records.append({"kind":"synthetic_reaction_dispatch","size":width,"candidate_passes":multiplier,
				"calls":calls,"applied":applied,"suppressed":suppressed,"dispatch_admission_and_full_hash_us":Time.get_ticks_usec()-began,"digest":digest})
		if before != CanonicalCodec.digest(session.mechanical_snapshot()): errors.append("characterization_mutated_source")
	return {"records":records,"failures":errors,"scope":"Diagnostic candidate dispatch and near-cap boards; not authored P3 content or weaker-hardware evidence."}

static func terminal_fixture() -> RunState:
	var state := InterventionFixture.create(1)
	var resource := RoomDefinitionResource.new(); resource.room_id = "merge_terminal_release"
	resource.work = 1; resource.craft = 1; resource.layout = BoardLayoutResource.new(); resource.layout.board_size = Vector2i(4,6)
	resource.obstacles = [{"id":"rubble/end","cell":Vector2i(3,2),"kind":"rubble","durability":1}]; resource.marked_ids = ["rubble/end"]
	var room := RoomDefinition.compile(resource,state.catalog)
	state.room.definition = room.definition; state.board.remove_tile(Vector2i(3,2)); state.board.obstacles = room.board.obstacles.duplicate(true)
	state.board.set_tile(Vector2i(3,5),state.catalog.create_tile(3))
	return state

static func recovery_fixture() -> RunState:
	var rows := [[2,1,3],[1,2,1],[3,0,4]]
	var state := RunState.new(); state.catalog = GameBootstrap.catalog().catalog; state.rules = RuleSet.for_room()
	var resource := RoomDefinitionResource.new(); resource.room_id = "merge_recovery_release"
	resource.work = 16; resource.craft = 6; resource.layout = BoardLayoutResource.new(); resource.layout.board_size = Vector2i(3,3)
	resource.obstacles = [{"id":"rubble/recovery","cell":Vector2i(1,2),"kind":"rubble","durability":2}]; resource.marked_ids = ["rubble/recovery"]
	var room := RoomDefinition.compile(resource,state.catalog)
	state.board = room.board; state.room = RoomState.new(); state.room.definition = room.definition; state.room.craft = 6
	state.streams = RngStreamBank.new(1234); state.moves_remaining = 16; state.phase = "ready"
	state.revision = 1; state.next_action = 2; state.next_event = 3
	for y in 3:
		for x in 3:
			if rows[y][x] > 0: state.board.set_tile(Vector2i(x,y),state.catalog.create_tile(rows[y][x]))
	state.sync_adapters(); return state

static func measure(state: RunState, command: RoomCommand, multiplier: int, label: String) -> Dictionary:
	var result := {"records":[],"failures":[]}
	var session := MergeSession.new()
	if not session.start(state.to_dict()): result.failures.append(label+"/initial_admission"); return result
	var executor := MergeExecutor.new(session); executor.compute_multiplier = multiplier
	var interval := 150000; var count := 0
	while count < 100:
		if count == 0:
			if not executor.submit(command).ok: result.failures.append(label+"/submit"); break
		elif session.phase == "merge_window": session.presented(); executor.prepare_default(); interval = 333333
		elif session.phase == "gravity": executor.continue_gravity()
		else: break
		var packet := {}; var until := Time.get_ticks_usec()+10000000
		while packet.is_empty() and Time.get_ticks_usec() < until:
			packet = executor.poll()
			if packet.is_empty(): OS.delay_usec(100)
		if packet.is_empty(): result.failures.append(label+"/timeout"); break
		if packet.get("status") == "default_ready": session.tick(20); packet = executor.release_window()
		if not packet.ok: result.failures.append(label+"/"+packet.get("code","unknown")); break
		var metric: Dictionary = executor.metrics.back().duplicate(true)
		metric.kind = "mandatory/"+metric.kind; metric.case = label; metric.multiplier = multiplier; metric.available_us = interval
		metric.ratio = metric.latency_us/float(maxi(1,interval)); result.records.append(metric)
		if metric.latency_us > interval or (multiplier == 1 and metric.ratio > 0.5): result.failures.append(label+"/mandatory_deadline")
		if packet.batch.kind == "gravity": interval = MergeProbe.gravity_us(packet.batch)
		count += 1
	if label == "last_work_completion" and (session.phase != "complete" or session.window_id != 0 or session.state.moves_remaining != 0): result.failures.append(label+"/outcome")
	if label == "last_work_exhaustion" and session.phase not in ["complete","failed"]: result.failures.append(label+"/outcome")
	if label == "recovery" and session.state.room.recovery_count != 1: result.failures.append(label+"/not_exercised")
	if not MergeReplay.restored(session.snapshot(),false).ok: result.failures.append(label+"/replay")
	if not executor.shutdown(): result.failures.append(label+"/shutdown")
	return result
