class_name MergeReactionScope
extends RefCounted
## Concrete diagnostic dispatcher for P3 seams. No authored family is activated.
static func ledger(context: MergeMoveContext, scope: String) -> Dictionary:
	match scope:
		"move": return context.uses
		"room": return context.room_uses
		"run": return context.run_uses
	return {}

static func reward(context: MergeMoveContext, source: Dictionary) -> void:
	if not context.reward_eligible or context.modifier_bonus == 0: return
	var origin := context.classification if context.modifier_context == "intervention" else "intervention"
	if not MergeModifiers.matches(origin,context.direct_batch,context.modifier_trigger): return
	if not context.modifier_family.is_empty():
		var eligible := false
		for item in source.sources:
			if context.modifier_family in item.tile.family_tags: eligible = true
		if not eligible: return
	var uses := ledger(context,context.modifier_scope)
	if uses.has("diagnostic_reward"): return
	uses.diagnostic_reward = true
	context.raw_bonus += context.modifier_bonus
	context.emit("reaction_applied",{"reaction_id":"diagnostic_reward","scope":context.modifier_scope,
		"source_event_id":source.event_id,"raw_bonus":context.modifier_bonus},source.event_id)

static func promote_live(context: MergeMoveContext, cell: Vector2i, expected_id: String, scope: String, reaction_id: String) -> Dictionary:
	if scope not in ["move","room","run"] or not GameValue.valid_id(reaction_id): return StateAdmission.fail("reaction_schema")
	if not context.reward_eligible: return {"ok":true,"applied":false,"reason":"suppressed"}
	var uses := ledger(context,scope)
	if uses.has(reaction_id): return {"ok":true,"applied":false,"reason":"scope_used"}
	var tile := context.state.board.get_tile(cell)
	if tile == null or tile.instance_id != expected_id or tile.tier not in range(1,4) or not context.state.board.can_move_occupant(cell):
		return {"ok":true,"applied":false,"reason":"stale_or_ineligible"}
	if not context.budget.spend(1,2): return StateAdmission.fail(context.budget.error)
	var old := tile.to_dict()
	if not context.state.catalog.promote(tile): return StateAdmission.fail("reaction_promotion")
	uses[reaction_id] = true
	context.emit("tile_promoted",{"instance_id":tile.instance_id,"cell":cell,"old":old,"new":tile.to_dict()})
	context.emit("reaction_applied",{"reaction_id":reaction_id,"scope":scope,"target_id":tile.instance_id})
	if not context.budget.error.is_empty(): return StateAdmission.fail(context.budget.error)
	return {"ok":true,"applied":true,"reason":""}
