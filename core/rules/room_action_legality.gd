class_name RoomActionLegality
extends RefCounted

static func cost(kind: String, rules: RuleSet) -> int:
	match kind:
		"action.exchange": return rules.value("exchange_cost")
		"action.clear_target": return rules.value("clear_cost")
		"action.promote_target": return rules.value("promote_cost")
	return 0

static func can_apply(state: RunState, command: Variant) -> Dictionary:
	if state.room == null or not command is RoomCommand or RoomCommand.parse(command.to_dict()) == null: return StateAdmission.fail("invalid_room_command")
	var data: Dictionary = command.data
	if data.revision != state.revision: return StateAdmission.fail("stale_revision")
	if data.kind == "begin_room":
		return {"ok":state.phase == "briefing","code":"" if state.phase == "briefing" else "invalid_phase"}
	if state.phase != "ready": return StateAdmission.fail("invalid_phase")
	if state.moves_remaining <= 0: return StateAdmission.fail("budget_exhausted")
	if data.kind != "swap":
		if not state.room.tool_available: return StateAdmission.fail("tool_already_used")
		if state.room.craft < effective_cost(data.kind,state): return StateAdmission.fail("insufficient_craft")
	var board := state.board
	if data.kind in ["swap","action.exchange"]:
		var a := board.get_tile(data.origin)
		var b := board.get_tile(data.destination)
		if a == null or b == null: return StateAdmission.fail("empty_cell")
		if a.instance_id != data.origin_id or b.instance_id != data.destination_id: return StateAdmission.fail("stale_target")
		if data.kind == "swap": return ActionLegality.can_apply(board,command.as_swap(),state.moves_remaining,state.phase)
		if board.neighbor_for(data.origin,data.destination-data.origin,"swap") != data.destination: return StateAdmission.fail("not_adjacent")
		if not board.can_move_occupant(data.origin) or not board.can_move_occupant(data.destination): return StateAdmission.fail("movement_locked")
		return {"ok":true,"code":""}
	if board.is_blocked(data.cell): return StateAdmission.fail("invalid_target")
	if data.layer == "obstacle":
		var obstacle := board.obstacle_at(data.cell)
		if data.kind != "action.clear_target" or obstacle.is_empty() or obstacle.id != data.target_id: return StateAdmission.fail("invalid_obstacle_target")
		return {"ok":true,"code":""}
	var tile := board.get_tile(data.cell)
	if tile == null or tile.instance_id != data.target_id: return StateAdmission.fail("stale_target")
	if data.layer == "lock":
		if data.kind != "action.clear_target" or board.get_cell(data.cell).lock.is_empty(): return StateAdmission.fail("invalid_lock_target")
	elif data.kind == "action.clear_target" and tile.tier > 3: return StateAdmission.fail("clear_tier_limit")
	elif data.kind == "action.promote_target" and tile.tier > 4: return StateAdmission.fail("promote_tier_limit")
	return {"ok":true,"code":""}

static func effective_cost(kind: String, state: RunState) -> int:
	if state.rules.is_p3() and kind == "action.clear_target" and "steady_hand" in state.settings and not state.room_uses.has("steady_hand"): return 1
	return cost(kind,state.rules)

static func tools(state: RunState) -> Array[RoomCommand]:
	var result: Array[RoomCommand] = []
	if state.room == null or not state.room.tool_available or state.moves_remaining <= 0 or state.phase != "ready": return result
	for pos in state.board.all_cells():
		for layer in ["obstacle","lock","gem"]:
			var clear := RoomCommand.target(state,"action.clear_target",pos,layer)
			if can_apply(state,clear).ok: result.append(clear)
		var promote := RoomCommand.target(state,"action.promote_target",pos)
		if can_apply(state,promote).ok: result.append(promote)
		for direction in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
			var exchange := RoomCommand.exchange(state,pos,pos+direction,true)
			if can_apply(state,exchange).ok: result.append(exchange)
	return result
