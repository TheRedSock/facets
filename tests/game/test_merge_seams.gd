extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for scope in ["move","room","run"]:
		var game := RunController.new(); game.start_room(null,1); game.apply_action(RoomCommand.begin(0))
		var session := MergeSession.new(); check(session.start(game.run_state.to_dict()),"scope fixture")
		var modifiers := MergeModifiers.DEFAULTS.merged({"reward_bonus":1,"reward_trigger":"any","reward_context":"any","reward_scope":scope},true)
		check(session.configure_modifiers(modifiers),"typed scope "+scope)
		for index in 3:
			if session.phase == "merge_window": session.presented()
			var moves := ActionLegality.enumerate_legal_swaps(session.state.board)
			check(not moves.is_empty(),"scope witness has legal move")
			if moves.is_empty(): break
			check(session.apply(RoomCommand.exchange(session.state,moves[0].origin,moves[0].destination)).ok,"scope move commits")
			check(session.context.raw_bonus == (1 if index == 0 or scope == "move" else 0),"MW26 once-per-"+scope+" across fresh paid scopes")
		check(MergeReplay.restored(session.snapshot(),false).ok,"scope counters included in exact replay")
	_source_family()
	_live_target()
	finish("test_merge_seams")

func _source_family() -> void:
	var state := InterventionFixture.create()
	var catalog := state.catalog.to_dict()
	catalog.definitions[catalog.roster[0]].family_tags = ["source_family"]
	catalog.definitions[catalog.roster[1]].family_tags = ["destination_family"]
	state.catalog = GameCatalog.admit(catalog).catalog
	for pos in state.board.all_cells():
		var tile := state.board.get_tile(pos)
		if tile != null: tile.family_tags.assign(state.catalog.definition(tile.tier).family_tags)
	state.sync_adapters()
	var session := MergeSession.new(); check(session.start(state.to_dict()),"source-family fixture admits")
	check(session.configure_modifiers(MergeModifiers.DEFAULTS.merged({"reward_bonus":1,"reward_context":"any","reward_family":"source_family"},true)),"family-filtered diagnostic reaction admits")
	check(session.apply(InterventionFixture.command(session.state)).ok,"source-family match executes")
	check(session.context.raw_bonus == 1 and "destination_family" in session.state.board.get_tile(Vector2i(2,3)).family_tags,"MW26 reward reads frozen source rather than promoted destination family")
	var source: Dictionary = session.last_batch.facts.filter(func(f: Dictionary) -> bool: return f.type == "match_committed")[0]
	var reaction: Dictionary = session.last_batch.facts.filter(func(f: Dictionary) -> bool: return f.type == "reaction_applied")[0]
	check(reaction.parent_event_id == source.event_id,"reaction ancestry is its source event")

func _live_target() -> void:
	var state := InterventionFixture.create()
	var context := MergeMoveContext.new(state,InterventionFixture.command(state),1,"intervention")
	var cell := Vector2i(2,1); var id := state.board.get_tile(cell).instance_id
	check(not MergeReactionScope.promote_live(context,cell,"piece/stale","move","diagnostic_promote").applied and context.uses.is_empty(),"MW26 stale live target spends no use")
	check(MergeReactionScope.promote_live(context,cell,id,"move","diagnostic_promote").applied,"live promotion spends one scope use")
	check(state.board.get_tile(cell).tier == 2 and not MergeReactionScope.promote_live(context,cell,id,"move","diagnostic_promote").applied,"scope cap prevents duplicate promotion")
	context.reward_eligible = false
	check(not MergeReactionScope.promote_live(context,Vector2i(2,2),state.board.get_tile(Vector2i(2,2)).instance_id,"room","diagnostic_room").applied and context.room_uses.is_empty(),"tool/extraction suppression precedes use consumption")
