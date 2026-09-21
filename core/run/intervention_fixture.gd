class_name InterventionFixture
extends RefCounted
## Authored diagnostic board for the opt-in trial, never normal room generation.
static func create(work: int = 16, variant: String = "offered") -> RunState:
	var rows := [[3,4,2,3],[4,3,1,4],[3,4,1,3],[4,3,4,1],[3,2,3,4],[4,2,4,0]]
	if variant == "automatic_chain": rows[4][2] = 2; rows[5][2] = 2
	if variant == "no_opportunity": rows[4][1] = 4; rows[5][1] = 5
	var catalog: GameCatalog = GameBootstrap.catalog().catalog
	var resource := RoomDefinitionResource.new()
	resource.room_id = "intervention_fixture_v1"; resource.work = work; resource.craft = 1
	resource.layout = BoardLayoutResource.new(); resource.layout.board_size = Vector2i(4,6)
	resource.obstacles = [{"id":"rubble/trial","cell":Vector2i(3,5),"kind":"rubble","durability":2}]
	resource.marked_ids = ["rubble/trial"]
	var room := RoomDefinition.compile(resource,catalog)
	var state := RunState.new()
	state.board = room.board; state.catalog = catalog; state.rules = RuleSet.for_room()
	state.streams = RngStreamBank.new(1234)
	state.room = RoomState.new(); state.room.definition = room.definition; state.room.craft = 1
	state.moves_remaining = work; state.phase = "ready"; state.revision = 1; state.next_action = 2; state.next_event = 3
	for y in rows.size():
		for x in rows[y].size():
			if rows[y][x] > 0: state.board.set_tile(Vector2i(x,y),catalog.create_tile(rows[y][x]))
	state.sync_adapters()
	return state

static func command(state: RunState) -> RoomCommand:
	return RoomCommand.exchange(state,Vector2i(3,3),Vector2i(2,3))
