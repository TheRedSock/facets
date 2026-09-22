class_name FamilyDispatcher
extends RefCounted
## Three typed handlers only. Every input is a frozen pre-promotion source.
static func has_family(source: Dictionary, family: String) -> bool:
	for item in source.sources:
		if family in item.tile.family_tags: return true
	return false

static func spend(context: MergeMoveContext) -> bool:
	var count: int = context.uses.get("family_intents",0)
	if count >= int(context.state.rules.value("max_reactions")):
		context.budget.error = "reaction_cap"
		return false
	context.uses.family_intents = count+1
	return context.budget.spend(1)

static func record(context: MergeMoveContext, intent: Dictionary, reason: String = "") -> void:
	var payload := intent.duplicate(true)
	payload.reason = reason
	context.emit("reaction_applied" if reason.is_empty() else "reaction_skipped",payload,intent.source_event_id)

static func damage(context: MergeMoveContext, component: Dictionary, event_id: int) -> void:
	var corundum := has_family(component,"corundum")
	var amount := 1
	if corundum:
		if not spend(context): return
		var intent := {"reaction_id":"corundum","source_event_id":event_id,"scope":"component"}
		if context.reward_eligible:
			amount = 2; record(context,intent)
		else: record(context,intent,"suppressed")
	for target in component.obstacle_targets:
		ObstacleResolver.damage(context,target.id,amount,event_id)

static func target(context: MergeMoveContext, source: Dictionary, maximum: int = 3) -> Dictionary:
	var board := context.state.board
	if source.survivor == null: return {}
	var survivor := board.get_tile(source.survivor)
	if survivor == null or survivor.instance_id != source.survivor_id: return {}
	var options: Array = []
	for direction in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
		var cell: Vector2i = board.neighbor_for(source.survivor,direction,"match")
		var tile := board.get_tile(cell)
		if tile != null and tile.tier >= 1 and tile.tier <= maximum and board.can_move_occupant(cell):
			options.append({"cell":cell,"target_id":tile.instance_id,"tier":tile.tier})
	options.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.tier != b.tier: return a.tier < b.tier
		if a.cell.y != b.cell.y: return a.cell.y < b.cell.y
		return a.cell.x < b.cell.x)
	return options[0] if not options.is_empty() else {}

static func dispatch(context: MergeMoveContext, facts: Array) -> void:
	var intents: Array = []
	for fact in facts:
		if fact.type != "match_committed": continue
		for family in ["quartz","beryl"]:
			if not has_family(fact,family): continue
			var intent := {"reaction_id":family,"source_event_id":fact.event_id,"scope":"move"}
			if family == "beryl": intent.target = target(context,fact,4 if "beryl_bridge" in context.state.settings else 3)
			intents.append(intent)
	# Phase priority, then event, scope and reaction identity (fixed per handler).
	intents.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.reaction_id != b.reaction_id: return a.reaction_id == "quartz"
		return a.source_event_id < b.source_event_id)
	for intent in intents:
		if not spend(context): return
		apply(context,intent)

static func apply(context: MergeMoveContext, intent: Dictionary) -> void:
	if not context.reward_eligible: record(context,intent,"suppressed"); return
	if context.uses.has(intent.reaction_id): record(context,intent,"scope_used"); return
	if intent.reaction_id == "quartz":
		context.raw_bonus += 1; context.uses.quartz = true
		record(context,intent)
		return
	if intent.target.is_empty(): record(context,intent,"no_target"); return
	var chosen: Dictionary = intent.target
	var tile := context.state.board.get_tile(chosen.cell)
	var maximum := 4 if "beryl_bridge" in context.state.settings else 3
	if tile == null or tile.instance_id != chosen.target_id or tile.tier != chosen.tier or tile.tier < 1 or tile.tier > maximum or not context.state.board.can_move_occupant(chosen.cell):
		record(context,intent,"stale_or_ineligible"); return
	var old := tile.to_dict()
	if not context.state.catalog.promote(tile): context.budget.error = "family_promotion"; return
	context.uses.beryl = true
	context.emit("tile_promoted",{"instance_id":tile.instance_id,"cell":chosen.cell,"old":old,"new":tile.to_dict()},intent.source_event_id)
	record(context,intent)
