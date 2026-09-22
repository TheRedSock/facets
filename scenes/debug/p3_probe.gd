class_name P3Probe
extends Node
## Explicit diagnostic entry point. Native witnesses use real controls and
## presentation; deterministic tuning has no animation/performance claim.
var failures: Array = []
var observations: Array = []
var output := ""
var clicks := 0

func check(okay: bool, label: String) -> void:
	observations.append({"case":label,"passed":okay})
	if not okay: failures.append(label); printerr("FAIL: "+label)

func wait_for(predicate: Callable, label: String, seconds: int = 20) -> bool:
	var deadline := Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if predicate.call(): return true
	check(false,"timeout/"+label); return false

func activate(control: BaseButton) -> void:
	clicks += 1
	var scroll := control.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll != null: scroll.ensure_control_visible(control)
	await get_tree().process_frame
	control.grab_focus()
	if scroll != null: scroll.ensure_control_visible(control)
	await get_tree().process_frame
	await get_tree().process_frame
	if clicks%2 == 0:
		var key := InputEventKey.new(); key.keycode = KEY_ENTER; key.pressed = true; Input.parse_input_event(key)
		await get_tree().process_frame
		key = InputEventKey.new(); key.keycode = KEY_ENTER; Input.parse_input_event(key)
	else:
		var position := control.get_viewport().get_final_transform()*control.get_global_rect().get_center()
		var mouse := InputEventMouseButton.new(); mouse.position = position; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = true; Input.parse_input_event(mouse)
		await get_tree().process_frame
		mouse = InputEventMouseButton.new(); mouse.position = position; mouse.button_index = MOUSE_BUTTON_LEFT; Input.parse_input_event(mouse)
	await get_tree().process_frame

func press(view: ExpeditionView, text: String) -> bool:
	if view.preview_pending: await wait_for(func() -> bool: return not view.preview_pending,"preview_before_input")
	await get_tree().process_frame
	for node in view.find_children("*","Button",true,false):
		if node.text == text and node.is_visible_in_tree(): await activate(node); return true
	check(false,"missing_control/"+text); return false

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.get_base_dir().path_join(name+".png"))

func key(code: int) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true; Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new(); event.keycode = code; Input.parse_input_event(event)
	await get_tree().process_frame

func board_gesture(view: MergeRoomView, command: RoomCommand, keyboard: bool) -> bool:
	var revision := view.session.state.revision
	if command.data.kind != "swap":
		for control in view._tool_buttons:
			if control.get_meta("kind") == command.data.kind: await activate(control); break
		check(view.board.has_focus(),"tool_returns_keyboard_focus_to_board")
		if command.data.kind == "action.exchange":
			view.board.cursor_cell = command.data.origin; await key(KEY_ENTER)
			view.board.cursor_cell = command.data.destination; await key(KEY_ENTER)
		else: view.board.cursor_cell = command.data.cell; await key(KEY_ENTER)
	elif keyboard:
		view.board.grab_focus(); view.board.cursor_cell = command.data.origin
		await key(KEY_ENTER)
		var direction: Vector2i = command.data.destination-command.data.origin
		await key(KEY_RIGHT if direction.x > 0 else (KEY_LEFT if direction.x < 0 else (KEY_DOWN if direction.y > 0 else KEY_UP)))
		await key(KEY_ENTER)
	else:
		var transform := view.board.get_viewport().get_final_transform()*view.board.get_global_transform()
		var origin: Vector2 = transform*(view.board._board_offset+view.board._cell_to_pixel(command.data.origin)+Vector2(view.board._cell_size)*0.5)
		var destination: Vector2 = transform*(view.board._board_offset+view.board._cell_to_pixel(command.data.destination)+Vector2(view.board._cell_size)*0.5)
		var press_event := InputEventMouseButton.new(); press_event.position = origin; press_event.button_index = MOUSE_BUTTON_LEFT; press_event.pressed = true; Input.parse_input_event(press_event)
		await get_tree().process_frame
		var drag := InputEventMouseMotion.new(); drag.position = destination; drag.relative = destination-origin; drag.button_mask = MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(drag)
		await get_tree().process_frame
		press_event = InputEventMouseButton.new(); press_event.position = destination; press_event.button_index = MOUSE_BUTTON_LEFT; Input.parse_input_event(press_event)
		await get_tree().process_frame
	return view.session.state.revision > revision or not view.session.reservation.is_empty()

func watch_outcome(view: ExpeditionView, live: MergeRoomView) -> void:
	live.outcome_committed.connect(func():
		check(view.run.session == null and view.run.phase in ["carry_selection","results"] and not live.queue.is_empty(),"expedition_outcome_precedes_terminal_presentation"),CONNECT_ONE_SHOT)

func native_route(route: String) -> void:
	var path := MergeProbe.option("--p3-witnesses","").path_join(route+".fac")
	var decoded := CanonicalCodec.decode(FileAccess.get_file_as_bytes(path))
	check(decoded.ok,"reference_decode/"+route)
	if not decoded.ok: return
	var reference: Dictionary = decoded.value
	check(ExpeditionState.restored(reference,false).ok,"reference_full_replay/"+route)
	var view := ExpeditionView.new(); view.diagnostic_practice = true
	view.store.directory = output.get_base_dir().path_join("slots/"+route)
	get_tree().root.add_child(view)
	await get_tree().process_frame
	await wait_for(func() -> bool: return view.find_children("*","TileView",true,false).size() == 8,"briefing_previews")
	await capture(route+"-briefing")
	var room_number := 0
	for entry in reference.history.slice(1):
		var command: Dictionary = entry.command
		match command.kind:
			"begin_room":
				await press(view,"Begin room")
				if not await wait_for(func() -> bool: return is_instance_valid(view.room_view) and view.room_view.board.visible,"room_load"):
					view.queue_free(); await get_tree().process_frame; return
				await capture(route+"-room"+str(room_number))
			"room_outcome":
				var live := view.room_view
				watch_outcome(view,live)
				var expected: Array = command.resolution.history
				var issued := 0; var verified := 0
				var saved_window := false
				var deadline := Time.get_ticks_msec()+180000
				while view.run.phase == "playing" and Time.get_ticks_msec() < deadline:
					await get_tree().process_frame
					var session := live.session
					while verified < session.history.size():
						check(verified < expected.size() and session.history[verified].state_digest == expected[verified].state_digest and session.history[verified].event_digest == expected[verified].event_digest,"native_batch/"+route+"/"+str(room_number)+"/"+str(verified))
						verified += 1
					if not live.error.is_empty(): check(false,live.error); break
					if not live.can_input(): continue
					if session.phase == "merge_window":
						if not saved_window:
							saved_window = true
							await press(view,"Save")
							var saved_state := CanonicalCodec.digest(view.run.current().to_dict())
							var forge := get_node("/root/GemForge"); var budget: int = forge.prefetch_budget_bytes
							forge.prefetch_budget_bytes = 0
							await press(view,"Continue")
							await wait_for(func() -> bool: return not view._loading,"failed_continue")
							check(view.room_view == live and CanonicalCodec.digest(view.run.current().to_dict()) == saved_state,"failed_continue_preserves_live_board_rng_and_resources")
							forge.prefetch_budget_bytes = budget
							await press(view,"Continue")
							await wait_for(func() -> bool: return not view._loading and is_instance_valid(view.room_view) and view.room_view.board.visible,"parked_continue")
							live = view.room_view
							watch_outcome(view,live)
							check(live.session.clock.paused and live.session.clock.assisted and CanonicalCodec.digest(view.run.current().to_dict()) == saved_state,"native_parked_continue_exact_paused")
							live.clock_adapter.pause(false,"manual")
						live.clock_adapter.pass_now(); continue
					while issued < expected.size() and expected[issued].command.is_empty(): issued += 1
					if issued >= expected.size(): check(false,"reference_commands_exhausted"); break
					var action := RoomCommand.parse(expected[issued].command); issued += 1
					check(await board_gesture(live,action,issued%2 == 0),"native_command/"+str(issued))
				check(view.run.phase != "playing","room_terminated/"+route)
				check(live.session.history.size() == expected.size(),"all_batches/"+route+"/"+str(room_number))
				await wait_for(func() -> bool: return view.room_view == null,"terminal_presentation")
				if view.run.phase == "playing": view.queue_free(); await get_tree().process_frame; return
				check(view.run.history.back().state_digest == entry.state_digest,"room_boundary/"+route+"/"+str(room_number))
				room_number += 1
			"confirm_carry":
				if view.preview_pending: await wait_for(func() -> bool: return not view.preview_pending,"carry_previews")
				check(is_instance_valid(view.retained_room) and view.retained_room.player.live.size() > 0,"old_board_retained_for_choices")
				for id in command.ids:
					for control in view.panel.find_children("*","CheckButton",true,false):
						if control.get_meta("gem_id","") == id: await activate(control)
				await press(view,"Confirm carry")
				check(view.run.phase == "reward_selection","carry_controls")
				if view.run.phase != "reward_selection": view.queue_free(); await get_tree().process_frame; return
				if view.preview_pending: await wait_for(func() -> bool: return not view.preview_pending,"reward_previews")
				await wait_for(func() -> bool: return view.find_children("*","TileView",true,false).size() > view.retained_room.player.live.size(),"live_choice_previews")
				await capture(route+"-rewards"+str(room_number))
				await press(view,"Save expedition")
				var before := CanonicalCodec.digest(view.run.snapshot())
				await press(view,"Continue saved expedition")
				await wait_for(func() -> bool: return not view._loading,"continue")
				check(CanonicalCodec.digest(view.run.snapshot()) == before,"disk_continue_preserves_offers_and_rng")
			"choose_reward":
				var before := CanonicalCodec.digest(view.run.snapshot())
				var forge := get_node("/root/GemForge"); var budget: int = forge.prefetch_budget_bytes
				forge.prefetch_budget_bytes = 0
				await press(view,"Choose "+command.id.capitalize())
				await wait_for(func() -> bool: return not view._loading,"failed_reward")
				check(CanonicalCodec.digest(view.run.snapshot()) == before,"failed_preflight_retains_choices")
				forge.prefetch_budget_bytes = budget
				await press(view,"Choose "+command.id.capitalize())
				await wait_for(func() -> bool: return view.run.phase != "reward_selection","reward_retry")
			"choose_route": await press(view,"Take "+command.id.capitalize())
			"enter_room":
				await press(view,"Enter next room")
				await wait_for(func() -> bool: return view.run.phase == "briefing","entry")
	check(view.run.phase == "results" and view.run.current().phase == "complete","native_three_room_win/"+route)
	check(ExpeditionState.restored(view.run.snapshot(),false).ok,"native_complete_replay/"+route)
	var file := FileAccess.open(output.get_base_dir().path_join(route+"-native.fac"),FileAccess.WRITE); file.store_buffer(CanonicalCodec.encode(view.run.snapshot())); file.close()
	await capture(route+"-results")
	await press(view,"Restart expedition")
	await wait_for(func() -> bool: return view.run.phase == "briefing","restart")
	check(view.run.current().settings.is_empty() and view.run.room_index == 0,"restart_fresh_run")
	await press(view,"Begin room")
	await wait_for(func() -> bool: return is_instance_valid(view.room_view) and view.room_view.board.visible,"restart_load")
	var worker := view.room_view.executor
	await press(view,"Menu")
	await get_tree().process_frame
	check(not is_instance_valid(view) and not worker._thread.is_started(),"menu_releases_worker_and_views")

func choice_matrix() -> void:
	# Explicit synthetic UI fixtures isolate all choices; full natural success
	# and checkpoint evidence comes from native_route, never these mutations.
	var pool := ["aquamarine","beryl_bridge","next_room_craft","steady_hand"]
	for first in pool:
		for second in pool:
			if first == second and first != "next_room_craft": continue
			var view := ExpeditionView.new(); view.run = ExpeditionState.create(7).run
			view.run.phase = "reward_selection"; view.run.offers = pool.duplicate()
			get_tree().root.add_child(view)
			await press(view,"Choose "+first.capitalize())
			await wait_for(func() -> bool: return view.run.phase == "route_selection","matrix_first")
			check(view.run.selected_reward == first,"first_reward_ui/"+first)
			view.run.room_index = 1; view.run.phase = "reward_selection"; view.run.offers = view.run.reward_pool(); view.show_phase()
			await press(view,"Choose "+second.capitalize())
			await wait_for(func() -> bool: return view.run.phase == "next_room_ready","matrix_second")
			check(view.run.selected_reward == second,"second_reward_ui/"+first+"/"+second)
			if view.preview_pending: await wait_for(func() -> bool: return not view.preview_pending,"matrix_previews")
			check(view.error.is_empty(),"matrix_delivery/"+first+"/"+second)
			view.queue_free(); await get_tree().process_frame
	for count in 3:
		var view := ExpeditionView.new(); view.run = ExpeditionState.create(7).run; view.run.phase = "carry_selection"
		get_tree().root.add_child(view)
		if view.preview_pending: await wait_for(func() -> bool: return not view.preview_pending,"matrix_carry_previews")
		var controls := view.panel.find_children("*","CheckButton",true,false)
		for index in count: await activate(controls[index])
		await press(view,"Confirm carry")
		check(view.run.phase == "reward_selection" and view.run.carry.size() == count,"zero_one_two_carry_ui/"+str(count))
		if view.preview_pending: await wait_for(func() -> bool: return not view.preview_pending,"matrix_carry_done")
		view.queue_free(); await get_tree().process_frame
	for operation in ["menu","restart"]:
		var view := ExpeditionView.new(); get_tree().root.add_child(view)
		view.run.begin(view.run.revision()); view.show_phase()
		await get_tree().process_frame
		var worker := view.room_view.executor
		if operation == "restart": view.restart(); await get_tree().process_frame
		view.queue_free()
		for frame in 60: await get_tree().process_frame
		check(not worker._thread.is_started(),"loading_cancel_releases_worker/"+operation)
	var menu: Control = load("res://scenes/menu/main_menu.tscn").instantiate(); get_tree().root.add_child(menu)
	var entry: Button
	for control in menu.find_children("*","Button",true,false):
		if control.text == "Play · P3 expedition": entry = control
	check(entry != null,"production_p3_menu_entry")
	if entry != null:
		await activate(entry)
		var entered: ExpeditionView
		for child in get_tree().root.get_children():
			if child is ExpeditionView: entered = child
		check(entered != null and not menu.visible,"production_menu_opens_expedition")
		if entered != null:
			await press(entered,"Begin room")
			await wait_for(func() -> bool: return is_instance_valid(entered.room_view) and entered.room_view.board.visible,"production_menu_room")
			check(entered.room_view.board.has_focus(),"begin_focuses_keyboard_board")
			await press(entered,"Menu")
			await get_tree().process_frame
			check(menu.visible and not is_instance_valid(entered),"production_menu_return")
	menu.queue_free(); await get_tree().process_frame

func tuning() -> Array:
	var records: Array = []
	for policy in ["first-v1","mixed-v1"]:
		for seed_value in range(1,101):
			var expedition: ExpeditionState = ExpeditionState.create(seed_value).run
			var rng := SeededRng.new(); rng.reseed(900000+seed_value)
			var steps := 0; var failure := ""
			var counters := {"work_spent":0,"craft_earned":0,"craft_clipped":0,"craft_spent":0,"rubble_damage":0,"highest_promoted":0,"highest_extracted":0,"rearrangements":0,"tools":{},"families":{}}
			while expedition.phase != "results" and steps < 1000:
				steps += 1; var result := {"ok":true}
				match expedition.phase:
					"briefing": result = expedition.begin(expedition.revision())
					"playing":
						var command: RoomCommand
						if expedition.session.phase == "ready": command = MergeProbe.choose(expedition.session,"mixed" if policy == "mixed-v1" else "all-pass",rng)
						elif expedition.session.phase == "merge_window": expedition.session.presented(); expedition.session.tick(20)
						result = expedition.session.apply(command)
						if result.ok:
							for fact in result.facts:
								match fact.type:
									"resource_spent":
										if fact.resource == "resource.action_budget": counters.work_spent += fact.amount
										else: counters.craft_spent += fact.amount
									"craft_settled": counters.craft_earned += fact.gain; counters.craft_clipped += fact.eligible_award-fact.gain
									"obstacle_damaged": counters.rubble_damage += fact.damage
									"tile_promoted": counters.highest_promoted = maxi(counters.highest_promoted,fact.new.tier)
									"tile_extracted": counters.highest_extracted = maxi(counters.highest_extracted,fact.tier)
									"board_rearranged": counters.rearrangements += 1
									"tool_activated": counters.tools[fact.kind] = counters.tools.get(fact.kind,0)+1
									"reaction_applied": counters.families[fact.reaction_id] = counters.families.get(fact.reaction_id,0)+1
						if result.ok and expedition.session.phase in ["complete","failed"]: result = expedition.finish_room()
					"carry_selection": result = expedition.confirm_carry(expedition.eligible_carry().slice(0,2).map(func(t: Dictionary) -> String: return t.instance_id),expedition.revision())
					"reward_selection": result = expedition.choose_reward(expedition.offers[0],expedition.revision())
					"route_selection": result = expedition.choose_route("deep_seam" if seed_value%2 == 0 else "commission",expedition.revision())
					"next_room_ready": result = {"ok":expedition.publish_entry(expedition.prepare_next())}
				if not result.ok: failure = result.get("code","entry_failed"); break
			check(failure.is_empty() and expedition.phase == "results","tuning_terminal/"+policy+"/"+str(seed_value))
			check(ExpeditionState.restored(expedition.snapshot(),false).ok,"tuning_full_replay/"+policy+"/"+str(seed_value))
			var snapshot := CanonicalCodec.encode(expedition.snapshot())
			var file := FileAccess.open(output.get_base_dir().path_join(policy+"-"+str(seed_value)+".fac"),FileAccess.WRITE); file.store_buffer(snapshot); file.close()
			records.append({"policy":policy,"seed":seed_value,"steps":steps,"room":expedition.room_index,"outcome":expedition.current().phase,"failure":failure,"room_failure_reason":expedition.current().room.failure_reason,"counters":counters,"digest":CanonicalCodec.digest(expedition.snapshot())})
			if seed_value%10 == 0: print("P3_TUNING: ",policy," ",seed_value); await get_tree().process_frame
	return records

func run(path: String) -> void:
	output = path
	if FileAccess.file_exists(path): printerr("FAIL: report exists"); get_tree().quit(1); return
	var report := {"schema":"facets-p3-probe-v1","profile":P3Content.PROFILE,"content":P3Content.CONTENT,"editor":OS.has_feature("editor"),"executable":OS.get_executable_path(),"display":str(DisplayServer.window_get_size())}
	if "--p3-tuning" in OS.get_cmdline_user_args():
		report.mode = "deterministic_tuning"
		report.rules_profile = MergeProbe.option("--p3-tuning-profile","p3-production-v1")
		report.seed_list = MergeProbe.option("--p3-seed-list","p3-seeds-1-100-v1")
		check(report.rules_profile == "p3-production-v1" and report.seed_list == "p3-seeds-1-100-v1","immutable_named_tuning_inputs")
		report.seed_scope = "integers 1..100 inclusive; no exclusions"; report.rules_digest = CanonicalCodec.digest(RuleSet.for_p3().to_dict())
		if failures.is_empty(): report.rooms = await tuning()
	else:
		report.mode = "native_lifecycle_assisted"
		for route in ["deep_seam","commission-opening"]: await native_route(route)
		await choice_matrix()
	report.observations = observations; report.failures = failures; report.status = "passed" if failures.is_empty() else "failed"
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("CHECK_COMPLETE: p3_probe"); get_tree().quit(0 if failures.is_empty() else 1)
