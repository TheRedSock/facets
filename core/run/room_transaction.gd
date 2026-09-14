class_name RoomTransaction
extends RefCounted
## P2 orchestration reuses the existing merge/settling implementation.

static func resolve(current: RunState, command: Variant, fail_at: String = "") -> Dictionary:
	var legal := RoomActionLegality.can_apply(current,command)
	if not legal.ok: return {"ok":false,"status":"rejected","code":legal.code}
	var state := current.duplicate_state()
	var context := ActionContext.new(state,command)
	if command.data.kind == "begin_room":
		state.phase = "ready"
		context.emit("room_started",{"room_id":state.room.definition.data.id})
	else:
		if command.data.kind == "swap":
			state.moves_remaining -= 1; state.room.normal_turns += 1; state.room.tool_available = true
			context.emit("resource_spent",{"resource":"resource.action_budget","amount":1,"remaining":state.moves_remaining})
		else:
			var cost := RoomActionLegality.cost(command.data.kind,state.rules)
			state.room.craft -= cost; state.room.tool_available = false
			context.emit("tool_activated",{"kind":command.data.kind,"cost":cost})
			context.emit("resource_spent",{"resource":"resource.tactic_charge","amount":cost,"remaining":state.room.craft})
		context.emit("tool_allowance",{"available":state.room.tool_available})
		if not context.budget.error.is_empty(): return ActionTransaction.failure(context.budget.error)
		if fail_at == "after_cost": return ActionTransaction.failure("injected_after_cost")
		if not ToolResolver.apply(context,command): return ActionTransaction.failure("root_effect_failed")
		if fail_at in ["after_target","after_swap"]: return ActionTransaction.failure("injected_"+fail_at)
		var resolver := TurnController.new(state.catalog)
		resolver.rules = state.rules; resolver.capture_step_hashes = false; resolver.fail_at = fail_at
		var pair: Array[Vector2i] = []
		if command.data.kind in ["swap","action.exchange"]: pair.assign([command.data.origin,command.data.destination])
		var timeline := resolver.execute_turn(state.board,state.streams.stream("board"),state.catalog.supply(),EventLog.new(),pair,context)
		if not timeline.failure_code.is_empty(): return ActionTransaction.failure(timeline.failure_code)
		CraftPolicy.settle(context)
		if fail_at == "after_craft": return ActionTransaction.failure("injected_after_craft")
		if not RoomBoundaryResolver.finish(context): return ActionTransaction.failure(context.budget.error)
	context.emit("action_settled",{"budget":state.moves_remaining,"phase":state.phase,"work":context.budget.work})
	if not context.budget.error.is_empty(): return ActionTransaction.failure(context.budget.error)
	state.next_action += 1; state.revision += 1
	if fail_at == "before_commit": return ActionTransaction.failure("injected_before_commit")
	var admitted := RunState.restored(state.to_dict())
	if not admitted.ok: return ActionTransaction.failure("invariant/"+admitted.code)
	var facts: Array = GameValue.freeze(context.facts)
	return {"ok":true,"status":"committed","code":"","state":state,"timeline":EventTimeline.from_facts(facts),
		"before":current.board.duplicate_board(),"after":state.board.duplicate_board(),"command":command.to_dict(),
		"action_id":current.next_action,"revision":state.revision,"state_digest":state.digest(),
		"event_digest":CanonicalCodec.digest(facts),"facts":facts}
