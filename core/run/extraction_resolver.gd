class_name ExtractionResolver
extends RefCounted
## Called only after matches and physical motion settle, never at a window.
static func collect(context: MergeMoveContext) -> Dictionary:
	var state := context.state; var room := state.room
	if room.definition.data.objective != "extract": return {"ok":true,"removed":false}
	var outlets: Array = room.definition.data.outlets.duplicate()
	outlets.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	var removed := false
	for cell in outlets:
		if room.remaining(state.board) == 0: break
		var tile := state.board.get_tile(cell)
		if tile == null or tile.tier < room.definition.data.minimum_tier or not state.board.obstacle_at(cell).is_empty() or not state.board.get_cell(cell).lock.is_empty(): continue
		if not context.budget.spend(1): return StateAdmission.fail(context.budget.error)
		if not removed: context.step += 1
		context.cause = "extraction"; context.reward_eligible = false
		var delivery := {"instance_id":tile.instance_id,"removal_id":state.next_removal,"tier":tile.tier,"cell":cell}
		var event := state.next_event
		state.board.remove_tile(cell); context.removed(tile.to_dict(),cell,"extraction")
		context.emit("tile_extracted",delivery,event)
		room.deliveries.append(delivery)
		context.emit("objective_progress",{"objective":"extract","remaining":room.remaining(state.board),"delivered":room.deliveries.size()},event)
		removed = true
	return {"ok":context.budget.error.is_empty(),"code":context.budget.error,"removed":removed}
