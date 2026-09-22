extends "res://tests/game/game_test.gd"
var phases := {}
func _initialize() -> void: _run.call_deferred()

func roundtrip(run: ExpeditionState) -> void:
	var phase := ExpeditionSave.phase_of(run); phases[phase] = true
	var bytes := ExpeditionSave.encode(run); var restored := ExpeditionSave.decode(bytes,false)
	check(restored.ok,"save phase admits "+phase+" "+str(restored.get("code","")))
	if restored.ok: check(CanonicalCodec.encode(restored.run.snapshot()) == CanonicalCodec.encode(run.snapshot()),"exact committed-boundary roundtrip "+phase)

func _run() -> void:
	var source: Dictionary = CanonicalCodec.decode(FileAccess.get_file_as_bytes("res://tests/fixtures/p3_expedition_v1/deep_seam.fac")).value
	var run: ExpeditionState = ExpeditionState.create(7).run; roundtrip(run)
	for entry in source.history.slice(1):
		var command: Dictionary = entry.command
		match command.kind:
			"begin_room": run.begin(run.revision())
			"room_outcome": run.session = MergeReplay.restored(command.resolution,false).session; run.finish_room()
			"confirm_carry": run.confirm_carry(command.ids,run.revision())
			"choose_reward": run.choose_reward(command.id,run.revision())
			"choose_route": run.choose_route(command.id,run.revision())
			"enter_room": run.publish_entry(run.prepare_next())
		roundtrip(run)
	var timed: ExpeditionState = ExpeditionState.create(1).run; timed.begin(timed.revision())
	var swaps := ActionLegality.enumerate_legal_swaps(timed.session.state.board)
	check(timed.session.apply(RoomCommand.exchange(timed.session.state,swaps[0].origin,swaps[0].destination)).ok,"timed save witness")
	timed.session.presented(); timed.session.tick(7); roundtrip(timed)
	var restored := ExpeditionSave.decode(ExpeditionSave.encode(timed))
	check(restored.ok and restored.run.session.clock.paused and restored.run.session.clock.assisted and restored.run.session.clock.tick == 7,"timed Continue is paused/assisted without offline charge")
	swaps = ActionLegality.enumerate_legal_swaps(timed.session.state.board)
	var command := RoomCommand.exchange(timed.session.state,swaps[0].origin,swaps[0].destination)
	var before := CanonicalCodec.encode(timed.snapshot())
	check(timed.session.reserve(command).ok,"accepted ticket before save")
	roundtrip(timed)
	restored = ExpeditionSave.decode(ExpeditionSave.encode(timed))
	var cost_before: int = restored.run.session.state.moves_remaining
	var executor := MergeExecutor.new(restored.run.session)
	check(executor.resume_reserved(),"restored immutable ticket recomputes candidate")
	var deadline := Time.get_ticks_msec()+5000; var result := {}
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame; result = executor.poll()
	check(result.get("ok",false) and restored.run.session.state.moves_remaining == cost_before-1,"reserved command charged exactly once")
	check(not executor.resume_reserved(),"completed reservation cannot execute twice")
	check(executor.shutdown(),"reservation worker stops")
	# Return to the exact pre-reservation committed prefix, then record a failure.
	timed = ExpeditionState.restored(CanonicalCodec.decode(before).value,false).run
	var rejected := timed.session.prepare(command,"after_cost")
	check(not rejected.ok,"diagnostic injection rejected")
	timed.session.record_failure(command.to_dict(),"after_cost",rejected.code); roundtrip(timed)
	var gravity: ExpeditionState = ExpeditionState.create(1).run; gravity.begin(gravity.revision())
	swaps = ActionLegality.enumerate_legal_swaps(gravity.session.state.board)
	gravity.session.apply(RoomCommand.exchange(gravity.session.state,swaps[0].origin,swaps[0].destination))
	for step in 50:
		if gravity.session.phase == "gravity": roundtrip(gravity); break
		if gravity.session.phase != "merge_window": break
		gravity.session.presented(); gravity.session.tick(20); gravity.session.apply()
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/p3-preparation.json"))
	for phase in spec.save_phases: check(phases.has(phase),"required save phase witnessed: "+phase)
	for large in [9007199254740993,-9007199254740993]:
		var exact: ExpeditionState = ExpeditionState.create(large).run
		var admitted := ExpeditionSave.decode(ExpeditionSave.encode(exact),false)
		check(admitted.ok and admitted.run.seed_value == large and admitted.run.state.streams.capture() == exact.state.streams.capture(),"signed >2^53 seed/RNG remains exact")
	var store := ExpeditionSave.new(); store.directory = report_path("slots")
	var prior: ExpeditionState = ExpeditionState.create(7).run
	var newer: ExpeditionState = ExpeditionState.create(8).run
	for injection in ["before_write","partial_temp","after_flush","after_verify","before_replace","after_backup"]:
		var slot: String = "fault_"+injection
		check(store.write_slot(prior,slot).ok,"prior save commits")
		check(not store.write_slot(newer,slot,injection).ok,"injected save failure "+injection)
		var loaded := store.load_slot(slot,false)
		check(loaded.ok and CanonicalCodec.encode(loaded.run.snapshot()) == CanonicalCodec.encode(prior.snapshot()),"last-known-good survives "+injection)
		check(store.write_slot(newer,slot).ok and store.load_slot(slot,false).run.seed_value == 8,"retry commits complete new save")
	check(not store.write_slot(prior,"../escape").ok and not store.load_slot("a/b").ok,"slot traversal rejected")
	var bytes := ExpeditionSave.encode(prior)
	check(not ExpeditionSave.decode(bytes.slice(0,bytes.size()-1)).ok,"truncated save rejected")
	var corrupt := bytes.duplicate(); corrupt[corrupt.size()-1] ^= 1
	check(ExpeditionSave.decode(corrupt).get("code") == "save_checksum","corrupt payload rejected before state admission")
	var decoded := CanonicalCodec.decode(bytes.slice(48)); decoded.value.save = "facets-save-atomic-p3-v1"
	var payload := CanonicalCodec.encode(decoded.value); var incompatible := ExpeditionSave.MAGIC.to_ascii_buffer()
	incompatible.resize(16); incompatible.encode_s64(8,payload.size()); incompatible.append_array(ExpeditionSave.checksum(payload)); incompatible.append_array(payload)
	check(ExpeditionSave.decode(incompatible).get("code") == "save_incompatible","unsupported version explicitly rejected")
	check(store.write_slot(prior,"recovery").ok and store.write_slot(newer,"recovery").ok,"recovery slot has valid backup")
	var file := FileAccess.open(store.path("recovery"),FileAccess.WRITE); file.store_buffer(corrupt); file.close()
	var recovered := store.load_slot("recovery",false)
	check(recovered.ok and recovered.recovered and recovered.warning == "save_checksum" and recovered.run.seed_value == 7,"Continue reports corrupt primary and admits known-good recovery")
	check(prior.seed_value == 7 and newer.seed_value == 8,"save rejection never mutates a live run")
	finish("test_p3_save")
