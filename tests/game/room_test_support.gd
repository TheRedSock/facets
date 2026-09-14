class_name RoomTestSupport
extends RefCounted

static func fixture(rows: Array, obstacles: Array, work: int = 16, craft: int = 1) -> RunState:
	var catalog: GameCatalog = GameBootstrap.catalog().catalog
	var resource := RoomDefinitionResource.new()
	resource.room_id = "test_room"; resource.work = work; resource.craft = craft
	resource.layout = BoardLayoutResource.new(); resource.layout.board_size = Vector2i(rows[0].size(),rows.size())
	for i in obstacles.size():
		var source: Dictionary = obstacles[i]
		var id := str(source.get("id","rubble/%d" % i))
		var cell: Variant = source.cell
		if cell is Array: cell = GameFixtureAdapter.cell(cell)
		resource.obstacles.append({"id":id,"cell":cell,"kind":"rubble","durability":int(source.get("durability",2))})
		if source.get("marked",true): resource.marked_ids.append(id)
	var admitted := RoomDefinition.compile(resource,catalog)
	assert(admitted.ok,str(admitted))
	var state := RunState.new()
	state.board = admitted.board; state.catalog = catalog; state.rules = RuleSet.for_room()
	state.streams = RngStreamBank.new(1234)
	state.room = RoomState.new(); state.room.definition = admitted.definition; state.room.craft = craft
	state.moves_remaining = work; state.phase = "ready"
	state.revision = 1; state.next_action = 2; state.next_event = 3
	for y in rows.size():
		for x in rows[y].size():
			if int(rows[y][x]) > 0: state.board.set_tile(Vector2i(x,y),catalog.create_tile(int(rows[y][x])))
	state.sync_adapters()
	return state

static func controller(state: RunState) -> RunController:
	var result := RunController.new()
	assert(result.restore_snapshot(state.to_dict()),result.last_error)
	return result
