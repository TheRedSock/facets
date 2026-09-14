extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func _projection(board: BoardState) -> Dictionary:
	var before := board.duplicate_board()
	var catalog := GameTestCatalog.create()
	var rng := SeededRng.new(); rng.reseed(77)
	var settled := BoardSettler.resolve(board,rng,catalog.supply(),SpawnResolver.new(catalog))
	check(settled.ok,"motion fixture settles")
	var timeline := EventTimeline.new()
	for step in settled.steps:
		step.match_events = []; step.remove_events = []; step.upgrade_events = []
		timeline.add_cascade_step(step)
	var plan := MotionPlan.build({"before":before,"timeline":timeline})
	var expected := 0; var actual := 0
	for step in settled.steps: expected += step.gravity_events.size()
	for phase in plan:
		for journey in phase.journeys: actual += journey.path.size()
	check(actual == expected,"projection retains every physical segment")
	return {"plan":plan,"before":before,"after":board}

func _run() -> void:
	var catalog := GameTestCatalog.create()
	# Authored L-shaped holes: one gap in column 1, three gaps in column 2.
	var board := BoardState.new(Vector2i(4,6))
	for pos in board.all_cells(): board.set_tile(pos,catalog.create_tile(1 + (pos.x + pos.y) % 4))
	for pos in [Vector2i(1,4),Vector2i(2,4),Vector2i(2,3),Vector2i(2,2)]: board.get_cell(pos).tile = null
	var result := _projection(board)
	var wave: Dictionary = result.plan[0]
	check(wave.concurrent,"ordinary L falls concurrently")
	check(wave.journeys.all(func(j: Dictionary) -> bool: return j.start == 0.0),"all newly unsupported stacks release together")
	var short_time := 0.0; var long_time := 0.0
	for journey in wave.journeys:
		if journey.spawn: check(journey.from.y < 0,"spawn begins in spaced incoming stack")
		elif journey.from.x == 1: short_time = maxf(short_time,journey.duration)
		elif journey.from.x == 2: long_time = maxf(long_time,journey.duration)
	check(short_time > 0 and short_time < long_time,"short falls land before long falls")
	check(wave.motion_seconds < wave.serial_seconds,"duration follows longest journey rather than sum of segments")
	# Sample all trajectories: shared cubic acceleration prevents lane overtaking.
	for tick in 101:
		var positions := {}
		var time: float = wave.motion_seconds * tick / 100.0
		for journey in wave.journeys:
			var y: float = lerpf(journey.from.y,journey.to.y,pow(minf(1.0,time / journey.duration),3))
			if not positions.has(journey.to.x): positions[journey.to.x] = []
			positions[journey.to.x].append(y)
		for values in positions.values():
			values.sort()
			for i in range(1,values.size()): check(values[i] - values[i-1] >= 0.999,"lane spacing throughout motion")
	# Entry-only refill keeps each spawned instance's complete subsequent journey.
	board = BoardState.new(Vector2i(1,8)); board.spawn_policy = "entry_only"; board.get_cell(Vector2i.ZERO).is_spawn_entry = true
	board.set_tile(Vector2i.ZERO,catalog.create_tile(1)); result = _projection(board)
	check(result.plan[0].concurrent and result.plan[0].journeys.size() == 8,"long entry-only column coalesces all refill rounds")
	check(result.plan[0].journeys.any(func(j: Dictionary) -> bool: return j.spawn and not j.path.is_empty()),"spawn travel retains later physical segments")
	# Two regions, separated by an intact column, remain a single concurrent wave.
	board = BoardState.new(Vector2i(3,4))
	for pos in board.all_cells():
		if pos.x == 1 or pos.y == 0: board.set_tile(pos,catalog.create_tile(1 + pos.y % 4))
	result = _projection(board); check(result.plan[0].concurrent,"disconnected moving columns overlap")
	for scenario in ["turn","up","portal","diagonal","pockets"]:
		var layout := BoardLayoutResource.new(); layout.board_size = Vector2i(3,4)
		if scenario == "turn": layout.set_gravity(Vector2i.ZERO,Vector2i.RIGHT)
		if scenario == "up":
			for pos in [Vector2i(0,0),Vector2i(0,1),Vector2i(0,2),Vector2i(0,3)]: layout.set_gravity(pos,Vector2i.UP)
		if scenario == "portal": layout.add_portal(Vector2i(0,1),Vector2i.DOWN,Vector2i(2,3))
		if scenario == "diagonal":
			layout.add_blocked(Vector2i(0,1)); layout.set_fill_sources(Vector2i(1,1),[Vector2i(-1,-1),Vector2i(1,-1)])
		if scenario == "pockets": layout.add_blocked(Vector2i(0,2))
		board = BoardState.new(); check(board.apply_layout(layout),scenario + " admitted")
		board.set_tile(Vector2i(0,3) if scenario == "up" else Vector2i.ZERO,catalog.create_tile(1))
		result = _projection(board)
		check(not result.plan[0].concurrent,scenario + " uses conservative exact-path fallback")
		if scenario == "portal": check(result.plan[0].journeys.any(func(j: Dictionary) -> bool: return j.path.any(func(p: Dictionary) -> bool: return p.kind == "portal")),"portal kind and landing preserved")
	var session := RunController.new(); session.start_new_run({"seed":3,"board_size":Vector2i(3,3)})
	board = BoardState.new(Vector2i(3,3))
	var tiers := [[3,1,4],[4,1,3],[1,2,2]]
	for pos in board.all_cells(): board.set_tile(pos,session.run_state.catalog.create_tile(tiers[pos.y][pos.x]))
	session.run_state.board = board
	var chained := session.apply_action(SwapCommand.new(Vector2i(0,2),Vector2i(1,2)))
	check(chained.ok,"promotion chain action commits")
	var chain_plan := MotionPlan.build(chained)
	check(chain_plan.size() >= 3 and chain_plan[0].kind == "match" and chain_plan[1].kind == "match", "automatic promotion chain precedes any falling in the visual plan")
	await _scene_cases()
	finish("test_game_motion")

func _scene_cases() -> void:
	var fixture := GemDeliveryFixture.create("res://artifacts/game/p1a/motion-assets",load("res://data/presentation/default.tres"))
	check(root.get_node("GemForge").open_library(fixture.library,fixture.catalog),"motion fixture opens")
	var scene: RunScene = load("res://scenes/run/run_scene.tscn").instantiate()
	root.add_child(scene)
	await _ready_board(scene)
	scene.run_controller.start_new_run({"seed":0}); await _ready_board(scene)
	var initial := scene.run_controller.run_state.to_dict()
	var command := scene.run_controller.enumerate_legal_swaps()[0]
	Engine.time_scale = 8.0
	await scene._on_swap_requested(command.origin,command.destination)
	Engine.time_scale = 1.0
	var player: ActionPlayer = scene.board_scene._action_player
	var digest := scene.run_controller.run_state.digest()
	var checkpoint: String = scene.run_controller.last_result.event_digest
	var starts: Array = player.observations.filter(func(o: Dictionary) -> bool: return o.kind == "start")
	check(starts.size() > 1,"normal scene observes actual travel")
	check(starts[0].frame == starts[1].frame,"independent real views start in the same frame")
	check(scene.board_scene._tile_views.size() == 64 and player._views_by_id.is_empty(),"natural completion has exact views and no in-flight references")
	scene.run_controller.restore_snapshot(initial); await _ready_board(scene)
	player.serial_reference = true; Engine.time_scale = 40.0
	await scene._on_swap_requested(command.origin,command.destination)
	Engine.time_scale = 1.0; player.serial_reference = false
	check(scene.run_controller.run_state.digest() == digest and scene.run_controller.last_result.event_digest == checkpoint,"serial and concurrent real playback match checkpoints")
	# Cancel at actual travel start, after detached spawn views were acquired.
	for operation in ["skip","landing_skip","restart","error","destroy"]:
		scene.run_controller.restore_snapshot(initial); await _ready_board(scene)
		scene._on_swap_requested(command.origin,command.destination)
		for frame in 400:
			await process_frame
			var desired := "land" if operation == "landing_skip" else "start"
			if player.observations.any(func(o: Dictionary) -> bool: return o.kind == desired): break
		check(not player._views_by_id.is_empty(),operation + " reaches live concurrent travel")
		if operation in ["skip","landing_skip"]: scene.skip_playback()
		elif operation == "restart": scene._on_restart_pressed()
		elif operation == "error": scene._show_delivery_error("controlled concurrent delivery failure"); scene.skip_playback()
		else: scene.queue_free()
		await process_frame; await process_frame
		check(player._tweens.is_empty() and player._views_by_id.is_empty(),operation + " clears all owned animation work")
		if operation == "error": check(scene.board_scene.input_is_locked() and not scene.board_scene.visible,"delivery gate survives concurrent cancellation")

func _ready_board(scene: RunScene) -> void:
	for frame in 240:
		await process_frame
		if not scene.board_scene.input_is_locked() and scene.board_scene.visible: return
	check(false,"motion scene ready")
