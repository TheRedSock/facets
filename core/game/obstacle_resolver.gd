class_name ObstacleResolver
extends RefCounted

static func damage(context: ActionContext, id: String, amount: int, parent: int) -> void:
	var board := context.state.board
	if not board.obstacles.has(id): return
	var obstacle: Dictionary = board.obstacles[id]
	var old := obstacle.duplicate(true)
	var actual := mini(amount,obstacle.durability)
	obstacle.durability -= actual
	var hit := context.emit("obstacle_damaged",{"obstacle_id":id,"cell":obstacle.cell,
		"damage":actual,"old":old,"new":obstacle.duplicate(true)},parent)
	if obstacle.durability == 0:
		board.obstacles.erase(id)
		var broken := context.emit("obstacle_broken",{"obstacle_id":id,"cell":old.cell,"source":old},hit)
		if id in context.state.room.definition.data.marked_ids:
			context.emit("objective_progress",{"objective":"clear_marked_rubble","obstacle_id":id,
				"remaining":context.state.room.remaining(board)},broken)
