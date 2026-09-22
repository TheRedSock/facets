class_name ExpeditionView
extends Control
signal back_requested
var run: ExpeditionState
var seed_value := 7
var room_view: MergeRoomView
var selected: Array = []
var panel: VBoxContainer
var error := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://assets/ui/themes/workshop.tres")
	if run == null:
		var result := ExpeditionState.create(seed_value)
		if not result.ok: error = result.code
		else: run = result.run
	show_phase()

func button(label: String, callback: Callable) -> Button:
	var control := Button.new(); control.text = label; control.custom_minimum_size.y = 42
	control.pressed.connect(callback); panel.add_child(control)
	return control

func label(text: String) -> void:
	var control := Label.new(); control.text = text; control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(control)

func show_phase() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	room_view = null
	if run != null and run.phase == "playing":
		room_view = MergeRoomView.new(); room_view.p3_mode = true; room_view.external_session = run.session
		room_view.back_requested.connect(func(): back_requested.emit(); queue_free())
		room_view.restart_requested.connect(restart)
		room_view.room_finished.connect(func():
			var result := run.finish_room()
			if not result.ok: error = result.code
			show_phase.call_deferred())
		add_child(room_view); return
	var background := ColorRect.new(); background.color = Color("141a22"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,36)
	add_child(margin)
	var scroll := ScrollContainer.new(); margin.add_child(scroll)
	panel = VBoxContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(panel)
	label("FACETS · Expedition")
	button("Menu",func(): back_requested.emit(); queue_free())
	if not error.is_empty(): label(error); button("Restart expedition",restart); return
	label("Room %d · %s" % [run.room_index+1,run.current().room.definition.data.id.capitalize()])
	match run.phase:
		"briefing":
			label("%d Work · %d Craft\nClear marked rubble. Carry up to two T4+ gems after completion.\nStaging: row 1, columns 4 and 5, in your selected order." % [run.state.moves_remaining,run.state.room.craft])
			button("Begin room",func():
				var result := run.begin(run.revision())
				if not result.ok: error = result.code
				show_phase())
		"carry_selection":
			selected = []
			label("Choose up to two remaining T4+ gems in staging order. Choosing none is allowed.")
			for tile in run.eligible_carry():
				var control := CheckButton.new(); control.text = "T%d %s · %s" % [tile.tier,tile.tile_id,tile.instance_id]
				control.toggled.connect(func(on: bool):
					if on:
						if selected.size() >= 2: control.set_pressed_no_signal(false)
						else: selected.append(tile.instance_id)
					else: selected.erase(tile.instance_id))
				panel.add_child(control)
			button("Confirm carry",func():
				var result := run.confirm_carry(selected,run.revision())
				if not result.ok: error = result.code
				show_phase())
		"reward_selection": label("Carry confirmed. Reward and route flow is the next implementation batch.")
		"results":
			label("Expedition complete" if run.state.phase == "complete" else "Expedition ended · "+run.state.room.failure_reason)
			button("Restart expedition",restart)
	var first := panel.find_children("*","Button",true,false)
	if not first.is_empty(): first[0].grab_focus()

func restart() -> void:
	var result := ExpeditionState.create(seed_value)
	if result.ok: run = result.run; error = ""
	else: error = result.code
	show_phase.call_deferred()
