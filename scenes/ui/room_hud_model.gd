class_name RoomHudModel
extends RefCounted
## Detached UI values; constructed at committed boundaries, never per-frame.
static func build(state: RunState, selected: Vector2i = Vector2i(-1,-1)) -> Dictionary:
	var data := {"phase":state.phase,"work":state.moves_remaining,"craft":state.room.craft,
		"capacity":state.rules.value("craft_capacity"),"remaining":state.room.remaining(state.board),
		"total":state.room.definition.data.marked_ids.size(),"allowance":state.room.tool_available,
		"reason":state.room.failure_reason,"tools":[],"inspection":"Select a gem to inspect its tier and next upgrade.","collection":[]}
	var legal := RoomActionLegality.tools(state)
	for kind in ["action.exchange","action.clear_target","action.promote_target"]:
		var cost := RoomActionLegality.effective_cost(kind,state)
		var reason := ""
		if state.phase != "ready": reason = "Begin the room" if state.phase == "briefing" else "Room finished"
		elif not state.room.tool_available: reason = "Make a matching swap to use another tool"
		elif state.room.craft < cost: reason = "Need %d Craft" % cost
		elif not legal.any(func(c: RoomCommand) -> bool: return c.data.kind == kind): reason = "No legal targets"
		data.tools.append({"kind":kind,"cost":cost,"reason":reason})
	var roster := state.catalog.roster()
	for i in roster.size(): data.collection.append("%d %s" % [i+1,str(roster[i]).capitalize()])
	var obstacle := state.board.obstacle_at(selected)
	var tile := state.board.get_tile(selected)
	if not obstacle.is_empty():
		data.inspection = "Rubble · %d hits left\nMatch beside it or use Chisel." % obstacle.durability
	elif tile != null:
		data.inspection = "%s · Tier %d\n%s" % [str(tile.tile_id).capitalize(),tile.tier,
			"Next: "+str(roster[tile.tier]).capitalize() if tile.tier < 8 else "A match recovers these gems."]
	return GameValue.freeze(data)
