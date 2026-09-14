class_name RoomBoundaryResolver
extends RefCounted

static func finish(context: ActionContext) -> bool:
	var state := context.state
	state.phase = "ready"
	if state.room.remaining(state.board) == 0: state.phase = "complete"
	elif state.moves_remaining == 0:
		state.phase = "failed"; state.room.failure_reason = "work_exhausted"
	elif not ActionLegality.has_legal_swap(state.board) and RoomActionLegality.tools(state).is_empty():
		var result := RecoveryResolver.recover(context)
		if not result.ok: return false
		if not result.recovered:
			state.phase = "failed"; state.room.failure_reason = "board_locked"
	if state.phase in ["complete","failed"]:
		context.emit("room_result",{"phase":state.phase,"reason":state.room.failure_reason,"remaining":state.room.remaining(state.board)})
	return context.budget.error.is_empty()

static func validate(state: RunState) -> String:
	var room := state.room
	var complete := room.remaining(state.board) == 0
	if state.phase == "briefing":
		if state.revision != 0 or room.normal_turns != 0 or not room.tool_available or room.craft != room.definition.data.craft or room.recovery_count != 0 or not room.failure_reason.is_empty() or complete: return "inconsistent_briefing"
		if state.board.obstacles != room.definition.data.initial_board.obstacles or not ActionLegality.has_legal_swap(state.board): return "inconsistent_opening"
		return ""
	if state.revision == 0: return "room_not_started"
	if complete: return "" if state.phase == "complete" and room.failure_reason.is_empty() else "inconsistent_completion"
	if state.moves_remaining == 0: return "" if state.phase == "failed" and room.failure_reason == "work_exhausted" else "inconsistent_exhaustion"
	# Query a detached ready view; validation never reshuffles or advances RNG.
	var query := state.duplicate_state(); query.phase = "ready"
	var available := ActionLegality.has_legal_swap(state.board) or not RoomActionLegality.tools(query).is_empty()
	if state.phase == "ready" and available and room.failure_reason.is_empty(): return ""
	if state.phase == "failed" and room.failure_reason == "board_locked" and not available and room.recovery_count > 0: return ""
	return "inconsistent_room_phase"
