extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var base: GameCatalog = P3Content.catalog().catalog
	var replaced: GameCatalog = P3Content.catalog(["aquamarine"]).catalog
	check(base.roster()[4] == "sapphire" and replaced.roster()[4] == "aquamarine","replacement has separate immutable ladder")
	var tile := replaced.create_tile(1)
	for tier in range(1,9):
		check(tile.tier == tier and tile.tile_id == replaced.roster()[tier-1],"full replacement ladder T%d" % tier)
		check(CanonicalCodec.encode(Array(tile.family_tags)) == CanonicalCodec.encode(replaced.definition(tier).family_tags),"replacement metadata matches ladder")
		if tier < 8: check(replaced.promote(tile),"next ladder promotion")
	var carried := base.create_tile(5); carried.instance_id = "expedition/91"; carried.immovable = true
	var converted := P3Content.carry_tile(carried.to_dict(),replaced)
	check(converted.instance_id == carried.instance_id and converted.tier == 5 and converted.tile_id == &"aquamarine" and not converted.immovable,"carry conversion preserves ID/tier and clears temporary state")
	var preview := P3Content.preview("aquamarine",[],[carried.to_dict()])
	check(preview.ladder.size() == 8 and preview.ladder[4].before.id == "sapphire" and preview.ladder[4].after.id == "aquamarine","preview shows complete before/after ladder")
	check(preview.carry[0].after == converted.to_dict() and preview.supply.targets == [1,2,3,4],"preview exactly predicts carry and unchanged supply")
	var state: RunState = P3Content.room(7,["steady_hand"]).state
	var session := MergeSession.new(); check(session.start(state.to_dict()),"Steady Hand room starts")
	var command := RoomCommand.target(session.state,"action.clear_target",Vector2i(2,2),"obstacle")
	var before := CanonicalCodec.encode(session.snapshot())
	check(session.quote(command).ok and session.quote(command).cost == 1,"first Chisel affordable with one Craft")
	check(CanonicalCodec.encode(session.snapshot()) == before,"preview does not consume use or resources")
	var invalid := command.to_dict(); invalid.target_id = "rubble/stale"
	check(not session.apply(RoomCommand.parse(invalid)).ok and CanonicalCodec.encode(session.snapshot()) == before,"invalid Chisel pure rejection")
	check(not session.prepare(command,"after_cost").ok and CanonicalCodec.encode(session.snapshot()) == before,"failed batch preserves discount")
	check(session.apply(command).ok and session.state.room_uses.get("steady_hand",false) and session.state.room.craft == 0,"accepted Chisel consumes exactly one room use and Craft")
	check(RoomActionLegality.effective_cost("action.clear_target",session.state) == 2,"later Chisel has base price")
	check(MergeReplay.restored(session.snapshot(),false).ok,"setting/room use included in replay restore")
	var context := MergeMoveContext.new(state,RoomCommand.begin(state.revision),1,"equilibrium")
	context.reward_eligible = true
	var cell := Vector2i(0,0); state.board.set_tile(cell,state.catalog.create_tile(4))
	var intent := {"reaction_id":"beryl","source_event_id":context.root,"scope":"move","target":{"cell":cell,"target_id":state.board.get_tile(cell).instance_id,"tier":4}}
	FamilyDispatcher.apply(context,intent)
	check(state.board.get_tile(cell).tier == 4 and not context.uses.has("beryl"),"base Beryl rejects T4")
	state.settings.append("beryl_bridge"); FamilyDispatcher.apply(context,intent)
	check(state.board.get_tile(cell).tier == 5 and context.uses.beryl,"Bridge extends Beryl through T4")
	context.uses.erase("beryl"); intent.target.tier = 5; FamilyDispatcher.apply(context,intent)
	check(state.board.get_tile(cell).tier == 5 and not context.uses.has("beryl"),"Bridge never includes T5")
	check(base.to_dict().targets == replaced.to_dict().targets and base.to_dict().weights == replaced.to_dict().weights,"replacement introduces no hidden supply changes")
	finish("test_p3_settings")
