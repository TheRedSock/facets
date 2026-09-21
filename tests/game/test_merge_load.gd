extends "res://tests/game/game_test.gd"
## Characterization only: independent active reaction waves, beyond the shipped
## diagnostic dispatcher's once-per-scope rejection workload.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	CanonicalCodec.seal_shared_cache()
	var rows: Array = []
	for width in [8,16]:
		var room := RoomDefinitionResource.new(); room.room_id = "active_wave_%d" % width
		room.work = 1; room.layout = BoardLayoutResource.new(); room.layout.board_size = Vector2i(width,width)
		room.obstacles = [{"id":"rubble/load","cell":Vector2i(width-1,width-1),"kind":"rubble","durability":2}]; room.marked_ids = ["rubble/load"]
		var game := RunController.new(); check(game.start_room(room,71),"active-load room admits")
		game.apply_action(RoomCommand.begin(0))
		var initial := game.run_state.duplicate_state(); var source_digest := initial.digest()
		var expected_digest := ""; var expected_applied := 0
		for waves in [1,4,8]:
			var worker := Thread.new(); var began := Time.get_ticks_usec()
			check(worker.start(_work.bind(initial,waves)) == OK,"load worker starts")
			while worker.is_alive(): await process_frame
			var result: Dictionary = worker.wait_to_finish()
			result.worker_wall_us = Time.get_ticks_usec()-began
			check(result.errors.is_empty(),"all active waves admitted and fully hashed")
			if waves == 1: expected_digest = result.digest; expected_applied = result.applied
			check(result.applied == expected_applied*waves and result.applied > 0,"4x/8x active effect count, not merely rejected triggers")
			check(result.digest == expected_digest,"each independent wave has exact equal semantics")
			check(initial.digest() == source_digest,"synthetic worker never changes source")
			result.width = width; result.waves = waves
			result.swap_150ms_ratio = result.service_us/150000.0
			result.shortened_50ms_ratio = result.service_us/50000.0
			rows.append(result)
	write_report("active-waves.json",{"profile":"characterization_only","rows":rows,
		"scope":"1/4/8 independent active diagnostic promotion waves on detached boards, including copies, full admission and hashes per wave. This deliberately overcounts per-wave admission versus one optimized future batch; it is not authored content or a weaker-machine claim.",
		"ordinary_deadlines_required":false})
	finish("test_merge_load")

func _work(initial: RunState, waves: int) -> Dictionary:
	var began := Time.get_ticks_usec(); var applied := 0; var digest := ""; var errors: Array = []
	for wave in waves:
		var source := initial.duplicate_state()
		var swap := ActionLegality.enumerate_legal_swaps(source.board)[0]
		var context := MergeMoveContext.new(source,RoomCommand.exchange(source,swap.origin,swap.destination),1,"intervention")
		for cell in source.board.all_cells():
			var tile := source.board.get_tile(cell)
			if tile == null: continue
			var outcome := MergeReactionScope.promote_live(context,cell,tile.instance_id,"move","load/"+tile.instance_id)
			if not outcome.ok: errors.append(outcome.code)
			elif outcome.applied: applied += 1
		if not RunState.restored(source.to_dict(),false).ok: errors.append("admission")
		var encoded := CanonicalCodec.digest({"state":source.to_dict(),"context":context.capture()})
		if encoded.is_empty() or (wave > 0 and encoded != digest): errors.append("complete_hash")
		digest = encoded
	return {"applied":applied,"digest":digest,"errors":errors,"service_us":Time.get_ticks_usec()-began}
