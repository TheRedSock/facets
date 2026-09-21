class_name InterventionView
extends Control
signal back_requested
signal boundary_wake
const MODES := ["Atomic","Paused","400 ms","800 ms"]
const PROFILES := ["","trial-paused-v1","trial-24-v1","trial-48-v1"]
var mode := 1
var reduced_motion := false
var automatic_clock := true
var trial: InterventionTrial
var board: BoardScene
var audio: RoomAudio
var ready_for_start := false
var playing := false
var error := ""
var _initial: RunState
var _generation := 0
var _previous_us := 0
var _elapsed_us := 0
var _boundary_drawn := false
var _status: Label
var _instructions: Label
var _start: Button
var _pass: Button
var _pause: Button
var _options: VBoxContainer
var _mode_select: OptionButton

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://assets/ui/themes/workshop.tres")
	var background := ColorRect.new(); background.color = Color("141a22")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",14); margin.add_child(body)
	var bar := HBoxContainer.new(); bar.add_theme_constant_override("separation",12); body.add_child(bar)
	_button(bar,"Menu",func(): back_requested.emit(); queue_free())
	_button(bar,"Restart",restart)
	_mode_select = OptionButton.new()
	for label in MODES: _mode_select.add_item(label)
	_mode_select.select(mode); bar.add_child(_mode_select)
	_mode_select.item_selected.connect(func(index: int): mode = index; restart())
	var reduced := CheckButton.new(); reduced.text = "Reduced motion"; reduced.button_pressed = reduced_motion
	reduced.toggled.connect(func(value: bool): reduced_motion = value); bar.add_child(reduced)
	_button(bar,"Sound / mute",func(): audio.set_muted(not RoomAudio.muted))
	var split := HBoxContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(split)
	board = load("res://scenes/board/board_scene.tscn").instantiate()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL; board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(400,400); split.add_child(board)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x = 350; panel.add_theme_constant_override("separation",14); split.add_child(panel)
	var title := Label.new(); title.text = "Intervention comparison"; title.add_theme_font_size_override("font_size",26); panel.add_child(title)
	_instructions = _label(panel,"Watch the fixed opening. When a gem glows, swap it with a highlighted neighbor or pass.\n\nExtra swaps cost 1 Work.")
	_status = _label(panel,"Loading gems…")
	_start = _button(panel,"Start opening",start_opening)
	_options = VBoxContainer.new(); panel.add_child(_options)
	_pass = _button(panel,"Pass",func(): _decide(null))
	_pause = _button(panel,"Pause",func(): set_paused(not trial.clock.paused,"manual") if trial != null else null)
	audio = RoomAudio.new(); add_child(audio)
	board.presentation_cue.connect(audio.play)
	board.cell_pressed.connect(_cell_pressed)
	board.target_mode = true
	restart.call_deferred()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 350; label.add_theme_font_size_override("font_size",20); parent.add_child(label); return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size.y = 38
	button.pressed.connect(callback); parent.add_child(button); return button

func restart() -> void:
	_generation += 1; var token := _generation
	boundary_wake.emit()
	ready_for_start = false; playing = false; trial = null; error = ""
	board.cancel_action_playback(false); board.reset_input_gates(); board.set_input_gate("trial",true)
	audio.cancel(); _clear_options(); _initial = InterventionFixture.create()
	board.visible = false; _refresh()
	var prepared: bool = await get_node("/root/GemForge").prepare_required(_initial.catalog.roster())
	if token != _generation or not is_inside_tree(): return
	if not prepared or not audio.last_error.is_empty(): error = audio.last_error if not audio.last_error.is_empty() else get_node("/root/GemForge").last_error; _refresh(); return
	board.set_board_state(_initial.board.duplicate_board()); board.visible = true
	ready_for_start = true; _refresh()

func start_opening() -> void:
	if not ready_for_start or playing: return
	var token := _generation; ready_for_start = false; playing = true; _refresh()
	var command := InterventionFixture.command(_initial)
	var result: Dictionary
	if mode == 0:
		result = ActionTransaction.resolve(_initial,command)
		if not result.ok: error = result.code; playing = false; _refresh(); return
	else:
		trial = InterventionTrial.new()
		if not trial.start(_initial.to_dict(),command.to_dict(),PROFILES[mode]): error = trial.last_error; playing = false; _refresh(); return
		result = trial.presentation_result(_initial.board,0,command.to_dict())
	await board.play_committed_action(result,reduced_motion)
	if token != _generation or not is_inside_tree(): return
	# A window is handed off only after the boundary has been drawn. Headless
	# regression uses a frame boundary; actual release probes exercise the draw.
	result = {}; command = null
	_boundary_drawn = false
	var boundary: Signal = get_tree().process_frame if DisplayServer.get_name() == "headless" else RenderingServer.frame_post_draw
	boundary.connect(_on_boundary_drawn)
	while token == _generation and not _boundary_drawn: await boundary_wake
	if boundary.is_connected(_on_boundary_drawn): boundary.disconnect(_on_boundary_drawn)
	if token != _generation or not is_inside_tree(): return
	playing = false
	if trial != null and trial.phase == "window":
		trial.apply(trial.event("presented")); _previous_us = Time.get_ticks_usec(); _elapsed_us = 0
		_show_options(); board.set_input_gate("trial",false); board.grab_focus()
	_refresh()

func _on_boundary_drawn() -> void:
	_boundary_drawn = true; boundary_wake.emit()

func _show_options() -> void:
	_clear_options()
	var cells: Array[Vector2i] = [trial.offers[0].origin]
	for option in trial.offers:
		cells.append(option.destination)
		_button(_options,"Swap to column %d, row %d · 1 Work" % [option.destination.x+1,option.destination.y+1],func(): _decide(option))
	board.set_targets(cells)

func _clear_options() -> void:
	for child in _options.get_children(): _options.remove_child(child); child.queue_free()
	board.set_targets([])

func _cell_pressed(cell: Vector2i) -> void:
	if trial == null or trial.phase != "window" or playing: return
	for option in trial.offers:
		if option.destination == cell: _decide(option); return

func _decide(command: Variant) -> void:
	if trial == null or trial.phase != "window" or playing: return
	if automatic_clock: _advance_clock(Time.get_ticks_usec())
	if trial.phase == "window" and not playing:
		var tick := int(_elapsed_us*60/1000000) if automatic_clock and int(trial.clock.deadline) == 0 else int(trial.clock.tick)
		apply_event(trial.event("decide",{"command":command,"tick":tick}))

func apply_event(input: Dictionary, injection: String = "") -> void:
	if trial == null or playing: return
	var before := trial.state.board.duplicate_board(); var from_fact := trial.context.facts.size()
	var result := trial.apply(input,injection)
	if not result.ok:
		if result.status == "failed": error = "Continuation failed: "+result.code+". The earlier position is retained. Restart to retry."
		_refresh(); return
	if trial.phase != "stable": _refresh(); return
	var command: Dictionary = input.command if input.get("command") is Dictionary and result.status != "expired" else {}
	var token := _generation; playing = true; board.set_input_gate("trial",true); _clear_options(); _refresh()
	await board.play_committed_action(trial.presentation_result(before,from_fact,command),reduced_motion)
	if token != _generation or not is_inside_tree(): return
	playing = false; _refresh()

func _process(_delta: float) -> void:
	if automatic_clock: _advance_clock(Time.get_ticks_usec())

func _advance_clock(now: int) -> void:
	if trial == null or playing or trial.phase != "window" or not trial.clock.started or trial.clock.paused: return
	var elapsed := now-_previous_us; _previous_us = now
	if elapsed > 100000:
		# Freeze at the last visible tick instead of expiring an unseen window.
		trial.apply(trial.event("pause",{"paused":true,"reason":"render_stall"})); _refresh(); return
	_elapsed_us += maxi(0,elapsed)
	var tick := int(_elapsed_us*60/1000000)
	if int(trial.clock.deadline) > 0 and tick > int(trial.clock.tick): apply_event(trial.event("advance",{"tick":tick}))

func set_paused(paused: bool, reason: String) -> void:
	if trial == null or playing or trial.phase != "window": return
	if not trial.clock.paused and automatic_clock: _advance_clock(Time.get_ticks_usec())
	if trial.phase != "window" or playing: return
	trial.apply(trial.event("pause",{"paused":paused,"reason":reason}))
	_previous_us = Time.get_ticks_usec(); _refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and automatic_clock: set_paused(true,"focus")

func _refresh() -> void:
	if _status == null: return
	_start.disabled = not ready_for_start or playing
	var waiting := trial != null and trial.phase == "window" and not playing and error.is_empty()
	_pass.disabled = not waiting or trial.clock.paused
	_pause.disabled = not waiting
	_pause.text = "Resume (assisted)" if waiting and trial.clock.paused else "Pause"
	for child in _options.get_children(): child.disabled = not waiting or trial.clock.paused
	if not error.is_empty(): _status.text = error; board.set_input_gate("trial",true); return
	if playing: _status.text = "Resolving…"; return
	if ready_for_start: _status.text = MODES[mode]+" · Ready\nStart when you are ready to watch the opening."; return
	if waiting:
		var time_text := "No deadline" if int(trial.clock.deadline) == 0 else "%d ms remaining" % int(ceil((trial.clock.deadline-trial.clock.tick)*1000.0/60.0))
		_status.text = "%s\nWork %d · Craft %d\n%s" % ["Paused · assisted attempt" if trial.clock.paused else "Intervene or pass",trial.state.moves_remaining,trial.state.room.craft,time_text]
	elif trial != null: _status.text = "Settled · Work %d · Craft %d\nExtra swaps: %d\nRestart or choose another mode to compare." % [trial.state.moves_remaining,trial.state.room.craft,trial.interventions]
	else: _status.text = "Atomic opening settled. Choose another mode to compare." if not ready_for_start and board.visible else "Loading gems…"

func _exit_tree() -> void:
	_generation += 1
	boundary_wake.emit()
	if is_instance_valid(board): board.cancel_action_playback(false)
	if is_instance_valid(audio): audio.cancel()
