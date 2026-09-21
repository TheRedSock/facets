class_name MergeClock
extends RefCounted
## Converts receipt time to explicit integer decisions. Frame rate is not a rule.
var session: MergeSession
var automatic := true
var _previous_us := 0
var _elapsed_us := 0
var decisions: Array = []

func _init(model: MergeSession) -> void: session = model

func presented(now_us: int) -> bool:
	if not session.presented(): return false
	_previous_us = now_us; _elapsed_us = 0
	decisions.append({"kind":"presented","window":session.window_id,"tick":0})
	return true

func advance(now_us: int) -> void:
	if not automatic or session.phase != "merge_window" or not session.clock.started or not session.reservation.is_empty(): return
	var delta := maxi(0,now_us-_previous_us); _previous_us = now_us
	if session.clock.paused: return
	if delta > 100000: pause(true,"render_stall"); return
	_elapsed_us += delta
	var tick := mini(20,int(_elapsed_us*60/1000000))
	if tick > session.clock.tick: session.tick(tick)

func pause(paused: bool, reason: String) -> bool:
	if reason not in ["manual","focus","render_stall","restore","practice"] or session.phase != "merge_window" or not session.clock.started or not session.reservation.is_empty(): return false
	session.clock.paused = paused; session.clock.assisted = true; session.clock.sequence += 1
	_previous_us = Time.get_ticks_usec()
	decisions.append({"kind":"pause","reason":reason,"paused":paused,"window":session.window_id,"tick":session.clock.tick})
	return true

func pass_now() -> bool:
	if session.phase != "merge_window" or not session.clock.started or not session.reservation.is_empty(): return false
	session.clock.paused = false; session.clock.assisted = true
	decisions.append({"kind":"explicit_pass","window":session.window_id,"tick":session.clock.tick})
	return session.tick(20)
