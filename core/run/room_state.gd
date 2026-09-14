class_name RoomState
extends RefCounted

var definition: RoomDefinition
var craft := 1
var tool_available := true
var normal_turns := 0
var recovery_attempts := 0
var recovery_count := 0
var failure_reason := ""

func to_dict() -> Dictionary:
	return {"definition":definition.data.duplicate(true),"resource.tactic_charge":craft,
		"tool_available":tool_available,"normal_turns":normal_turns,"recovery_attempts":recovery_attempts,
		"recovery_count":recovery_count,"failure_reason":failure_reason}

func remaining(board: BoardState) -> int:
	var count := 0
	for id in definition.data.marked_ids:
		if board.obstacles.has(id): count += 1
	return count

func duplicate_state() -> RoomState:
	var copy := RoomState.new()
	copy.definition = definition; copy.craft = craft; copy.tool_available = tool_available
	copy.normal_turns = normal_turns; copy.recovery_attempts = recovery_attempts
	copy.recovery_count = recovery_count; copy.failure_reason = failure_reason
	return copy

static func restored(value: Variant, catalog: GameCatalog, board: BoardState) -> Dictionary:
	if not StateAdmission.exact(value,["definition","resource.tactic_charge","tool_available","normal_turns","recovery_attempts","recovery_count","failure_reason"]): return StateAdmission.fail("room_state_schema")
	if not value["resource.tactic_charge"] is int or value["resource.tactic_charge"] < 0 or value["resource.tactic_charge"] > 6 or not value.tool_available is bool or value.failure_reason not in ["","work_exhausted","board_locked"]: return StateAdmission.fail("room_state_value")
	for key in ["normal_turns","recovery_attempts","recovery_count"]:
		if not value[key] is int or value[key] < 0 or value[key] > 1000000: return StateAdmission.fail("room_counter")
	var admitted := RoomDefinition.admit(value.definition,catalog)
	if not admitted.ok: return admitted
	if not board.room_board or board.layout_resource().board_size != admitted.board.size: return StateAdmission.fail("room_board_mismatch")
	var topology := board.duplicate_board()
	topology.clear(); topology.obstacles = admitted.board.obstacles.duplicate(true); topology.next_instance = 1
	topology.id_namespace = admitted.board.id_namespace
	for pos in topology.all_cells():
		topology.get_cell(pos).lock = {}; topology.get_cell(pos).tags = admitted.board.get_cell(pos).tags.duplicate(true)
	if topology.to_dict() != admitted.board.to_dict(): return StateAdmission.fail("room_topology_mismatch")
	for id in board.obstacles:
		if not admitted.board.obstacles.has(id): return StateAdmission.fail("room_obstacle_id")
		var original: Dictionary = admitted.board.obstacles[id]
		var obstacle: Dictionary = board.obstacles[id]
		if obstacle.cell != original.cell or obstacle.kind != original.kind or obstacle.durability > original.durability: return StateAdmission.fail("room_obstacle_state")
	var room := RoomState.new()
	room.definition = admitted.definition; room.craft = value["resource.tactic_charge"]
	room.tool_available = value.tool_available; room.normal_turns = value.normal_turns
	room.recovery_attempts = value.recovery_attempts; room.recovery_count = value.recovery_count
	room.failure_reason = value.failure_reason
	return {"ok":true,"room":room}
