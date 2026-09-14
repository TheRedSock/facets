extends SceneTree
## Explicit candidate capture. Never overwrites checked-in expected results.
func _initialize() -> void:
	var state := RunState.new()
	state.catalog = GameTestCatalog.create()
	state.board = GameFixtureAdapter.board(GameFixtureAdapter.read_cases()[0])
	state.moves_remaining = 2; state.streams = RngStreamBank.new(140901); state.sync_adapters()
	var result := ActionTransaction.resolve(state,SwapCommand.new(Vector2i(1,1),Vector2i(1,0)))
	if not result.ok: printerr("FAIL: " + result.code); quit(1); return
	var output := FileAccess.open("res://artifacts/game/p1-implementation/action-vector-candidate.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"case":"match_3","build":Engine.get_version_info().string,"initial_digest":state.digest(),"state_digest":result.state_digest,"event_digest":result.event_digest,"facts":result.facts,"fact_bytes":CanonicalCodec.encode(result.facts).hex_encode()},"\t"))
	output.close(); print("CHECK_COMPLETE: capture_action_vector"); quit()
