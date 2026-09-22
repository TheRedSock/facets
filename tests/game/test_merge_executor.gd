extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _session(variant: String = "automatic_chain") -> MergeSession:
	var session := MergeSession.new()
	check(session.start(InterventionFixture.create(16,variant).to_dict()),"executor fixture")
	return session

func _await_result(executor: MergeExecutor, limit_ms: int = 4000) -> Dictionary:
	var deadline := Time.get_ticks_msec()+limit_ms
	while Time.get_ticks_msec() < deadline:
		var result := executor.poll()
		if not result.is_empty(): return result
		await process_frame
	check(false,"worker completion timeout")
	return {"ok":false,"code":"test_timeout"}

func _run() -> void:
	var session := _session()
	var reference := session._detached()
	var command := InterventionFixture.command(session.state)
	check(reference.apply(command).ok,"synchronous reference")
	var notice := Semaphore.new()
	var executor := MergeExecutor.new(session,notice)
	check(not notice.try_wait(),"CPU observer has no completion before submission")
	var received := Time.get_ticks_usec()
	check(executor.submit(command,received).ok,"paid command reserved")
	check(not executor.submit(command).ok,"MW22 only one reservation accepted")
	check(session.state.moves_remaining == 16 and session.batch_id == 0,"reservation neither charges nor commits")
	var result := await _await_result(executor)
	check(notice.try_wait() and not notice.try_wait(),"CPU observer receives exactly one paid completion")
	check(result.ok and session.batch_id == 1,"worker candidate publishes once")
	check(executor.metrics.back().submitted_us == received,"readiness includes receipt and reservation admission")
	check(executor.metrics.back().latency_us == executor.metrics.back().published_us-received,"readiness includes actual publication after notification")
	check(CanonicalCodec.encode(session.mechanical_snapshot()) == CanonicalCodec.encode(reference.mechanical_snapshot()),"threaded root equals synchronous reference")
	check(session.state.moves_remaining == 15 and session.reservation.is_empty() and session.history.size() == 1,"MW22 atomic state/cost/history publication")
	check(session.presented(),"present merge")
	check(executor.prepare_default(),"MW19 start automatic speculation")
	check(not executor.prepare_default(),"MW23 backpressure rejects duplicate queued default")
	var before := CanonicalCodec.encode(session.mechanical_snapshot())
	result = await _await_result(executor)
	check(notice.try_wait() and not notice.try_wait(),"CPU observer sees private default readiness without publishing")
	check(result.status == "default_ready" and CanonicalCodec.encode(session.mechanical_snapshot()) == before,"speculation does not advance live state")
	check(not executor.prepare_default() and executor._pending.is_empty(),"MW23 exactly one prepared default")
	check(not executor.release_window().ok,"default cannot publish early")
	check(session.tick(19),"MW20 ordinary clock update")
	check(not executor.release_window().ok,"default still cannot publish at tick 19")
	check(session.tick(20),"expiry")
	result = executor.release_window()
	check(result.ok and session.window_id == 2,"MW19 expiry publishes automatic merge and next window")
	check(session.history.back().tick == 20,"MW20 publication binds actual clock decision")
	check(not executor.release_window().ok,"duplicate publication rejected")
	check(executor.shutdown(),"worker shutdown")
	await _intervene("automatic_chain")
	await _intervene("offered")
	await _failure_and_lifecycle()
	await _gravity_boundary()
	finish("test_merge_executor")

func _gravity_boundary() -> void:
	var session := _session("offered")
	check(session.apply(InterventionFixture.command(session.state)).ok,"gravity timing root")
	session.presented()
	var executor := MergeExecutor.new(session)
	check(executor.prepare_default(),"gravity timing default submitted")
	await _await_result(executor)
	session.tick(20)
	check(executor.release_window().ok and session.phase == "gravity","gravity timing packet published")
	var presented := Time.get_ticks_usec()
	check(executor.continue_gravity(presented),"gravity follower submitted")
	var result := await _await_result(executor)
	check(result.ok and executor.metrics.back().submitted_us == presented,"gravity readiness starts at presentation boundary")
	check(executor.shutdown(),"gravity timing shutdown")

func _intervene(variant: String) -> void:
	var session := _session(variant)
	session.apply(InterventionFixture.command(session.state)); session.presented()
	var notice := Semaphore.new()
	var executor := MergeExecutor.new(session,notice)
	executor.injected_delay_us = 100000
	check(executor.prepare_default(),"start cancellable default "+variant)
	# Wait until the job actually starts, not merely until queued.
	var deadline := Time.get_ticks_msec()+1000
	while not executor._running and Time.get_ticks_msec() < deadline: await process_frame
	check(executor._running,"default worker entered")
	session.tick(19)
	var choice := RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3))
	var reference := session._detached()
	check(reference.apply(choice).ok,"non-speculative intervention reference")
	executor.injected_delay_us = 0
	var accepted_at := Time.get_ticks_usec()
	check(executor.submit(choice).ok,"MW19/20 timely intervention supersedes default")
	check(not session.tick(20),"reserved on-time input is not expired while worker runs")
	var result := await _await_result(executor)
	check(notice.try_wait() and not notice.try_wait(),"cancelled default posts no completion; replacement posts once")
	check(result.ok,"replacement command publishes")
	check(CanonicalCodec.encode(session.mechanical_snapshot()) == CanonicalCodec.encode(reference.mechanical_snapshot()),"discarded default cannot alter board/RNG/IDs/accounting "+variant)
	check(session.history.back().tick == 19,"receipt retained instead of worker completion time")
	check(executor.discarded >= 1 and executor.default_result.is_empty(),"stale candidate discarded")
	check(Time.get_ticks_usec()-accepted_at < 150000,"cancelled default does not consume entire swap interval")
	check(executor.shutdown(),"cancel case shutdown")

func _failure_and_lifecycle() -> void:
	var session := _session()
	session.apply(InterventionFixture.command(session.state)); session.presented()
	var executor := MergeExecutor.new(session)
	executor.injected_failure = "after_promotion"
	check(executor.prepare_default(),"failed speculation starts privately")
	var result := await _await_result(executor)
	check(result.status == "default_ready" and session.error.is_empty() and session.phase == "merge_window","MW19 speculative failure private")
	executor.injected_failure = ""
	check(executor.submit(RoomCommand.exchange(session.state,Vector2i(2,3),Vector2i(1,3))).ok,"discard failed branch for intervention")
	result = await _await_result(executor)
	check(result.ok and session.error.is_empty(),"unused speculative failure cannot poison accepted branch")
	check(executor.shutdown(),"private failure shutdown")
	session = _session()
	session.apply(InterventionFixture.command(session.state)); session.presented()
	executor = MergeExecutor.new(session); executor.injected_failure = "after_promotion"
	check(executor.prepare_default(),"selected failed default prepared")
	await _await_result(executor)
	var committed_board := session.state.board.to_dict()
	session.tick(20)
	result = executor.release_window()
	check(not result.ok and session.phase == "diagnostic" and session.state.board.to_dict() == committed_board,"MW19 selected speculative failure preserves committed board")
	check(executor.shutdown(),"selected default failure shutdown")
	session = _session()
	var notice := Semaphore.new()
	executor = MergeExecutor.new(session,notice); executor.injected_failure = "after_cost"
	var before := CanonicalCodec.encode(session.mechanical_snapshot())
	check(executor.submit(InterventionFixture.command(session.state)).ok,"failure command reserved")
	result = await _await_result(executor)
	check(notice.try_wait() and not notice.try_wait(),"failed demand still wakes CPU observer")
	check(not result.ok and result.status == "failed" and session.phase == "diagnostic","MW22 chosen failure enters diagnostic")
	check(session.state.moves_remaining == 16 and session.history.is_empty() and session.reservation.is_empty(),"unpublished failure releases reservation and cost")
	check(executor.shutdown(),"chosen failure shutdown")
	for cycle in 8:
		session = _session()
		executor = MergeExecutor.new(session); executor.injected_delay_us = 200000
		before = CanonicalCodec.encode(session.mechanical_snapshot())
		check(executor.submit(InterventionFixture.command(session.state)).ok,"lifecycle submitted")
		executor.cancel()
		check(executor.shutdown(),"MW21 bounded lifecycle shutdown %d" % cycle)
		check(executor.poll().is_empty() and CanonicalCodec.encode(session.mechanical_snapshot()) == before,"cancelled generation never commits")
		check(not executor._thread.is_started() and executor._pending.is_empty() and executor._completed.is_empty(),"MW21 no residual worker/mailbox")
