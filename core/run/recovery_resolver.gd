class_name RecoveryResolver
extends RefCounted

static func recover(context: ActionContext) -> Dictionary:
	var state := context.state
	var original := state.board
	var cells: Array[Vector2i] = []
	var pieces: Array = []
	for pos in original.all_cells():
		if original.can_move_occupant(pos) and original.get_tile(pos).tier <= 3:
			cells.append(pos); pieces.append(original.get_tile(pos))
	var attempts := 0
	var recovered := false
	var before: Array = []
	for i in cells.size(): before.append({"cell":cells[i],"instance_id":pieces[i].instance_id})
	if cells.size() >= 2:
		for attempt in int(state.rules.value("max_recoveries")):
			if not context.budget.spend(cells.size()+original.size.x*original.size.y*8): return {"ok":false,"code":context.budget.error}
			attempts = attempt+1
			var candidate := original.duplicate_board()
			var shuffled := state.streams.stream("recovery").shuffle(pieces)
			for i in cells.size(): candidate.set_tile(cells[i],shuffled[i].duplicate_tile())
			var physics := BoardPhysics.new()
			if physics._has_move(candidate,candidate.all_cells()) or not physics.find_spawn_eligible_cells(candidate).is_empty(): continue
			if not MatchDetector.new().find_matches(candidate).is_empty() or not ActionLegality.has_legal_swap(candidate): continue
			state.board = candidate; recovered = true; break
	state.room.recovery_attempts += attempts
	state.room.recovery_count += 1
	var after: Array = []
	for pos in cells: after.append({"cell":pos,"instance_id":state.board.get_tile(pos).instance_id})
	context.step += 1
	var eligible := context.reward_eligible
	context.reward_eligible = false
	context.emit("board_rearranged",{"attempts":attempts,"recovered":recovered,"before":before,"after":after})
	context.reward_eligible = eligible
	return {"ok":true,"recovered":recovered}
