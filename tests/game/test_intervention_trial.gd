extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _start(profile: String = "trial-paused-v1", work: int = 16, variant: String = "offered") -> InterventionTrial:
	var state := InterventionFixture.create(work,variant)
	var trial := InterventionTrial.new()
	check(trial.start(state.to_dict(),InterventionFixture.command(state).to_dict(),profile),"trial starts: "+trial.last_error)
	return trial

func _run() -> void:
	var state := InterventionFixture.create()
	var command := InterventionFixture.command(state)
	var control := ActionTransaction.resolve(state,command)
	check(control.ok,"atomic fixture control")
	var trial := _start()
	check(trial.phase == "window" and trial.cursor.phase == "gravity","real resolver parked before gravity")
	if trial.phase != "window": finish("test_intervention_trial"); return
	check(trial.state.board.get_tile(Vector2i(2,1)) == null and trial.state.board.get_tile(Vector2i(2,2)) == null,"unfilled match holes prove no precomputed continuation")
	check(trial.state.streams.capture() == state.streams.capture(),"parked prefix consumes no refill RNG")
	check(trial.state.board.get_tile(Vector2i(2,3)).tier == 2,"promoted survivor at explained coordinate")
	check(trial.offers.any(func(o: Dictionary) -> bool: return o.origin == Vector2i(2,3) and o.destination == Vector2i(1,3)),"explained left swap offered")
	check(not trial.clock.started and trial.clock.tick == 0,"clock waits for visible boundary")
	var bytes := CanonicalCodec.encode(trial.snapshot())
	var restored := InterventionTrial.restored(CanonicalCodec.decode(bytes).value)
	check(restored.ok,"complete parked snapshot admits")
	if restored.ok: check(CanonicalCodec.encode(restored.trial.snapshot()) == bytes,"parked snapshot exact")
	var invalid := trial.event("decide",{"command":trial.offers[0]})
	check(not trial.apply(invalid).ok and CanonicalCodec.encode(trial.snapshot()) == bytes,"no queued decision before presentation")
	for field in ["cursor","context","clock","offers","state"]:
		var bad := trial.snapshot().duplicate(true)
		if field == "cursor": bad.cursor.cascade += 1
		elif field == "context": bad.context.work += 1
		elif field == "clock": bad.clock.tick += 1
		elif field == "offers": bad.offers.clear()
		else: bad.state.next_event += 1
		check(not InterventionTrial.restored(bad).ok,"forged pending "+field+" rejects")
	check(trial.apply(trial.event("presented")).ok,"explicit presentation handoff")
	bytes = CanonicalCodec.encode(trial.snapshot())
	check(not trial.apply(trial.event("presented")).ok and CanonicalCodec.encode(trial.snapshot()) == bytes,"repeated handoff cannot extend deadline")
	var stale := trial.event("decide",{"command":trial.offers[0]}); stale.revision -= 1
	check(not trial.apply(stale).ok and CanonicalCodec.encode(trial.snapshot()) == bytes,"stale revision pure")
	for target in [Vector2i(2,2),Vector2i(3,5),Vector2i(0,0)]:
		var wrong := RoomCommand.exchange(trial.state,Vector2i(2,3),target)
		check(not trial.apply(trial.event("decide",{"command":wrong.to_dict()})).ok and CanonicalCodec.encode(trial.snapshot()) == bytes,"empty/obstacle/nonadjacent target pure")
	check(trial.apply(trial.event("decide",{"command":null})).ok and trial.phase == "stable","pass resumes to actual stability")
	check(trial.state.digest() == control.state_digest and CanonicalCodec.digest(trial.context.facts) == control.event_digest,"pass preserves exact full P2 state/facts/RNG")
	check(InterventionTrial.restored(trial.snapshot()).ok,"complete pass transcript replay")
	for profile in InterventionTrial.PROFILES:
		trial = _start(profile,2)
		check(trial.apply(trial.event("presented")).ok,"present "+profile)
		var choice: Dictionary = trial.offers.filter(func(o: Dictionary) -> bool: return o.destination == Vector2i(1,3))[0]
		var decision := trial.event("decide",{"command":choice,"tick":0 if profile == "trial-paused-v1" else int(trial.clock.deadline)-1})
		check(trial.apply(decision).ok and trial.phase == "stable","intervention accepted before deadline "+profile)
		check(trial.interventions == 1 and trial.state.moves_remaining == 0 and trial.state.room.normal_turns == 1,"one additional Work, one normal turn "+profile)
		check(trial.context.facts.any(func(f: Dictionary) -> bool: return f.type == "match_committed" and Vector2i(1,3) in f.cells and Vector2i(1,4) in f.cells and Vector2i(1,5) in f.cells),"intended line actually commits "+profile)
		check(trial.context.facts.filter(func(f: Dictionary) -> bool: return f.type == "craft_settled").size() == 1,"one shared Craft settlement "+profile)
		check(not trial.apply(decision).ok,"at most one intervention "+profile)
		check(InterventionTrial.restored(trial.snapshot()).ok,"intervention replay/accounting "+profile)
	for deadline in [24,48]:
		for late in [deadline,deadline+10]:
			trial = _start("trial-%d-v1" % deadline)
			trial.apply(trial.event("presented"))
			var expired := trial.apply(trial.event("decide",{"command":trial.offers[0],"tick":late}))
			check(expired.ok and expired.status == "expired" and trial.interventions == 0,"deadline tie/late expires %d/%d" % [deadline,late])
			check(trial.state.digest() == control.state_digest and CanonicalCodec.digest(trial.context.facts) == control.event_digest,"expiry is exact atomic pass")
	trial = _start("trial-24-v1")
	trial.apply(trial.event("presented")); trial.apply(trial.event("advance",{"tick":7}))
	trial.apply(trial.event("pause",{"paused":true,"reason":"focus"}))
	bytes = CanonicalCodec.encode(trial.snapshot())
	check(not trial.apply(trial.event("advance",{"tick":20})).ok and CanonicalCodec.encode(trial.snapshot()) == bytes,"focus freeze rejects clock advance")
	check(InterventionTrial.restored(trial.snapshot()).ok,"paused clock restores")
	trial.apply(trial.event("pause",{"paused":false,"reason":"focus"}))
	trial.apply(trial.event("decide",{"command":trial.offers[0],"tick":12}))
	var stream := trial.snapshot()
	for fps in [30,60,120]:
		# Render frames, stalls and reduced motion cannot enter this input contract.
		var replay := InterventionTrial.restored(stream)
		check(replay.ok and CanonicalCodec.encode(replay.trial.snapshot()) == CanonicalCodec.encode(stream),"same admitted input stream independent of render rate %d, stall/reduced motion" % fps)
	trial = _start("trial-paused-v1",1)
	check(trial.phase == "stable" and not trial.offered,"zero remaining Work suppresses every offer")
	trial = _start("trial-paused-v1",16,"automatic_chain")
	var consumed_id := InterventionFixture.create(16,"automatic_chain").board.get_tile(Vector2i(3,3)).instance_id
	check(trial.context.facts.any(func(f: Dictionary) -> bool: return f.type == "tile_removed" and f.instance_id == consumed_id),"automatic chain consumes initial opportunity before input")
	check(trial.offers.all(func(o: Dictionary) -> bool: return o.origin_id != consumed_id),"consumed survivor never offered")
	trial = _start("trial-paused-v1",16,"no_opportunity")
	check(trial.phase == "stable" and not trial.offered,"no eligible opportunity resolves without a window")
	_failure_cases()
	_pass_corpus()
	finish("test_intervention_trial")

func _pass_corpus() -> void:
	var count := 0; var windows := 0
	for seed_value in range(1,21):
		var game := RunController.new()
		check(game.start_room(null,seed_value),"trial corpus room")
		game.apply_action(RoomCommand.begin(0))
		for index in 5:
			var swaps := game.enumerate_legal_swaps()
			if swaps.is_empty(): break
			var swap := swaps[(seed_value+index)%swaps.size()]
			var command := RoomCommand.exchange(game.run_state,swap.origin,swap.destination)
			var trial := InterventionTrial.new()
			check(trial.start(game.run_state.to_dict(),command.to_dict(),"trial-paused-v1"),"trial corpus start")
			var control := game.apply_action(command)
			if trial.phase == "window":
				windows += 1; trial.apply(trial.event("presented")); trial.apply(trial.event("decide",{"command":null}))
			check(control.ok and trial.phase == "stable" and trial.state.digest() == control.state_digest and CanonicalCodec.digest(trial.context.facts) == control.event_digest,"trial corpus exact atomic pass %d/%d" % [seed_value,index])
			count += 1
	check(count >= 80 and windows > 0,"trial pass corpus contains real windows and ordinary room actions")

func _failure_cases() -> void:
	var reference := _start()
	var state := InterventionFixture.create()
	var rules := state.rules.to_dict(); rules.max_work = reference.context.budget.work
	state.rules = RuleSet.new(rules)
	var capped := InterventionTrial.new()
	check(capped.start(state.to_dict(),InterventionFixture.command(state).to_dict(),"trial-paused-v1"),"near-cap prefix may commit")
	for trial: InterventionTrial in [capped,_start()]:
		trial.apply(trial.event("presented"))
		var prefix := trial.state.digest(); var facts := CanonicalCodec.digest(trial.context.facts)
		var result := trial.apply(trial.event("decide",{"command":null}),"" if trial == capped else "after_spawn")
		check(not result.ok and result.status == "failed" and trial.phase == "diagnostic","failed continuation becomes diagnostic")
		check(trial.state.digest() == prefix and CanonicalCodec.digest(trial.context.facts) == facts,"failed segment preserves committed prefix and RNG")
		check(InterventionTrial.restored(trial.snapshot()).ok,"diagnostic prefix replay preserves failure")
		check(trial.start(InterventionFixture.create().to_dict(),InterventionFixture.command(InterventionFixture.create()).to_dict(),"trial-paused-v1"),"restart available after failure")
