extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for route in ["deep_seam","commission"]:
		var decoded := CanonicalCodec.decode(FileAccess.get_file_as_bytes("res://tests/fixtures/p3_expedition_v1/"+route+".fac"))
		check(decoded.ok,"canonical expedition reference decodes")
		if not decoded.ok: continue
		var restored := ExpeditionState.restored(decoded.value,false)
		check(restored.ok,"full frozen expedition checkpoints "+route)
		if not restored.ok: continue
		var run: ExpeditionState = restored.run
		check(run.phase == "results" and run.room_index == 2 and run.state.phase == "complete","three-room success witness "+route)
		var altered: Dictionary = decoded.value.duplicate(true); altered.history[1].state_digest = "tampered"
		check(not ExpeditionState.restored(altered,false).ok,"tampered transition checkpoint rejected")
	var failed: ExpeditionState = ExpeditionState.create(1).run
	check(failed.begin(failed.revision()).ok,"failure witness begins")
	for index in 300:
		var result: Dictionary
		if failed.session.phase == "ready":
			var swaps := ActionLegality.enumerate_legal_swaps(failed.session.state.board)
			if swaps.is_empty(): check(false,"failure policy legal swap"); break
			result = failed.session.apply(RoomCommand.exchange(failed.session.state,swaps[0].origin,swaps[0].destination))
		else:
			if failed.session.phase == "merge_window": failed.session.presented(); failed.session.tick(20)
			result = failed.session.apply()
		check(result.ok,"failure policy batch commits")
		if not result.ok or failed.session.phase in ["complete","failed"]: break
	check(failed.session.phase == "failed" and failed.finish_room().ok,"actual Work-exhaustion expedition outcome")
	check(ExpeditionState.restored(failed.snapshot(),false).ok,"complete failure replay")
	write_report("failure.fac",failed.snapshot(),true)
	finish("test_p3_replay")
