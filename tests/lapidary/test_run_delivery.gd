extends SceneTree
## Exercise the real asynchronous RunScene preflight/rebuild boundary.
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;printerr("FAIL: "+label)
func _run()->void:
	var fixture:=GemDeliveryFixture.create("res://artifacts/run-delivery/%d"%Time.get_ticks_usec(),load("res://data/presentation/default.tres"))
	if fixture.is_empty():printerr("FAIL: Cannot build explicit delivery fixture");quit(1);return
	var forge:Node=root.get_node("GemForge")
	check(forge.open_library(fixture.library,fixture.catalog),"Default semantic catalog opens")
	# Load after autoload initialization, as the exported external probe does.
	var scene:Control=load("res://scenes/run/run_scene.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await process_frame
		if scene.board_scene.visible and scene.board_scene._tile_views.size()==64:break
	check(scene.board_scene.visible and not scene.board_scene._input_locked and scene.board_scene._tile_views.size()==64,"Run waits for preflight and displays its complete board")
	var invalid:=BoardState.new(Vector2i.ONE);var tile:=TileState.new();tile.tile_id=&"missing_delivery_tile";invalid.set_tile(Vector2i.ZERO,tile)
	await scene._on_board_changed(invalid)
	check("missing_delivery_tile" in scene._delivery_error,"Rebuild reports the missing tile")
	check(not scene.board_scene.visible and scene.board_scene._input_locked,"Awaited rebuild does not unhide/unlock a failed board")
	var valid:=BoardState.new(Vector2i.ONE);var replacement:=TileState.new();replacement.tile_id=&"quartz";valid.set_tile(Vector2i.ZERO,replacement)
	var before:=valid.compute_hash()
	await scene._on_board_changed(valid)
	check(scene._delivery_error.is_empty() and scene.board_scene.visible and not scene.board_scene._input_locked,"Explicit new valid board recovers from a failed delivery")
	check(before==valid.compute_hash(),"Presentation leaves simulation state unchanged")
	scene.free();print("CHECK_COMPLETE: test_run_delivery");quit(1 if failures else 0)
