class_name MergeExecutor
extends RefCounted
## Main thread owns session/publication. Worker owns detached job/candidate until
## transferring its sole reference through the protected completion mailbox.
var session: MergeSession
var default_result := {}
var metrics: Array = []
var compute_multiplier := 1
var injected_delay_us := 0
var injected_failure := ""
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending := {}
var _completed := {}
var _generation := 0
var _stopping := false
var _running := false
var _kind := ""
var _submitted_us := 0
var discarded := 0
## Optional CPU-harness notification. The playable room never blocks on it.
## Set before thread startup; only the worker posts, after filling the mailbox.
var _completion_notice: Semaphore

func _init(model: MergeSession, completion_notice: Semaphore = null) -> void:
	session = model
	_completion_notice = completion_notice
	CanonicalCodec.seal_shared_cache()
	var code := _thread.start(_work)
	if code != OK: _stopping = true

func submit(command: RoomCommand, received_us: int = 0) -> Dictionary:
	var began := received_us if received_us > 0 else Time.get_ticks_usec()
	if _stopping: return StateAdmission.fail("executor_stopped")
	var admitted := session.reserve(command)
	if not admitted.ok: return admitted
	default_result = {}
	_queue("command",command,began)
	return admitted

func prepare_default() -> bool:
	if _stopping or session.phase != "merge_window" or not session.reservation.is_empty(): return false
	if not default_result.is_empty() or busy(): return false
	_queue("default",null)
	return true

func continue_gravity(presented_us: int = 0) -> bool:
	if _stopping or session.phase != "gravity" or busy(): return false
	_queue("gravity",null,presented_us)
	return true

func _queue(kind: String, command: RoomCommand, boundary_us: int = 0) -> void:
	_submitted_us = boundary_us if boundary_us > 0 else Time.get_ticks_usec()
	# Immutable catalog/rules/definition may be shared; all mutable state is copied.
	var source := session._detached()
	_mutex.lock()
	_generation += 1
	_pending = {"kind":kind,"source":source,"command":command,"generation":_generation,
		"submitted_us":_submitted_us,"multiplier":compute_multiplier,"delay_us":injected_delay_us,"failure":injected_failure}
	_completed = {}; _kind = kind
	_mutex.unlock()
	_wake.post()

func busy() -> bool:
	_mutex.lock()
	var result := _running or not _pending.is_empty() or not _completed.is_empty()
	_mutex.unlock()
	return result

func _cancelled(generation: int) -> bool:
	_mutex.lock()
	var result := _stopping or generation != _generation
	_mutex.unlock()
	return result

func _work() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		if _stopping: _mutex.unlock(); return
		var job := _pending; _pending = {}
		if job.is_empty(): _mutex.unlock(); continue
		_running = true
		_mutex.unlock()
		var began := Time.get_ticks_usec()
		var cancel: Callable = func() -> bool: return _cancelled(job.generation)
		var result: Dictionary = job.source.prepare(job.command,job.failure,cancel)
		var computed := Time.get_ticks_usec()-began
		var extra: int = job.delay_us+maxi(0,job.multiplier-1)*computed
		var until := Time.get_ticks_usec()+extra
		# Diagnostic delay has sub-millisecond cancellation checkpoints and never
		# sleeps the renderer. Normal computation checks cancellation in its budget.
		while Time.get_ticks_usec() < until and not cancel.call():
			# Time can cross the deadline between the loop guard and this read.
			OS.delay_usec(clampi(until-Time.get_ticks_usec(),0,500))
		_mutex.lock()
		_running = false
		if not _stopping and job.generation == _generation:
			_completed = {"generation":job.generation,"kind":job.kind,"result":result,
				"submitted_us":job.submitted_us,"service_us":computed,"ready_us":Time.get_ticks_usec(),
				"command":job.command.to_dict() if job.command != null else {},"injection":job.failure}
			if _completion_notice != null: _completion_notice.post()
		else: discarded += 1
		_mutex.unlock()

## Returns a committed packet, private default readiness, or an explicit failure.
func poll() -> Dictionary:
	_mutex.lock()
	var done := _completed; _completed = {}
	var generation := _generation
	_mutex.unlock()
	if done.is_empty(): return {}
	if done.generation != generation: return {}
	if done.kind == "default":
		default_result = done
		return {"ok":true,"status":"default_ready"}
	return _publish(done)

func release_window() -> Dictionary:
	if session.phase != "merge_window" or not session.clock.started or session.clock.tick < MergeSession.WINDOW_TICKS or not session.reservation.is_empty(): return StateAdmission.fail("window_not_expired")
	if default_result.is_empty(): return {"ok":false,"code":"not_ready","status":"waiting"}
	var done := default_result; default_result = {}
	return _publish(done,true)

func _publish(done: Dictionary, release: bool = false) -> Dictionary:
	var began := Time.get_ticks_usec()
	var result: Dictionary = done.result
	var committed: bool = result.ok and session.publish(result,release)
	var now := Time.get_ticks_usec()
	metrics.append({"kind":done.kind,"service_us":done.service_us,"ready_us":done.ready_us,
		"submitted_us":done.submitted_us,"published_us":now,"latency_us":now-done.submitted_us,"committed":committed,
		"publication_us":now-began,"stages_us":result.get("stages_us",{})})
	if not committed:
		session.reservation = {}
		if result.ok: return {"ok":false,"status":"rejected","code":"stale_publication"}
		session.record_failure(done.command,done.injection,result.code)
		return {"ok":false,"status":"failed","code":result.code}
	return {"ok":true,"status":"committed","batch":session.last_batch}

func resume_reserved() -> bool:
	if session.reservation.is_empty() or _stopping or busy(): return false
	_queue("command",RoomCommand.parse(session.reservation.command))
	return true

func cancel() -> void:
	_mutex.lock()
	_generation += 1; _pending = {}; _completed = {}
	_mutex.unlock()
	default_result = {}; session.reservation = {}

func shutdown(timeout_ms: int = 2000) -> bool:
	if not _thread.is_started(): return true
	cancel()
	_mutex.lock(); _stopping = true; _mutex.unlock(); _wake.post()
	var deadline := Time.get_ticks_msec()+timeout_ms
	while _thread.is_alive() and Time.get_ticks_msec() < deadline: OS.delay_usec(500)
	if _thread.is_alive(): return false # Keep owner alive; never free a live worker.
	_thread.wait_to_finish()
	return true
