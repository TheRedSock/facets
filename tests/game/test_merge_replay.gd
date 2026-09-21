extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _session() -> MergeSession:
	var result := MergeSession.new()
	var state := InterventionFixture.create(16,"automatic_chain")
	state.streams = RngStreamBank.new(9007199254740993)
	check(result.start(state.to_dict()),"replay initial exact integer seed")
	return result

func _roundtrip(session: MergeSession, label: String) -> void:
	var bytes := CanonicalCodec.encode(session.snapshot())
	var decoded := CanonicalCodec.decode(bytes)
	check(decoded.ok,"FAC1 complete envelope "+label)
	var admitted := MergeReplay.restored(decoded.value,false)
	check(admitted.ok,"MW24 complete restore "+label+": "+str(admitted.get("code","")))
	if admitted.ok:
		check(CanonicalCodec.encode(admitted.session.snapshot()) == bytes,"exact checkpoint "+label)
		check(admitted.session.state.streams.master_seed == 9007199254740993,"MW25 >2^53 seed retained")

func _run() -> void:
	var session := _session()
	_roundtrip(session,"ready")
	var command := InterventionFixture.command(session.state)
	check(session.reserve(command).ok,"reserve root before save")
	_roundtrip(session,"reserved equilibrium command")
	var admitted := MergeReplay.restored(session.snapshot())
	check(admitted.ok,"reserved snapshot default admission")
	if not admitted.ok: finish("test_merge_replay"); return
	var restored: MergeSession = admitted.session
	var executor := MergeExecutor.new(restored)
	check(executor.resume_reserved(),"pending command reconstructs from immutable ticket")
	var end := Time.get_ticks_msec()+3000
	while restored.batch_id == 0 and Time.get_ticks_msec() < end:
		executor.poll(); await process_frame
	check(restored.batch_id == 1 and restored.state.moves_remaining == 15,"restored reservation charges exactly once")
	check(executor.shutdown(),"reserved restore executor shutdown")
	session = restored
	_roundtrip(session,"unpresented automatic-match barrier")
	var clock := MergeClock.new(session); clock.presented(Time.get_ticks_usec()); session.tick(7)
	_roundtrip(session,"presented tick 7")
	admitted = MergeReplay.restored(session.snapshot())
	check(admitted.ok and admitted.session.clock.paused and admitted.session.clock.assisted and admitted.session.clock.tick == 7,"restored timed window pauses without offline time")
	if admitted.ok: _roundtrip(admitted.session,"assisted restored window")
	clock.pause(true,"focus"); _roundtrip(session,"focus pause")
	clock.pause(false,"focus")
	var choice := RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3))
	check(session.reserve(choice).ok,"reserve intervention")
	_roundtrip(session,"reserved intervention")
	admitted = MergeReplay.restored(session.snapshot())
	check(admitted.ok,"accepted intervention survives assisted restoration")
	if admitted.ok:
		session = admitted.session; executor = MergeExecutor.new(session); executor.resume_reserved()
		end = Time.get_ticks_msec()+3000
		while session.move_id < 2 and Time.get_ticks_msec() < end:
			executor.poll(); await process_frame
		check(executor.shutdown() and session.move_id == 2,"resumed intervention commits once")
		_roundtrip(session,"intervention committed")
	var steps := 0
	while session.phase in ["merge_window","gravity"] and steps < 100:
		if session.phase == "merge_window":
			if not session.clock.started: session.presented()
			session.tick(20)
		var result := session.apply()
		check(result.ok,"replay continuation")
		if not result.ok: break
		_roundtrip(session,session.phase)
		steps += 1
	check(steps < 100 and session.phase in ["ready","complete","failed"],"all pending work reaches a stable/result boundary")
	_rejections(session)
	var short := InterventionFixture.create(1,"automatic_chain"); short.streams = RngStreamBank.new(9007199254740993)
	session = MergeSession.new(); check(session.start(short.to_dict()),"terminal replay fixture")
	session.apply(InterventionFixture.command(session.state)); steps = 0
	while session.phase in ["merge_window","gravity"] and steps < 100:
		if session.phase == "merge_window": session.presented(); session.tick(20)
		check(session.apply().ok,"terminal transcript continuation"); steps += 1
	check(session.phase in ["complete","failed"],"terminal result reached")
	_roundtrip(session,"terminal result")
	session = _session(); session.configure_modifiers(MergeModifiers.DEFAULTS.merged({"discount_charges":1,"reward_bonus":1},true))
	session.apply(InterventionFixture.command(session.state)); session.presented()
	check(session.apply(RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3))).ok,"discount transcript input")
	_roundtrip(session,"discounted intervention accounting")
	await _failure()
	finish("test_merge_replay")

func _rejections(session: MergeSession) -> void:
	var saved := session.snapshot()
	for field in ["phase","cursor","context","state","batch_id","window_id"]:
		var bad := saved.duplicate(true)
		if field == "phase": bad.mechanical.phase = "ready" if bad.mechanical.phase != "ready" else "gravity"
		elif field == "cursor": bad.mechanical.cursor.chain += 1
		elif field == "context": bad.mechanical.context.entitlement += 1
		elif field == "state": bad.mechanical.state.next_event += 1
		else: bad.mechanical[field] += 1
		check(not MergeReplay.restored(bad,false).ok,"MW25 forged complete state rejects "+field)
	var bad := saved.duplicate(true); bad.version = "facets-replay-v2"
	check(not MergeReplay.restored(bad).ok,"wrong protocol rejected")
	bad = saved.duplicate(true); bad.history.pop_back()
	check(not MergeReplay.restored(bad).ok,"truncated history cannot admit later state")
	bad = saved.duplicate(true); bad.clock.tick = 21
	check(not MergeReplay.restored(bad).ok,"out-of-range clock rejects")
	bad = saved.duplicate(true); bad.history[0].record_digest = "forged"
	check(not MergeReplay.restored(bad).ok,"decision chain digest checked")
	bad = saved.duplicate(true); bad.history[0].tick = 19
	check(not MergeReplay.restored(bad).ok,"inconsistent receipt fields reject")
	check(not RunState.restored(saved).ok,"successor envelope cannot masquerade as a legacy save")
	check(CanonicalCodec.encode(session.snapshot()) == CanonicalCodec.encode(saved),"rejected imports do not mutate live state")

func _failure() -> void:
	var session := _session(); session.apply(InterventionFixture.command(session.state)); session.presented(); session.tick(20)
	var executor := MergeExecutor.new(session); executor.injected_failure = "after_promotion"
	check(executor.prepare_default(),"diagnostic default prepared")
	var end := Time.get_ticks_msec()+3000
	while executor.default_result.is_empty() and Time.get_ticks_msec() < end:
		executor.poll(); await process_frame
	check(not executor.release_window().ok and session.phase == "diagnostic","selected failure recorded")
	_roundtrip(session,"diagnostic committed prefix")
	check(executor.shutdown(),"diagnostic worker shutdown")
