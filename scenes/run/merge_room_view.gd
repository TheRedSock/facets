class_name MergeRoomView
extends Control
signal back_requested
signal room_finished
signal outcome_committed
signal restart_requested
signal save_requested
signal continue_requested
signal presentation_ready
var external_session: MergeSession
var _reported_terminal := false
var _committed_terminal := false
var seed_value := 1
var p3_mode := false
var initial_override := {}
static var preferred_reduced_motion := false
var reduced_motion := preferred_reduced_motion
var automatic_clock := true
var practice_mode := false
var begun := false
var application_focused := true
var session: MergeSession
var executor: MergeExecutor
var clock_adapter: MergeClock
var board: BoardScene
var player: MergePlayer
var audio: RoomAudio
var error := ""
var queue: Array = []
var telemetry: Array = []
var frame_us: Array = []
var starvation := 0
var main_frame_us := {}
var presented_batches: Array = []
var _window_deadline := 0
var _epoch := 0
var _motion_deadline := 0
var _waiting_since := 0
var _window_handoff := false
var _tool := ""
var _tool_origin := Vector2i(-1,-1)
var _status: Label
var _tool_buttons: Array[Button] = []
var _begin: Button
var _cancel_button: Button
var _notice := ""
var input_buffer := MergeInputBuffer.new()
var _buffer_overlay: Control
var _window_bar: ProgressBar
var _title: Label
var _instructions: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://assets/ui/themes/workshop.tres")
	var background := ColorRect.new(); background.color = Color("141a22")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var body := VBoxContainer.new(); margin.add_child(body)
	var bar := HFlowContainer.new(); body.add_child(bar)
	_button(bar,"Menu",func(): back_requested.emit(); queue_free())
	_button(bar,"Restart expedition" if external_session != null else "Restart",func():
		if external_session != null: restart_requested.emit()
		else: restart())
	var reduced := CheckButton.new(); reduced.text = "Reduced motion"
	reduced.button_pressed = reduced_motion; bar.add_child(reduced)
	reduced.toggled.connect(func(value: bool): reduced_motion = value; preferred_reduced_motion = value; player.reduced_motion = value)
	_button(bar,"Pause / resume",func():
		input_buffer.clear()
		if clock_adapter != null: clock_adapter.pause(not session.clock.paused,"manual"))
	_button(bar,"Pass window",func(): clock_adapter.pass_now() if clock_adapter != null else false)
	_button(bar,"Sound / mute",func(): audio.set_muted(not RoomAudio.muted))
	if p3_mode: _button(bar,"Collection / rewards",_show_collection)
	if external_session != null:
		_button(bar,"Save",func(): save_requested.emit())
		_button(bar,"Continue",func(): continue_requested.emit())
	_cancel_button = _button(bar,"Cancel selection",_cancel_selection)
	var split := HBoxContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(split)
	board = load("res://scenes/board/board_scene.tscn").instantiate()
	board.custom_minimum_size = Vector2(400,400); board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(board)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.x = 510; split.add_child(scroll)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x = 488; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(panel)
	_title = Label.new(); _title.text = "Reactive play"; _title.add_theme_font_size_override("font_size",24); panel.add_child(_title)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _status.custom_minimum_size.x = 300; panel.add_child(_status)
	_window_bar = ProgressBar.new(); _window_bar.max_value = 20; _window_bar.show_percentage = false
	_window_bar.custom_minimum_size.y = 12; panel.add_child(_window_bar)
	var instructions := Label.new(); instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.custom_minimum_size.x = 300
	instructions.text = "Clear the marked rubble. Swap adjacent gems to make a match.\n\nDuring a merge, you can make another match anywhere — including moving the upgraded gem before its next automatic match. Each swap costs 1 Work.\n\nNo input lets the next match or gravity continue. Take your time once the board settles."
	panel.add_child(instructions)
	_instructions = instructions
	_begin = _button(panel,"Begin room",func():
		_begin.hide(); begun = true
		board.grab_focus()
		if session.phase == "gravity": executor.continue_gravity()
		_refresh())
	for item in [["Exchange · 2 Craft","action.exchange"],["Clear · 2 Craft","action.clear_target"],["Promote · 3 Craft","action.promote_target"]]:
		var kind: String = item[1]
		var button := _button(panel,item[0],_select_tool.bind(kind))
		button.set_meta("kind",kind); _tool_buttons.append(button)
	audio = RoomAudio.new(); add_child(audio); board.presentation_cue.connect(audio.play)
	board.swap_requested.connect(request_swap); board.cell_pressed.connect(_target)
	board.selection_canceled.connect(_cancel_selection)
	board.external_input = _buffer_input
	_buffer_overlay = Control.new(); _buffer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(_buffer_overlay)
	_buffer_overlay.draw.connect(func(): input_buffer.draw(_buffer_overlay,board,player.input_views()))
	input_buffer.queued.connect(func():
		_notice = "Swap buffered · will try next opportunity"
		telemetry.append({"kind":"buffer_queued","us":Time.get_ticks_usec()})
		_refresh())
	board.delivery_failed.connect(func(message: String): _fail(message))
	player = MergePlayer.new(board); player.reduced_motion = reduced_motion
	player.motion_finished.connect(_motion_done)
	board.external_layout = func():
		if player.motion_busy and session != null:
			session.clock.assisted = true
			session.clock_notes.append({"kind":"assist","reason":"resize","window":session.window_id,"tick":session.clock.tick})
		player.relayout()
	restart.call_deferred()

func _button(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = label; button.custom_minimum_size.y = 40
	button.pressed.connect(callback); parent.add_child(button); return button

func _show_collection() -> void:
	if session == null: return
	if session.phase == "merge_window": clock_adapter.pause(true,"manual")
	input_buffer.clear()
	var dialog := AcceptDialog.new(); dialog.title = "Collection and expedition rewards"
	var preview := P3Content.preview("aquamarine",session.state.settings)
	var lines := "Current ladder → Aquamarine replacement\n"
	for item in preview.ladder:
		lines += "T%d  %s (%s) → %s (%s)\n" % [item.tier,item.before.id,", ".join(item.before.family_tags),item.after.id,", ".join(item.after.family_tags)]
	for reward in ["aquamarine","steady_hand","beryl_bridge","next_room_craft"]:
		lines += "\n"+P3Content.preview(reward,session.state.settings).description+"\n"
	dialog.dialog_text = lines; add_child(dialog); dialog.popup_centered(Vector2i(850,570))
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free)

func restart() -> void:
	_epoch += 1; var epoch := _epoch
	begun = false; error = ""; queue.clear(); _window_handoff = false; _motion_deadline = 0; _waiting_since = 0
	_tool = ""; board.target_mode = false; board.set_input_gate("merge",true)
	_notice = ""; board.set_targets([])
	input_buffer.clear()
	if executor != null and not executor.shutdown(): _fail("Worker shutdown timed out"); return
	player.cancel(); audio.cancel()
	_reported_terminal = false
	_committed_terminal = false
	session = MergeSession.new()
	var initial := initial_override
	if external_session != null: initial = external_session.initial
	if initial.is_empty():
		if p3_mode:
			var opened := P3Content.room(seed_value)
			if not opened.ok: _fail(opened.code); return
			initial = opened.state.to_dict()
		else:
			var game := RunController.new()
			if not game.start_room(null,seed_value): _fail(game.last_error); return
			game.apply_action(RoomCommand.begin(0)); initial = game.run_state.to_dict()
	if not session.start(initial): _fail("Room state could not be admitted"); return
	if external_session != null: session = external_session
	executor = MergeExecutor.new(session); clock_adapter = MergeClock.new(session); clock_adapter.automatic = automatic_clock
	if practice_mode: clock_adapter.automatic = false
	board.visible = false; _refresh()
	# Loading is owned by the persistent service, not a suspended room method
	# that can be abandoned by immediate restart/navigation.
	var roster := session.state.catalog.roster()
	get_node("/root/GemForge").request_required(roster,_assets_loaded.bind(epoch))

func _assets_loaded(loaded: bool, epoch: int) -> void:
	if epoch != _epoch or not is_inside_tree(): return
	if not loaded or not audio.last_error.is_empty(): _fail("Required room presentation could not load"); return
	player.reset(session.state.board); board.visible = true; _begin.show(); _refresh()
	board.outlet_cells = session.state.room.definition.data.get("outlets",[])
	board.outlet_tier = session.state.room.definition.data.get("minimum_tier",0)
	if external_session != null:
		begun = true; _begin.hide()
		board.grab_focus()
		if not session.reservation.is_empty():
			var command := RoomCommand.parse(session.reservation.command)
			_motion_deadline = Time.get_ticks_usec()+150000
			if command.data.kind == "swap": player.begin_swap(command)
			executor.resume_reserved()
		elif session.phase == "gravity": executor.continue_gravity()
		_refresh()
	presentation_ready.emit()

func request_swap(a: Vector2i, b: Vector2i) -> void:
	var received := Time.get_ticks_usec()
	if not can_input(): return
	input_buffer.clear()
	clock_adapter.advance(received)
	var command := RoomCommand.exchange(session.state,a,b)
	var result := executor.submit(command,received)
	if not result.ok:
		_notice = "Swap unavailable"; audio.play("ui_reject")
		telemetry.append({"kind":"rejected","code":result.code,"us":received})
		_record_main(Time.get_ticks_usec()-received); return
	board.set_input_gate("merge",true); _waiting_since = 0
	_notice = ""
	_motion_deadline = received+150000
	player.begin_swap(command)
	telemetry.append({"kind":"input","received_us":received,"feedback_us":Time.get_ticks_usec(),"deadline_us":_motion_deadline})
	_refresh()
	_record_main(Time.get_ticks_usec()-received)

func restore_session(value: Dictionary) -> bool:
	var admitted := MergeReplay.restored(value)
	if not admitted.ok: return false
	if executor != null and not executor.shutdown(): return false
	_epoch += 1; queue.clear(); _window_handoff = false; _motion_deadline = 0; _waiting_since = 0
	input_buffer.clear(); _notice = ""; board.set_targets([])
	session = admitted.session; clock_adapter = MergeClock.new(session); clock_adapter.automatic = automatic_clock
	if practice_mode: clock_adapter.automatic = false
	executor = MergeExecutor.new(session); player.reset(session.state.board)
	_tool = ""; board.target_mode = false; error = ""; begun = true; _begin.hide()
	if not session.reservation.is_empty():
		var command := RoomCommand.parse(session.reservation.command)
		_motion_deadline = Time.get_ticks_usec()+150000
		if command.data.kind == "swap": player.begin_swap(command)
		executor.resume_reserved()
	elif session.phase == "gravity": executor.continue_gravity()
	_refresh()
	return true

func _tool_reason(kind: String) -> String:
	if not can_input() or session.phase != "ready": return "Tools are available when the board settles"
	if not session.state.room.tool_available: return "Make a matching swap before another tool"
	var cost := RoomActionLegality.effective_cost(kind,session.state)
	if session.state.room.craft < cost: return "Need %d Craft" % cost
	return ""

func _select_tool(kind: String) -> void:
	if _tool == kind: _cancel_selection(); return
	var reason := _tool_reason(kind)
	_cancel_selection()
	if not reason.is_empty(): _notice = reason; audio.play("ui_reject"); _refresh(); return
	_tool = kind; board.target_mode = true; board.grab_focus(); _refresh()

func _cancel_selection() -> void:
	input_buffer.clear()
	_tool = ""; _tool_origin = Vector2i(-1,-1); board.target_mode = false
	board._deselect(); board.set_targets([]); _notice = ""; _refresh()

func _target(pos: Vector2i) -> void:
	var began := Time.get_ticks_usec()
	if not can_input() or _tool.is_empty() or session.phase != "ready": return
	var command: RoomCommand
	if _tool == "action.exchange":
		if _tool_origin == Vector2i(-1,-1): _tool_origin = pos; board.set_targets([pos]); return
		command = RoomCommand.exchange(session.state,_tool_origin,pos,true)
	else:
		var layer := "obstacle" if not session.state.board.obstacle_at(pos).is_empty() else ("lock" if not session.state.board.get_cell(pos).lock.is_empty() else "gem")
		command = RoomCommand.target(session.state,_tool,pos,layer)
	var accepted := executor.submit(command,began)
	_cancel_selection()
	if accepted.ok:
		audio.play("ui_accept")
		_tool = ""; board.target_mode = false; board.set_input_gate("merge",true)
		# Tool feedback receives the same fixed calculation interval as a swap.
		_motion_deadline = began+150000
	else: _notice = "Tool unavailable — choose another target or make a swap"; audio.play("ui_reject")
	_refresh()
	_record_main(Time.get_ticks_usec()-began)

func can_input() -> bool:
	return begun and application_focused and error.is_empty() and session != null and session.phase in ["ready","merge_window"] and session.reservation.is_empty() and queue.is_empty() and not player.motion_busy and not _window_handoff and not session.clock.paused and (session.phase == "ready" or (session.clock.started and session.clock.tick < 20))

func can_buffer() -> bool:
	return begun and application_focused and error.is_empty() and session != null and session.phase not in ["complete","failed","diagnostic"] and not session.clock.paused and _tool.is_empty() and (player.motion_busy or _motion_deadline > 0 or _window_handoff)

func _buffer_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_selection(); board.accept_event(); return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_selection(); board.accept_event(); return true
	if not can_buffer(): return false
	input_buffer.handle(event,board,player.input_views()); _buffer_overlay.queue_redraw()
	return true

func _consume_buffer() -> void:
	if not can_input(): return
	var buffered := input_buffer.take(session.state.board)
	if buffered.is_empty(): return
	if not buffered.ok:
		_notice = "Buffered swap cancelled — a selected gem disappeared"
		audio.play("ui_reject"); telemetry.append({"kind":"buffer_cancelled","code":buffered.code}); return
	var command := RoomCommand.exchange(session.state,buffered.origin,buffered.destination)
	var legal := session.quote(command)
	if not legal.ok:
		_notice = "Buffered swap cancelled — no longer a legal move"
		audio.play("ui_reject"); telemetry.append({"kind":"buffer_cancelled","code":legal.code}); return
	telemetry.append({"kind":"buffer_admitted","queued_us":buffered.intent.queued_us,"us":Time.get_ticks_usec(),"window":session.window_id})
	request_swap(buffered.origin,buffered.destination)

func _process(delta: float) -> void:
	if session == null or executor == null or not begun or not error.is_empty(): return
	var began := Time.get_ticks_usec(); frame_us.append(int(delta*1000000))
	clock_adapter.advance(began)
	if session.clock.paused or session.phase in ["complete","failed","diagnostic"]:
		if not input_buffer.pending.is_empty(): _notice = "Buffered swap cancelled"
		input_buffer.clear()
	var result := executor.poll()
	if not result.is_empty():
		if not result.ok: _fail(result.code); return
		if result.status == "committed":
			# A long frame can cross the deadline and receive the completion in
			# one poll. Record that miss even without an intervening empty queue.
			if _motion_deadline > 0 and Time.get_ticks_usec() > _motion_deadline:
				_starved("gravity" if executor.metrics.back().kind == "gravity" else "command",began)
			if queue.size() >= 2: _fail("Presentation queue overflow"); return
			queue.append(result.batch)
			telemetry.append({"kind":"candidate_ready","us":Time.get_ticks_usec(),"batch":result.batch.batch_id,"deadline_us":_motion_deadline})
	if session.phase == "merge_window" and session.clock.started and session.clock.tick >= 20 and session.reservation.is_empty() and not player.motion_busy and not _window_handoff:
		board.set_input_gate("merge",true)
		result = executor.release_window()
		if result.ok: queue.append(result.batch); _waiting_since = 0
		elif result.get("status") != "waiting": _fail(result.code); return
		else: _starved("default",began)
	if external_session != null and session.phase in ["complete","failed"] and not _committed_terminal:
		_committed_terminal = true; outcome_committed.emit()
	if not queue.is_empty() and not player.motion_busy and Time.get_ticks_usec() >= _motion_deadline:
		var batch: Dictionary = queue.pop_front(); _motion_deadline = 0; _waiting_since = 0
		_present(batch)
	elif queue.is_empty() and _motion_deadline > 0 and began >= _motion_deadline:
		if not session.reservation.is_empty(): _starved("command",began)
		elif session.phase == "gravity" and executor.busy(): _starved("gravity",began)
	_consume_buffer()
	if session.phase == "merge_window": executor.prepare_default()
	_refresh()
	telemetry.append({"kind":"main_frame","us":Time.get_ticks_usec()-began})
	_record_main(Time.get_ticks_usec()-began)
	if external_session != null and session.phase in ["complete","failed"] and queue.is_empty() and not player.motion_busy and not _reported_terminal:
		_reported_terminal = true; room_finished.emit()

func _record_main(us: int) -> void:
	var frame := Engine.get_process_frames()
	main_frame_us[frame] = main_frame_us.get(frame,0)+us
	# Diagnostics are bounded in an ordinary long-running room. Probes drain them.
	if main_frame_us.size() > 4096: main_frame_us.erase(main_frame_us.keys()[0])
	if telemetry.size() > 8192: telemetry = telemetry.slice(4096)
	if frame_us.size() > 8192: frame_us = frame_us.slice(4096)

func _starved(kind: String, now: int) -> void:
	if _waiting_since != 0: return
	_waiting_since = now; starvation += 1
	telemetry.append({"kind":"starvation","phase":kind,"us":now})

func _present(batch: Dictionary) -> void:
	var presented_us := Time.get_ticks_usec()
	presented_batches.append({"batch":batch.batch_id,"kind":batch.kind,"us":presented_us,
		"expiry_us":_window_deadline if batch.command.is_empty() and not executor.metrics.is_empty() and executor.metrics.back().kind == "default" else 0})
	if presented_batches.size() > 1024: presented_batches.pop_front()
	board.set_input_gate("merge",true)
	if batch.kind == "merge":
		player.show_merge(batch)
		if session.phase == "merge_window": _start_window()
	elif batch.kind == "gravity":
		_motion_deadline = presented_us+int(player.gravity_seconds(batch)*1000000)
		player.play_gravity(batch)
		executor.continue_gravity(presented_us)
	else:
		player.reset(batch.after); _refresh()
	# Ordinary gravity uses ActionPlayer, which already owns its fact cues.
	# Reduced gravity is only a fade, so the streaming owner supplies those cues.
	if batch.kind != "gravity" or reduced_motion: player.present_fact_cues(batch.facts)
	for fact in batch.facts:
		if fact.type == "tile_extracted":
			_notice = "Delivered T%d gem through an outlet" % fact.tier
			audio.play("ui_accept")
		if fact.type == "room_result":
			board.presentation_cue.emit("room_success" if fact.phase == "complete" else "room_failure")
			break

func _start_window() -> void:
	_window_handoff = true; var epoch := _epoch
	if DisplayServer.get_name() == "headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	if epoch != _epoch or not is_inside_tree(): return
	var began := Time.get_ticks_usec()
	clock_adapter.presented(Time.get_ticks_usec()); _window_handoff = false
	_window_deadline = Time.get_ticks_usec()+333334
	if practice_mode:
		session.clock.assisted = true
		session.clock_notes.append({"kind":"assist","reason":"practice","window":session.window_id,"tick":0})
	if not application_focused: clock_adapter.pause(true,"focus")
	telemetry.append({"kind":"window_presented","window":session.window_id,"us":Time.get_ticks_usec()})
	_consume_buffer()
	_refresh()
	_record_main(Time.get_ticks_usec()-began)

func _motion_done() -> void: pass

func _refresh() -> void:
	if _status == null: return
	if not error.is_empty(): _status.text = error; return
	if session == null or not board.visible: _status.text = "Loading gems…"; return
	_title.text = str(session.state.room.definition.data.id).capitalize()
	_instructions.text = "Swap adjacent gems to match. Each swap costs 1 Work. During every merge, swap anywhere to redirect the next match. Tools are available once the board settles.\n\nMouse: click or drag. Keyboard: arrows and Enter; Esc cancels."
	var objective := "Marked rubble" if session.state.room.definition.data.objective == "clear_marked_rubble" else "Deliveries remaining (T%d+)" % session.state.room.definition.data.minimum_tier
	_status.text = "Work %d   Craft %d\n%s: %d\n%s" % [session.state.moves_remaining,session.state.room.craft,objective,session.state.room.remaining(session.state.board),
		"Merge — swap now" if can_input() and session.phase == "merge_window" else session.phase.capitalize()]
	_window_bar.visible = session.phase == "merge_window" and session.clock.started and not player.motion_busy
	_window_bar.value = 20-session.clock.tick
	if session.clock.paused: _status.text += "\nPaused — assisted attempt"
	elif practice_mode:
		_status.text += "\nPractice — no deadline. Use Pass window to continue."
		if not p3_mode: _status.text += "\n\nFirst swap: row 4, column 4 left. Then move the upgraded gem left again. Restart and pass the first window to compare."
	if not _tool.is_empty(): _status.text += "\nChoose a tool target · Esc or Cancel to return to swaps"
	if not _notice.is_empty(): _status.text += "\n"+_notice
	if session.state.rules.is_p3():
		_status.text += "\n\nQuartz T1–2: +1 Craft once per paid move.\nCorundum %s: 2 rubble damage.\nBeryl %s: promotes the lowest adjacent T1–%d once per paid move.\nTools suppress families and Craft." % ["T7" if "aquamarine" in session.state.settings else "T5/7","T5/6" if "aquamarine" in session.state.settings else "T6",4 if "beryl_bridge" in session.state.settings else 3]
		if session.state.room.definition.data.objective == "extract": _status.text += "\n\nCyan outlets collect unlocked qualifying gems after all merges and falling settle. Each gem fills one delivery."
	_cancel_button.disabled = _tool.is_empty() and input_buffer.pending.is_empty() and input_buffer.selected_id.is_empty()
	if _buffer_overlay != null: _buffer_overlay.queue_redraw()
	board.set_input_gate("merge",not can_input())
	for button in _tool_buttons:
		var kind: String = button.get_meta("kind")
		button.text = "%s · %d Craft" % [{"action.exchange":"Reposition","action.clear_target":"Chisel","action.promote_target":"Refine"}[kind],RoomActionLegality.effective_cost(kind,session.state)]
		var reason := _tool_reason(button.get_meta("kind"))
		button.disabled = not reason.is_empty(); button.tooltip_text = reason

func _fail(message: String) -> void:
	input_buffer.clear()
	error = message; begun = false
	if executor != null: executor.cancel()
	if player != null and session != null: player.reset(session.state.board)
	if board != null: board.set_input_gate("merge",true)
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		input_buffer.clear(); _notice = ""
		application_focused = false
		if clock_adapter != null: clock_adapter.pause(true,"focus")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: application_focused = true

func _exit_tree() -> void:
	_epoch += 1
	if executor != null: executor.shutdown()
	if player != null: player.cancel()
