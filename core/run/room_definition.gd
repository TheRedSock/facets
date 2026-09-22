class_name RoomDefinition
extends RefCounted
## Immutable authoring definition; empty initial board preserves admitted topology.
var data: Dictionary

func _init(value: Dictionary) -> void:
	data = GameValue.freeze(value)

static func compile(resource: RoomDefinitionResource, catalog: GameCatalog) -> Dictionary:
	if resource == null: return StateAdmission.fail("missing_room")
	var topology := LayoutAdmission.admit(resource.layout)
	if not topology.ok: return {"ok":false,"code":"room_layout","issues":topology.issues}
	var board := BoardState.new()
	board.apply_topology(topology.topology)
	board.room_board = true
	for obstacle in resource.obstacles:
		if not obstacle.has("id") or not GameValue.valid_id(obstacle.id) or board.obstacles.has(obstacle.id): return StateAdmission.fail("duplicate_obstacle_id")
		board.obstacles[obstacle.id] = obstacle.duplicate(true)
	return admit({"schema":1,"id":resource.room_id,"initial_board":board.to_dict(),"work":resource.work,
		"craft":resource.craft,"objective":"clear_marked_rubble","marked_ids":Array(resource.marked_ids)},catalog)

static func admit(value: Variant, catalog: GameCatalog) -> Dictionary:
	var keys := ["schema","id","initial_board","work","craft","objective","marked_ids"]
	var typed: bool = value is Dictionary and value.get("schema") == 2
	if typed: keys.append_array(["outlets","minimum_tier","demand","outlet_requires_clear","outlet_requires_unlocked"])
	if not StateAdmission.exact(value,keys): return StateAdmission.fail("room_definition_schema")
	if not value.schema is int or value.schema not in [1,2] or not GameValue.valid_id(value.id) or value.objective not in (["clear_marked_rubble","extract"] if typed else ["clear_marked_rubble"]): return StateAdmission.fail("room_definition_version")
	if not value.work is int or value.work < 1 or value.work > 1000 or not value.craft is int or value.craft < 0 or value.craft > 6: return StateAdmission.fail("room_economy")
	if not value.marked_ids is Array or (value.marked_ids.is_empty() and value.objective == "clear_marked_rubble") or value.marked_ids.size() > 256: return StateAdmission.fail("room_objective")
	var admitted := StateAdmission.board(value.initial_board,catalog)
	if not admitted.ok: return admitted
	var board: BoardState = admitted.board
	if not board.room_board or board.next_instance != 1: return StateAdmission.fail("room_initial_board")
	for pos in board.all_cells():
		if board.get_tile(pos) != null: return StateAdmission.fail("room_initial_occupant")
	if typed:
		if not value.outlets is Array or value.outlets.size() > 256 or not value.minimum_tier is int or not value.demand is int or value.outlet_requires_clear != true or not value.outlet_requires_clear is bool or value.outlet_requires_unlocked != true or not value.outlet_requires_unlocked is bool: return StateAdmission.fail("outlet_schema")
		if value.objective == "extract":
			if value.outlets.is_empty() or value.minimum_tier < 1 or value.minimum_tier > 8 or value.demand < 1 or value.demand > 256 or not value.marked_ids.is_empty(): return StateAdmission.fail("outlet_objective")
		elif not value.outlets.is_empty() or value.minimum_tier != 0 or value.demand != 0: return StateAdmission.fail("outlet_objective")
		var outlets := {}
		for cell in value.outlets:
			if not cell is Vector2i or board.is_blocked(cell) or outlets.has(cell): return StateAdmission.fail("outlet_cell")
			outlets[cell] = true
	var seen := {}
	for id in value.marked_ids:
		if not GameValue.valid_id(id) or seen.has(id) or not board.obstacles.has(id): return StateAdmission.fail("room_marked_reference")
		seen[id] = true
	var normalized: Dictionary = value.duplicate(true)
	normalized.marked_ids.sort()
	return {"ok":true,"definition":RoomDefinition.new(normalized),"board":board}
