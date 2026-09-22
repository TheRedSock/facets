class_name P3Content
extends RefCounted
## Explicit prototype profile; legacy resource definitions remain untouched.
const PROFILE := "p3-merge"
const SIMULATION := "facets-sim-p3-merge-v1"
const CONTENT := "facets-p3-merge-content-v1"
const REPLAY := "facets-replay-p3-merge-v1"
const SAVE := "facets-save-p3-merge-v1"
const FAMILIES := {"quartz":"quartz","amethyst":"quartz","sapphire":"corundum",
	"ruby":"corundum","emerald":"beryl","aquamarine":"beryl"}

static func catalog() -> Dictionary:
	var base := GameBootstrap.catalog()
	if not base.ok: return base
	var data: Dictionary = base.catalog.to_dict()
	for id in data.roster:
		data.definitions[id].family_tags = [FAMILIES[id]] if FAMILIES.has(id) else []
	return GameCatalog.admit(data)

static func room(seed_value: int) -> Dictionary:
	var admitted := catalog()
	if not admitted.ok: return admitted
	var definition := RoomDefinition.compile(load("res://data/game/rooms/open_seam.tres"),admitted.catalog)
	if not definition.ok: return definition
	var rules := RuleSet.for_p3()
	var opening := OpeningGenerator.generate(definition.board.layout_resource(),admitted.catalog,RngStreamBank.new(seed_value),rules,definition.board)
	if not opening.ok: return opening
	var state := RunState.new()
	state.catalog = admitted.catalog; state.rules = rules; state.board = opening.board
	state.streams = opening.streams; state.opening_attempts = opening.attempts
	state.room = RoomState.new(); state.room.definition = definition.definition
	state.moves_remaining = definition.definition.data.work
	state.revision = 1; state.next_action = 2; state.next_event = 3
	state.sync_adapters()
	return RunState.restored(state.to_dict())
