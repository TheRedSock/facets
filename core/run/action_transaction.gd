class_name ActionTransaction
extends RefCounted

static func resolve(current: RunState, command: Variant, fail_at: String = "") -> Dictionary:
	if current.room != null: return RoomTransaction.resolve(current,command,fail_at)
	if not command is SwapCommand: return {"ok":false,"status":"rejected","code":"invalid_command"}
	var legal := ActionLegality.can_apply(current.board,command,current.moves_remaining,current.phase)
	if not legal.ok: return {"ok": false, "status": "rejected", "code": legal.code}
	var before := current.board.duplicate_board()
	var candidate := current.duplicate_state()
	if not candidate.board.swap_cells(command.origin,command.destination): return failure("swap_failed")
	if fail_at == "after_swap": return failure("injected_after_swap")
	candidate.moves_remaining -= 1
	var controller := TurnController.new(candidate.catalog); controller.rules = candidate.rules
	controller.capture_step_hashes = false
	controller.fail_at = fail_at
	var timeline := controller.execute_turn(candidate.board,candidate.streams.stream("board"),candidate.catalog.supply(),EventLog.new(),[command.origin,command.destination])
	if not timeline.failure_code.is_empty(): return failure(timeline.failure_code)
	candidate.phase = "budget_exhausted" if candidate.moves_remaining == 0 else ("no_legal_swaps" if not ActionLegality.has_legal_swap(candidate.board) else "ready")
	var facts := RuleFactBuilder.new().build(candidate,command,before,timeline)
	if facts.size() > int(candidate.rules.value("max_facts")): return failure("fact_cap")
	candidate.next_action += 1; candidate.revision += 1
	if fail_at == "before_commit": return failure("injected_before_commit")
	var admitted := RunState.restored(candidate.to_dict())
	if not admitted.ok: return failure("invariant/" + admitted.code)
	timeline = EventTimeline.from_facts(facts)
	return {"ok": true, "status": "committed", "code": "", "state": candidate, "timeline": timeline,
		"before": before, "after": candidate.board.duplicate_board(), "command": command.to_dict(),
		"action_id": current.next_action, "revision": candidate.revision, "state_digest": candidate.digest(), "event_digest": CanonicalCodec.digest(facts), "facts": facts}

static func failure(code: String) -> Dictionary:
	return {"ok": false, "status": "failed", "code": code}
