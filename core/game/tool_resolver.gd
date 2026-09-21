class_name ToolResolver
extends RefCounted

static func apply(context: ActionContext, command: RoomCommand, reset_step: bool = true) -> bool:
	var state := context.state
	var board := state.board
	var data := command.data
	context.step = 0 if reset_step else context.step+1
	if data.kind in ["swap","action.exchange"]:
		var first := board.get_tile(data.origin).to_dict()
		var second := board.get_tile(data.destination).to_dict()
		if not board.swap_cells(data.origin,data.destination): return false
		for pair in [[first,data.origin,data.destination],[second,data.destination,data.origin]]:
			context.emit("tile_moved",{"instance_id":pair[0].instance_id,"tile_id":pair[0].tile_id,"tier":pair[0].tier,
				"from":pair[1],"to":pair[2],"movement":"swap","path":[{"from":pair[1],"to":pair[2],"kind":"swap","sequence":context.segment}]})
			context.segment += 1
		var matched := {}
		for component in MatchClassifier.new().classify(MatchDetector.new().find_matches(board)):
			for pos in component.cells: matched[board.get_tile(pos).instance_id] = true
		if matched.has(first.instance_id) != matched.has(second.instance_id):
			var helper: Dictionary = second if matched.has(first.instance_id) else first
			context.emit("swap_assisted",{"instance_id":helper.instance_id,"source":helper})
		return true
	if data.layer == "obstacle":
		ObstacleResolver.damage(context,data.target_id,1,context.root)
		return true
	var cell := board.get_cell(data.cell)
	var tile := board.get_tile(data.cell)
	if data.layer == "lock":
		var old := cell.lock.duplicate(true)
		cell.lock.durability -= 1
		if cell.lock.durability == 0: cell.lock = {}
		context.emit("lock_damaged",{"cell":data.cell,"instance_id":tile.instance_id,"old":old,"new":cell.lock.duplicate(true)})
	elif data.kind == "action.clear_target":
		var source := tile.to_dict()
		board.remove_tile(data.cell)
		context.removed(source,data.cell,"effect_clearance")
	else:
		var old := tile.to_dict()
		if not state.catalog.promote(tile): return false
		context.emit("tile_promoted",{"instance_id":tile.instance_id,"cell":data.cell,"old":old,"new":tile.to_dict()})
	return true
