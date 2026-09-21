class_name MergeReplay
extends RefCounted
## External admission re-executes the committed transcript, including complete
## state/event digests. Scheduler jobs and speculative branches are never saved.

static func capture(session: MergeSession) -> Dictionary:
	if session.state == null: return {}
	return GameValue.freeze({"schema":1,"version":MergeSession.VERSION,"replay":MergeSession.REPLAY,
		"initial":session.initial,"mechanical":session.mechanical_snapshot(),"history":session.history,
		"clock":session.clock,"reservation":session.reservation,"clock_notes":session.clock_notes,
		"error":session.error,"failure":session.failure})

static func _clock_valid(value: Variant, prior: Dictionary) -> bool:
	if not StateAdmission.exact(value,["started","tick","sequence","paused","assisted"]): return false
	for key in ["started","paused","assisted"]:
		if not value[key] is bool: return false
	if not value.tick is int or value.tick < 0 or value.tick > 20 or not value.sequence is int or value.sequence < prior.sequence or value.sequence > 1000000000: return false
	if value.tick < prior.tick or (prior.assisted and not value.assisted): return false
	if not value.started and (value.tick != 0 or value.paused): return false
	return true

static func restored(value: Variant, pause_timed: bool = true) -> Dictionary:
	if not StateAdmission.exact(value,["schema","version","replay","initial","mechanical","history","clock","reservation","clock_notes","error","failure"]): return StateAdmission.fail("merge_snapshot_schema")
	if not value.schema is int or value.schema != 1 or value.version != MergeSession.VERSION or value.replay != MergeSession.REPLAY: return StateAdmission.fail("merge_snapshot_version")
	if not value.initial is Dictionary or not value.mechanical is Dictionary or not value.history is Array or value.history.size() > 10000 or not value.clock_notes is Array or value.clock_notes.size() > 10000 or not value.reservation is Dictionary or not value.failure is Dictionary or not value.error is String: return StateAdmission.fail("merge_snapshot_types")
	var original := CanonicalCodec.encode(value)
	if original.is_empty(): return StateAdmission.fail("merge_snapshot_codec")
	var session := MergeSession.new()
	if not session.start(value.initial): return StateAdmission.fail("merge_snapshot_initial")
	if not value.mechanical.get("modifiers") is Dictionary or not session.configure_modifiers(value.mechanical.modifiers): return StateAdmission.fail("merge_snapshot_modifiers")
	for entry in value.history:
		if not StateAdmission.exact(entry,["command","window","tick","sequence","assisted","state_digest","event_digest","clock","record_digest"]): return StateAdmission.fail("merge_replay_entry")
		if not entry.command is Dictionary or not entry.window is int or entry.window != session.window_id or not _clock_valid(entry.clock,session.clock): return StateAdmission.fail("merge_replay_clock")
		if entry.tick != entry.clock.tick or entry.sequence != entry.clock.sequence or entry.assisted != entry.clock.assisted: return StateAdmission.fail("merge_replay_receipt")
		session.clock = entry.clock.duplicate(true)
		var command: RoomCommand = null
		if not entry.command.is_empty():
			command = RoomCommand.parse(entry.command)
			if command == null: return StateAdmission.fail("merge_replay_command")
		var prepared := session.prepare(command)
		if not prepared.ok or not session.publish(prepared,command == null): return StateAdmission.fail("merge_replay_rejected")
		if CanonicalCodec.encode(session.history.back()) != CanonicalCodec.encode(entry): return StateAdmission.fail("merge_replay_checkpoint")
	if not _clock_valid(value.clock,session.clock): return StateAdmission.fail("merge_snapshot_clock")
	session.clock = value.clock.duplicate(true)
	if not value.failure.is_empty():
		if not StateAdmission.exact(value.failure,["command","injection","code","phase"]) or not value.failure.command is Dictionary or not value.failure.injection is String or value.failure.phase != session.phase: return StateAdmission.fail("merge_failure_record")
		var command: RoomCommand = null if value.failure.command.is_empty() else RoomCommand.parse(value.failure.command)
		if command == null and not value.failure.command.is_empty(): return StateAdmission.fail("merge_failure_command")
		var failed := session.prepare(command,value.failure.injection)
		if failed.ok or failed.code != value.failure.code: return StateAdmission.fail("merge_failure_mismatch")
		session.record_failure(value.failure.command,value.failure.injection,value.failure.code)
	if not value.reservation.is_empty():
		if not StateAdmission.exact(value.reservation,["command","revision","window","tick","sequence","cost","context"]) or not value.reservation.command is Dictionary: return StateAdmission.fail("merge_reservation_schema")
		var command := RoomCommand.parse(value.reservation.command)
		if command == null or not session.reserve(command).ok or session.reservation != value.reservation: return StateAdmission.fail("merge_reservation_mismatch")
	for note in value.clock_notes:
		if not note is Dictionary or note.get("kind") not in ["presented","pause","explicit_pass","assist"] or not note.get("window") is int or note.window < 0 or note.window > session.window_id or not note.get("tick") is int or note.tick < 0 or note.tick > 20: return StateAdmission.fail("merge_clock_note")
		if note.kind in ["pause","assist"] and note.get("reason") not in ["manual","focus","render_stall","restore","practice","resize"]: return StateAdmission.fail("merge_clock_reason")
		var keys := ["kind","window","tick"]
		if note.kind in ["pause","assist"]: keys.append("reason")
		if note.kind == "pause":
			keys.append("paused")
			if not note.get("paused") is bool: return StateAdmission.fail("merge_clock_pause")
		if not StateAdmission.exact(note,keys): return StateAdmission.fail("merge_clock_note_schema")
		if note.kind != "presented" and not session.clock.assisted: return StateAdmission.fail("merge_assistance_unmarked")
	session.clock_notes = value.clock_notes.duplicate(true)
	if CanonicalCodec.encode(capture(session)) != original: return StateAdmission.fail("merge_snapshot_mismatch")
	# Verification above is exact. Resuming a timed decision is an explicit new
	# assisted state, never charged for offline time. Reservations remain accepted.
	if pause_timed and session.phase == "merge_window":
		session.clock.assisted = true
		if session.reservation.is_empty():
			session.clock.started = true; session.clock.paused = true; session.clock.sequence += 1
		session.clock_notes.append({"kind":"pause","reason":"restore","paused":session.clock.paused,"window":session.window_id,"tick":session.clock.tick})
	return {"ok":true,"session":session}
