extends "res://tests/game/game_test.gd"

func _initialize() -> void: _run.call_deferred()

func ready_board(scene: RunScene) -> void:
	for frame in 120:
		await process_frame
		if not scene.board_scene.input_is_locked() and scene.board_scene.visible: return
	check(false,"board loading finishes")

func _run() -> void:
	var fixture := GemDeliveryFixture.create("res://artifacts/game/p1-playback/%d" % Time.get_ticks_usec(),load("res://data/presentation/default.tres"))
	check(not fixture.is_empty(),"explicit delivered art fixture")
	if fixture.is_empty(): finish("test_game_playback"); return
	check(root.get_node("GemForge").open_library(fixture.library,fixture.catalog),"fixture library opens")
	var scene: RunScene = load("res://scenes/run/run_scene.tscn").instantiate()
	root.add_child(scene); await ready_board(scene)
	scene.run_controller.start_new_run({"seed":4,"starting_moves":2}); await ready_board(scene)
	var initial := scene.run_controller.run_state.to_dict()
	var command: SwapCommand = scene.run_controller.enumerate_legal_swaps()[0]
	scene._on_swap_requested(command.origin,command.destination)
	check(scene.run_controller.run_state.revision == 1 and scene.run_controller.run_state.moves_remaining == 1 and scene.board_scene.input_is_locked(),"real scene commits before playback await")
	var committed := scene.run_controller.run_state.digest()
	var event_digest: String = scene.run_controller.last_result.event_digest
	scene.board_scene.set_input_gate("modal",true)
	scene.skip_playback(); await process_frame
	check(scene.board_scene.input_is_locked(),"skip cannot release modal gate")
	scene.board_scene.set_input_gate("modal",false)
	check(scene.run_controller.run_state.digest() == committed and scene.board_scene._board_state.digest() == scene.run_controller.get_board().digest(),"skip snaps to committed view without rules")
	scene.run_controller.restore_snapshot(initial); await ready_board(scene)
	scene.instant_playback = true
	await scene._on_swap_requested(command.origin,command.destination)
	check(scene.run_controller.run_state.digest() == committed and scene.run_controller.last_result.event_digest == event_digest,"instant playback preserves checkpoint")
	scene.run_controller.restore_snapshot(initial); await ready_board(scene)
	scene.instant_playback = false; Engine.time_scale = 40.0
	await scene._on_swap_requested(command.origin,command.destination)
	Engine.time_scale = 1.0
	check(scene.run_controller.run_state.digest() == committed and scene.run_controller.last_result.event_digest == event_digest and not scene.board_scene.input_is_locked(),"sequential playback preserves checkpoint and releases its gate")
	var next: SwapCommand = scene.run_controller.enumerate_legal_swaps()[0]
	scene._on_swap_requested(next.origin,next.destination)
	scene._on_restart_pressed(); await ready_board(scene)
	for frame in 3: await process_frame
	check(scene.run_controller.run_state.digest() == CanonicalCodec.digest(initial) and not scene.board_scene.input_is_locked(),"restart during playback ignores stale continuation")
	var before := scene.run_controller.run_state.digest()
	await scene._on_swap_requested(Vector2i.ZERO,Vector2i.ZERO)
	check(scene.run_controller.run_state.digest() == before and not scene.board_scene.input_is_locked(),"real rejected bounce leaves rules unchanged")
	scene._on_swap_requested(command.origin,command.destination)
	scene._show_delivery_error("controlled playback delivery failure")
	scene.skip_playback(); await process_frame
	check(not scene.board_scene.visible and scene.board_scene.input_is_locked(),"skip cannot unlock delivery failure")
	scene.run_controller.restart(); await ready_board(scene)
	check(scene._delivery_error.is_empty(),"explicit valid restart recovers delivery")
	scene._on_swap_requested(command.origin,command.destination)
	var detached := scene.run_controller; var digest := detached.run_state.digest()
	scene.queue_free(); await process_frame; await process_frame
	check(detached.run_state.digest() == digest,"scene destruction cancels presentation without rule work")
	finish("test_game_playback")
