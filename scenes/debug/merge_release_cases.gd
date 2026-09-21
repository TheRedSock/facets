class_name MergeReleaseCases
extends RefCounted
## Fixed executable witnesses run outside unassisted performance measurements.
var failures: Array = []
var observations: Array = []
var tree: SceneTree

func check(okay: bool, label: String) -> void:
	observations.append({"case":label,"passed":okay})
	if not okay: failures.append(label)

func loaded(view: MergeRoomView) -> bool:
	var until := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec() < until:
		await tree.process_frame
		if not view.error.is_empty(): check(false,view.error); return false
		if view.board != null and view.board.visible and view.player.live.size() > 0:
			view._begin.pressed.emit(); return true
	check(false,"fixture_load_timeout"); return false

func window(view: MergeRoomView, id: int) -> bool:
	var until := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec() < until:
		await tree.process_frame
		if not view.error.is_empty(): check(false,view.error); return false
		if view.session.window_id == id and view.can_input(): return true
	check(false,"fixture_window_timeout/"+str(id)); return false

func run(scene_tree: SceneTree, report_path: String = "") -> Dictionary:
	tree = scene_tree
	var state := InterventionFixture.create(16,"automatic_chain")
	state.board.set_tile(Vector2i(1,2),state.catalog.create_tile(2))
	var view := MergeRoomView.new(); view.initial_override = state.to_dict(); view.automatic_clock = false
	view.practice_mode = true
	tree.root.add_child(view)
	if await loaded(view):
		MergeProbe.gesture(view,InterventionFixture.command(view.session.state),true)
		if await window(view,1):
			check(view.session.clock.assisted and not view.clock_adapter.automatic,"practice_explicitly_assisted_without_deadline")
			var promoted_id := view.session.state.board.get_tile(Vector2i(2,3)).instance_id
			check(view.player.live[promoted_id].tier == 2,"promoted_identity_first_frame")
			if not report_path.is_empty():
				await RenderingServer.frame_post_draw
				tree.root.get_texture().get_image().save_png(report_path+".practice.png")
			view.session.tick(19)
			MergeProbe.gesture(view,RoomCommand.exchange(view.session.state,Vector2i(2,3),Vector2i(1,3)),false)
			if await window(view,2):
				check(view.session.state.board.get_tile(Vector2i(1,3)).tier == 3 and view.session.state.board.get_tile(Vector2i(2,4)).tier == 2,"stronger_match_denies_automatic")
				check(view.session.history.back().tick == 19,"latest_legal_receipt")
				if not report_path.is_empty():
					await RenderingServer.frame_post_draw
					tree.root.get_texture().get_image().save_png(report_path+".redirection.png")
				view._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
				check(view.session.clock.paused and not view.can_input(),"focus_loss_freezes_input")
				var saved := view.session.snapshot()
				check(view.restore_session(saved) and view.session.clock.paused,"parked_restore_is_assisted_pause")
				view._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
				view.clock_adapter.pause(false,"manual")
				view.clock_adapter.pass_now()
				var until := Time.get_ticks_msec()+5000
				while not view.player.observations.any(func(o: Dictionary) -> bool: return o.kind == "gravity_started") and Time.get_ticks_msec() < until: await tree.process_frame
				check(view.player.observations.any(func(o: Dictionary) -> bool: return o.kind == "gravity_started"),"default_gravity_in_release")
		view.restart()
		if await loaded(view):
			check(CanonicalCodec.digest(view.session.initial) == CanonicalCodec.digest(state.to_dict()),"restart_identity")
			view.reduced_motion = true; view.player.reduced_motion = true
			MergeProbe.gesture(view,InterventionFixture.command(view.session.state),true)
			if await window(view,1):
				view.session.tick(20)
				if await window(view,2): check(view.session.state.board.get_tile(Vector2i(2,5)).tier == 3,"no_input_automatic_merge_reduced_motion")
		view.restart()
		if await loaded(view):
			view.executor.injected_delay_us = 220000
			MergeProbe.gesture(view,InterventionFixture.command(view.session.state),false)
			if await window(view,1): check(view.starvation > 0 and view.session.clock.tick == 0,"deliberate_late_result_holds_then_full_window")
		view.restart()
		if await loaded(view):
			MergeProbe.gesture(view,InterventionFixture.command(view.session.state),false)
			view._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
			var until := Time.get_ticks_msec()+5000
			while not view.session.clock.started and Time.get_ticks_msec() < until: await tree.process_frame
			check(view.session.clock.started and view.session.clock.paused and not view.can_input(),"focus_loss_during_motion_pauses_next_window")
			view._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	var worker := view.executor
	view.queue_free(); await tree.process_frame; await tree.process_frame
	check(not worker._thread.is_started() and worker._pending.is_empty(),"fixture_teardown_no_worker")
	view = MergeRoomView.new(); view.initial_override = MergeCharacterization.terminal_fixture().to_dict()
	tree.root.add_child(view)
	if await loaded(view):
		var cues: Array = []
		view.board.presentation_cue.connect(func(cue: String): cues.append(cue))
		MergeProbe.gesture(view,InterventionFixture.command(view.session.state),true)
		var until := Time.get_ticks_msec()+5000
		while (view.session.phase != "complete" or view.player.motion_busy or not view.queue.is_empty()) and Time.get_ticks_msec() < until: await tree.process_frame
		check(view.session.phase == "complete" and view.session.state.moves_remaining == 0 and view.session.window_id == 0 and not view.can_input(),"last_work_success_terminal_view")
		check("room_success" in cues,"success_audio_cue_from_committed_result")
		view.restart()
		if await loaded(view): check(view.session.phase == "ready" and view.session.state.moves_remaining == 1,"terminal_restart")
	view.queue_free(); await tree.process_frame; await tree.process_frame
	# The actual menu button creates the production room; its Menu button removes
	# that room and returns visibility. No test-only scene substitutes this path.
	var menu: Control = load("res://scenes/menu/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	var button: Button
	for child in menu.find_children("*","Button",true,false):
		if child.text == "Play · merge interventions": button = child
	check(button != null,"production_menu_entry")
	if button != null:
		button.pressed.emit(); await tree.process_frame
		var entered: MergeRoomView
		for child in tree.root.get_children():
			if child is MergeRoomView: entered = child
		check(entered != null and not menu.visible,"production_entry_opens_room")
		if entered != null and await loaded(entered):
			worker = entered.executor
			for child in entered.find_children("*","Button",true,false):
				if child.text == "Menu": child.pressed.emit(); break
			await tree.process_frame; await tree.process_frame
			check(menu.visible and not worker._thread.is_started(),"menu_navigation_shuts_down_worker")
	menu.queue_free(); await tree.process_frame
	await tree.create_timer(0.2).timeout
	return {"observations":observations,"failures":failures}
