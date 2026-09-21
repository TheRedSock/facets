extends "res://tests/game/game_test.gd"
## Checks specification consistency and existing delivery coverage, not P3 rules.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/p3-preparation.json"))
	check(spec.profile == "p3-merge" and spec.simulation not in [RuleSet.DEFAULTS.simulation,RuleSet.room_defaults().simulation,MergeSession.SIMULATION],"reserved expedition identity cannot silently reuse controls or standalone successor")
	check(spec.production_action_model == "incremental_merge_windows" and spec.state_schema == 4,"P3 explicitly incorporates new continuation state")
	check(spec.roster == GameBootstrap.catalog().catalog.roster(),"preparation starts with actual starter roster")
	var definition: TileDefinitionResource = load("res://data/tiles/aquamarine.tres")
	check(definition.tier == int(spec.replacement.tier),"replacement resource has intended tier")
	var catalog: GemDeliveryCatalog = load("res://data/presentation/default.tres")
	var needed: Array = spec.roster.duplicate(); needed.append(spec.replacement.after)
	for id in needed:
		var binding: GemTilePresentation
		for item in catalog.bindings:
			if str(item.tile_id) == id: binding = item
		check(binding != null,"existing delivered binding "+id)
		if binding != null: check(not str(binding.roles.get(&"rest","")).is_empty() and not str(binding.roles.get(&"upgrade","")).is_empty(),"existing required roles "+id)
	var rooms := {}
	for room in spec.rooms:
		check(not rooms.has(room.id),"unique room definition "+room.id); rooms[room.id] = room
		var occupied := {}
		for cell in room.rubble:
			var key := str(cell)
			check(not occupied.has(key),"no duplicate rubble "+room.id); occupied[key] = true
		for cell in spec.carry.staging:
			check(not occupied.has(str(cell)),"carry staging avoids rubble "+room.id)
		for cell in room.rubble+room.outlets+spec.carry.staging:
			check(cell[0] >= 0 and cell[0] < room.size[0] and cell[1] >= 0 and cell[1] < room.size[1],"planned cell in bounds "+room.id)
		if room.kind == "extract": check(room.outlets.size() == 2 and room.demand > 0 and room.minimum_tier >= 1,"extraction specification bounded "+room.id)
		else: check(not room.rubble.is_empty() and room.outlets.is_empty(),"seam specification concrete "+room.id)
	for route in spec.routes:
		check(route.size() == 3 and route[0] == "open_seam" and route[-1] == "vault","three-room route shape")
		for room in route: check(rooms.has(room),"route references authored definition")
	for first in spec.reward_pool:
		var second: Array = spec.reward_pool.duplicate()
		if first in spec.permanent_rewards: second.erase(first)
		check(second.size() >= int(spec.reward_screen_size),"every first reward leaves three distinct legal second offers: "+first)
		var unique := {}
		for reward in second: unique[reward] = true
		check(unique.size() == second.size(),"fallback never duplicated: "+first)
	check(spec.bridge_starter_access in spec.roster and spec.families[spec.bridge_starter_access] == "beryl","Beryl Bridge already has starter Emerald access")
	check(spec.save_phases.size() == 11 and "reward_selection" in spec.save_phases and "route_selection" in spec.save_phases,"stable and parked phases included in persistence")
	for phase in ["empty","ready","merge_window","gravity","reserved_command","complete","failed","diagnostic","publication"]:
		check(spec.phase_disposition.has(phase) and not spec.phase_disposition[phase].is_empty(),"MW27 explicit phase disposition "+phase)
	for field in ["resolution_session","move_id","batch_id","window_id","cursor","entitlement","move_uses","run_uses","reservation","window_clock","assistance","decision_chain"]:
		check(field in spec.save_fields,"MW27 pending identity inventory "+field)
	for field in ["rng","offers","entry_bonus","ordered_carry","instance_allocator","replay_cursor"]: check(field in spec.save_fields,"complete save inventory includes "+field)
	var ids := {}
	for fixture in spec.fixtures:
		check(not ids.has(fixture.id) and not fixture.expected.is_empty(),"named preparatory expectation "+fixture.id); ids[fixture.id] = true
	var inherited: Dictionary
	for fixture in GameFixtureAdapter.read_cases():
		if fixture.id == "outlet_delivery": inherited = fixture.expected
	for fixture in spec.fixtures:
		if fixture.id == "frozen_outlet_delivery": check(fixture.expected == inherited,"P0 outlet expectation preserved exactly")
	finish("test_p3_preparation")
