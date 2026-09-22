class_name P3Workload
extends RefCounted
## Declared content-load fixtures, not generated expedition success claims.
## Covers four authored rooms, all settings combinations and 0/1/2 incoming gems.
static func create(seed_value: int) -> Dictionary:
	var settings: Array = []
	for index in 3:
		if (seed_value/4) & (1 << index): settings.append(["aquamarine","steady_hand","beryl_bridge"][index])
	var catalog := P3Content.catalog(settings)
	if not catalog.ok: return catalog
	var room := P3Rooms.definition(["open_seam","deep_seam","commission","vault"][posmod(seed_value,4)],catalog.catalog)
	if not room.ok: return room
	var board: BoardState = room.board
	board.id_namespace = "expedition"
	for index in posmod(seed_value,3): board.set_tile(ExpeditionState.STAGING[index],catalog.catalog.create_tile(4+index))
	var opening := OpeningGenerator.generate(board.layout_resource(),catalog.catalog,RngStreamBank.new(seed_value),RuleSet.for_p3(),board)
	if not opening.ok: return opening
	var state := RunState.new(); state.catalog = catalog.catalog; state.rules = RuleSet.for_p3(); state.settings = settings
	state.board = opening.board; state.streams = opening.streams; state.opening_attempts = opening.attempts
	state.room = RoomState.new(); state.room.definition = room.definition; state.room.craft = 3
	state.moves_remaining = room.definition.data.work; state.revision = 1; state.next_action = 2; state.next_event = 3
	state.sync_adapters()
	return RunState.restored(state.to_dict())
