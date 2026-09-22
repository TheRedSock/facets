extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for amount in [0,1,2]:
		var created := ExpeditionState.create(7); check(created.ok,"expedition initial entry")
		if not created.ok: continue
		var run: ExpeditionState = created.run
		check(run.phase == "briefing" and run.state.board.id_namespace == "expedition","expedition owns briefing and namespace")
		var before := CanonicalCodec.encode(run.snapshot())
		check(not run.begin(run.revision()+1).ok and before == CanonicalCodec.encode(run.snapshot()),"stale Begin is pure")
		check(run.begin(run.revision()).ok,"begin commits")
		# Explicit transition fixture: behavior of normal room outcomes is tested
		# through the kernel separately, not claimed by this synthetic completion.
		run.session.state.board.obstacles.clear(); run.session.state.phase = "complete"; run.session.phase = "complete"
		check(run.finish_room().ok,"terminal room closes input for carry")
		var eligible := run.eligible_carry(); check(eligible.size() >= amount,"carry fixture has eligible gems")
		var ids: Array = []
		for index in amount: ids.append(eligible[index].instance_id)
		before = CanonicalCodec.encode(run.snapshot())
		check(not run.confirm_carry(["expedition/stale"],run.revision()).ok,"stale carry rejected")
		if not ids.is_empty(): check(not run.confirm_carry([ids[0],ids[0]],run.revision()).ok,"duplicate carry rejected")
		check(before == CanonicalCodec.encode(run.snapshot()),"rejected carry preserves complete state")
		check(run.confirm_carry(ids,run.revision()).ok,"ordered zero/one/two carry commits")
		run.phase = "next_room_ready"; run.entry_bonus = 1; run.state.room.craft = 6
		var definition := run.state.room.definition
		before = CanonicalCodec.encode(run.snapshot())
		var preparation := run.prepare_entry(definition,"after_opening")
		check(not preparation.ok and before == CanonicalCodec.encode(run.snapshot()),"failed opening preserves RNG/bonus/carry/history")
		if amount > 0:
			check(not run.prepare_entry(definition,"",[Vector2i(2,2)]).ok,"blocked or insufficient staging rejects before draw")
			check(before == CanonicalCodec.encode(run.snapshot()),"staging rejection is pure")
		preparation = run.prepare_entry(definition)
		check(preparation.ok,"carry-aware preparation succeeds")
		if not preparation.ok: continue
		check(not run.publish_entry(preparation,false) and before == CanonicalCodec.encode(run.snapshot()),"asset failure retains entire previous run")
		var next: RunState = preparation.candidate
		check(next.board.next_instance > run.state.board.next_instance,"allocator never restarts across rooms")
		check(next.next_event == run.state.next_event and next.next_action == run.state.next_action,"entry preserves global command allocators before commit")
		for index in amount:
			check(next.board.get_tile(ExpeditionState.STAGING[index]).instance_id == ids[index],"staging preserves ordered carry identity")
		check(next.room.craft == 4 and next.room_uses.is_empty(),"entry Craft and room uses reset")
		for stream in ["rewards","routes","recovery"]: check(next.streams.stream(stream).capture() == run.state.streams.stream(stream).capture(),"entry preserves "+stream+" stream")
		check(run.publish_entry(preparation) and run.entry_bonus == 0 and run.carry.is_empty(),"entry commits and consumes bonus once")
		check(not run.publish_entry(preparation),"stale entry candidate cannot publish twice")
		check(run.begin(run.revision()).ok and RunState.restored(run.session.state.to_dict()).ok,"new room is admitted with continuous history")
	finish("test_p3_entry")
