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

static func valid_settings(value: Variant) -> bool:
	if not value is Array or value.size() > 3: return false
	var seen := {}
	for id in value:
		if id not in ["aquamarine","steady_hand","beryl_bridge"] or seen.has(id): return false
		seen[id] = true
	return true

static func catalog(settings: Array = []) -> Dictionary:
	if not valid_settings(settings): return StateAdmission.fail("p3_settings")
	var base := GameBootstrap.catalog()
	if not base.ok: return base
	var data: Dictionary = base.catalog.to_dict()
	if "aquamarine" in settings:
		data.roster[4] = "aquamarine"; data.definitions.erase("sapphire")
		data.definitions.aquamarine = {"id":"aquamarine","tier":5,"match_group":"tier_5","family_tags":[]}
	for id in data.roster:
		data.definitions[id].family_tags = [FAMILIES[id]] if FAMILIES.has(id) else []
	return GameCatalog.admit(data)

static func carry_tile(source: Dictionary, target_catalog: GameCatalog) -> TileState:
	var tile := target_catalog.create_tile(source.tier)
	tile.instance_id = source.instance_id
	return tile

static func preview(reward: String, settings: Array, carry: Array = []) -> Dictionary:
	var next := settings.duplicate()
	if reward != "next_room_craft" and reward not in next: next.append(reward)
	var before := catalog(settings); var after := catalog(next)
	if not before.ok or not after.ok: return StateAdmission.fail("preview_settings")
	var ladder: Array = []
	for tier in range(1,9): ladder.append({"tier":tier,"before":before.catalog.definition(tier),"after":after.catalog.definition(tier)})
	var converted: Array = []
	for source in carry: converted.append({"before":source,"after":carry_tile(source,after.catalog).to_dict()})
	return {"ok":true,"reward":reward,"ladder":ladder,"carry":converted,
		"supply":{"targets":[1,2,3,4],"weights":[4,3,2,1]},
		"description":{
			"aquamarine":"Replace T5 Sapphire (Corundum) with Aquamarine (Beryl). T7 Ruby keeps Corundum. Carried T5 gems keep their IDs and tier. Refill stays T1–4.",
			"steady_hand":"The first accepted Chisel in each room costs 1 Craft instead of 2. Invalid or cancelled targets do not spend the discount.",
			"beryl_bridge":"Beryl may promote an adjacent T1–4 instead of T1–3. The same once-per-paid-move use applies. Emerald already provides Beryl.",
			"next_room_craft":"Add 1 Craft on next room entry, after carry Craft is clamped to 1–3. Consumed only when entry commits."
		}.get(reward,"")}

static func room(seed_value: int, settings: Array = []) -> Dictionary:
	var admitted := catalog(settings)
	if not admitted.ok: return admitted
	var definition := RoomDefinition.compile(load("res://data/game/rooms/open_seam.tres"),admitted.catalog)
	if not definition.ok: return definition
	var rules := RuleSet.for_p3()
	var opening := OpeningGenerator.generate(definition.board.layout_resource(),admitted.catalog,RngStreamBank.new(seed_value),rules,definition.board)
	if not opening.ok: return opening
	var state := RunState.new()
	state.catalog = admitted.catalog; state.rules = rules; state.board = opening.board
	state.settings = settings.duplicate()
	state.streams = opening.streams; state.opening_attempts = opening.attempts
	state.room = RoomState.new(); state.room.definition = definition.definition
	state.moves_remaining = definition.definition.data.work
	state.revision = 1; state.next_action = 2; state.next_event = 3
	state.sync_adapters()
	return RunState.restored(state.to_dict())
