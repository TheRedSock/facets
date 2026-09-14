class_name GameTopologyCases
extends RefCounted

static func run(test: SceneTree) -> void:
	var catalog := GameTestCatalog.create()
	for c in GameFixtureAdapter.read_cases():
		var board := GameFixtureAdapter.board(c)
		if c.phase == "spawn_query": test.check(BoardPhysics.new().find_spawn_eligible_cells(board).is_empty(), c.id)
		if c.phase == "gravity_query": test.check(board.get_effective_gravity(Vector2i.ZERO) == GameFixtureAdapter.cell(c.expected.direction), c.id)
		if c.phase == "settle_refill":
			var rng := SeededRng.new(); rng.reseed(int(c.seed))
			var result := BoardSettler.resolve(board,rng,catalog.supply(),SpawnResolver.new(catalog))
			test.check(result.ok and board.all_cells().all(func(p: Vector2i) -> bool: return board.get_tile(p) != null), c.id + " fills lane without matches")
			var origins: Array = []
			for step in result.steps:
				for event in step.gravity_events + step.spawn_events:
					test.check(event.cause == c.expected.all_events_root_cause and not event.reward_eligible,c.id + " setup cause cannot earn rewards")
				for event in step.spawn_events:
					origins.append(event.cell)
			test.check(origins.size() == 3 and origins.all(func(p: Vector2i) -> bool: return p == Vector2i.ZERO), c.id + " entry origins")
	# Irregular mask has two independent supported pockets.
	var layout := BoardLayoutResource.new(); layout.board_size = Vector2i(3,3)
	for y in 3: layout.add_blocked(Vector2i(1,y))
	var board := BoardState.new(); test.check(board.apply_layout(layout), "irregular pockets admitted")
	board.set_tile(Vector2i(0,0),catalog.create_tile(1)); board.set_tile(Vector2i(2,0),catalog.create_tile(2))
	var physics := BoardPhysics.new(); physics.resolve_gravity(board)
	test.check(board.get_tile(Vector2i(0,2)).tier == 1 and board.get_tile(Vector2i(2,2)).tier == 2, "separate supported pockets")
	# Sideways then down: each visited cell reevaluates gravity.
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(3,3)
	layout.set_gravity(Vector2i.ZERO,Vector2i.RIGHT)
	board = BoardState.new(); test.check(board.apply_layout(layout), "turn admitted")
	board.set_tile(Vector2i.ZERO,catalog.create_tile(1)); physics.resolve_gravity(board)
	test.check(board.get_tile(Vector2i(1,2)) != null and physics.last_move_events.map(func(e: Dictionary) -> Vector2i: return e.to) == [Vector2i(1,0),Vector2i(1,1),Vector2i(1,2)], "sideways to down exact path")
	# Upward scan deliberately visits the same moving instance again in round 0.
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(1,4)
	for y in 4: layout.set_gravity(Vector2i(0,y),Vector2i.UP)
	board = BoardState.new(); test.check(board.apply_layout(layout), "upward zone admitted")
	board.set_tile(Vector2i(0,3),catalog.create_tile(1)); physics.resolve_gravity(board)
	test.check(board.get_tile(Vector2i.ZERO) != null and physics.last_move_events.size() == 3 and physics.last_move_events.all(func(e: Dictionary) -> bool: return e.round == 0), "legacy upward scan frozen")
	# Directed portal landing and a local fill offset next to a different portal.
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(3,3)
	layout.add_portal(Vector2i(0,1),Vector2i.DOWN,Vector2i(2,2))
	board = BoardState.new(); test.check(board.apply_layout(layout), "portal landing admitted")
	board.set_tile(Vector2i.ZERO,catalog.create_tile(1)); physics.resolve_gravity(board)
	test.check(board.get_tile(Vector2i(2,2)) != null and physics.last_move_events[-1].kind == "portal" and physics.last_move_events[-1].from == Vector2i(0,1), "portal segment retained")
	board = BoardState.new(Vector2i(3,2))
	board.get_cell(Vector2i(1,1)).fill_sources = [Vector2i(-1,-1)]
	board.add_portal(Vector2i(1,1),Vector2i(-1,-1),Vector2i(2,0)) # raw query only; diagonal portals do not admit
	board.set_tile(Vector2i.ZERO,catalog.create_tile(1)); board.set_tile(Vector2i(2,0),catalog.create_tile(2))
	test.check(physics._fill_source(board,Vector2i(1,1)) == Vector2i.ZERO, "local diagonal fill ignores portal override")
	# Two gravity sources compete for bottom-middle; right-to-left wins.
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(3,2)
	layout.set_fill_sources(Vector2i(1,1),[Vector2i(-1,-1)])
	layout.add_portal(Vector2i(2,0),Vector2i.DOWN,Vector2i(2,1))
	board = BoardState.new(); test.check(board.apply_layout(layout), "local fill beside admitted cardinal portal")
	board.set_tile(Vector2i.ZERO,catalog.create_tile(1))
	test.check(physics._fill_source(board,Vector2i(1,1)) == Vector2i.ZERO,"admitted fill remains local")
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(3,1)
	layout.set_gravity(Vector2i.ZERO,Vector2i.RIGHT); layout.set_gravity(Vector2i(2,0),Vector2i.LEFT)
	board = BoardState.new(); var admitted := LayoutAdmission.admit(layout)
	test.check(admitted.ok and admitted.issues.any(func(i: Dictionary) -> bool: return i.code == "contention"), "contention diagnostic")
	board.apply_layout(layout); board.set_tile(Vector2i.ZERO,catalog.create_tile(1)); board.set_tile(Vector2i(2,0),catalog.create_tile(2)); physics.resolve_gravity(board)
	test.check(board.get_tile(Vector2i(1,0)).tier == 2 and board.get_tile(Vector2i.ZERO).tier == 1, "right source wins contention")
	# Immovable occupant above an entry cannot move; occupied entry never falls back.
	board = BoardState.new(Vector2i(1,3)); board.spawn_policy = "entry_only"
	board.get_cell(Vector2i(0,1)).is_spawn_entry = true
	var immovable := catalog.create_tile(1); immovable.immovable = true
	board.set_tile(Vector2i.ZERO,immovable)
	var rng := SeededRng.new(); rng.reseed(44)
	var filled := BoardSettler.resolve(board,rng,catalog.supply(),SpawnResolver.new(catalog))
	test.check(filled.ok and board.get_tile(Vector2i.ZERO) == immovable and board.get_tile(Vector2i(0,2)) != null, "immovable above entry preserved")
	# Mixed fill/gravity cycle, malformed entries and bounds are raw admission errors.
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(1,2); layout.set_fill_sources(Vector2i.ZERO,[Vector2i.DOWN])
	test.check(not LayoutAdmission.admit(layout).ok, "mixed-edge cycle rejected")
	layout = BoardLayoutResource.new(); layout.add_spawn_entry(Vector2i(99,0))
	test.check(not LayoutAdmission.admit(layout).ok, "out-of-bounds raw entry rejects")
	layout.spawn_entries = [Vector2i.ZERO]; layout.add_blocked(Vector2i.ZERO)
	test.check(not LayoutAdmission.admit(layout).ok, "blocked raw entry rejects")
	layout = BoardLayoutResource.new(); layout.board_size = Vector2i(17,16)
	test.check(not LayoutAdmission.admit(layout).ok, "oversize rejects before allocation")
	layout.board_size = Vector2i(16,16)
	board = BoardState.new(); test.check(board.apply_layout(layout), "16x16 admitted")
	for x in 16: board.set_tile(Vector2i(x,0),catalog.create_tile(1 + x % 4))
	var started := Time.get_ticks_usec()
	physics.resolve_gravity(board)
	var elapsed := Time.get_ticks_usec() - started
	test.check(physics.last_result.ok and physics.last_move_events.size() == 240 and board.get_tile(Vector2i(15,15)) != null, "16x16 converges with exact segment count")
	var stress := FileAccess.open("res://artifacts/game/p1-implementation/stress.json",FileAccess.WRITE)
	stress.store_string(JSON.stringify({"size":[16,16],"segments":physics.last_move_events.size(),"rounds":physics.last_result.get("rounds"),"elapsed_ms":elapsed/1000.0,"ok":physics.last_result.ok},"\t")); stress.close()
	var limits := RuleSet.DEFAULTS.duplicate(); limits.max_settle = 0
	board = BoardState.new(Vector2i(1,2)); board.set_tile(Vector2i.ZERO,catalog.create_tile(1))
	test.check(not physics.settle(board,ResolutionBudget.new(RuleSet.new(limits))).ok, "settle cap is failure with work remaining")
	board.move_tile(Vector2i.ZERO,Vector2i.DOWN)
	test.check(physics.settle(board,ResolutionBudget.new(RuleSet.new(limits))).ok, "stable exactly at cap succeeds")
