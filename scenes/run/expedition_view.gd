class_name ExpeditionView
extends Control
signal back_requested
var run: ExpeditionState
var seed_value := 7
var room_view: MergeRoomView
var selected: Array = []
var panel: VBoxContainer
var error := ""
var _generation := 0
var _loading := false
var store := ExpeditionSave.new()
var retained_room: MergeRoomView
var diagnostic_practice := false
var preview_pending := false

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
	_generation += 1; _loading = false; preview_pending = false
	# Retain actual old board views through choice/preflight/new-board load.
	if is_instance_valid(room_view):
		if is_instance_valid(retained_room): retained_room.queue_free()
		retained_room = room_view; retained_room.hide(); retained_room.set_process(false)
	for child in get_children():
		if child == retained_room: continue
		remove_child(child); child.queue_free()
	room_view = null
	if run != null and run.phase == "playing":
		room_view = MergeRoomView.new(); room_view.p3_mode = true; room_view.external_session = run.session
		room_view.practice_mode = diagnostic_practice
		room_view.back_requested.connect(func(): back_requested.emit(); queue_free())
		room_view.restart_requested.connect(restart)
		room_view.save_requested.connect(save_run)
		room_view.continue_requested.connect(continue_run)
		room_view.presentation_ready.connect(func():
			if is_instance_valid(retained_room): retained_room.queue_free()
			retained_room = null)
		room_view.outcome_committed.connect(func():
			var result := run.finish_room()
			if not result.ok: error = result.code)
		room_view.room_finished.connect(func(): show_phase.call_deferred())
		add_child(room_view); return
	var background := ColorRect.new(); background.color = Color("141a22"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,36)
	add_child(margin)
	var scroll := ScrollContainer.new(); scroll.follow_focus = true; margin.add_child(scroll)
	panel = VBoxContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(panel)
	label("FACETS · Expedition")
	button("Menu",func(): back_requested.emit(); queue_free())
	if run != null: button("Save expedition",save_run)
	button("Continue saved expedition",continue_run)
	if not error.is_empty(): label(error)
	if run == null: button("Restart expedition",restart); return
	label("Room %d · %s" % [run.room_index+1,run.current().room.definition.data.id.capitalize()])
	if run.phase in ["briefing","carry_selection","reward_selection","next_room_ready"]:
		var tiles: Array = []
		var catalog := run.current().catalog
		for tier in range(1,9): tiles.append({"id":catalog.definition(tier).id,"tier":tier})
		label("Current collection · tiers 1–8")
		if run.phase == "reward_selection" and "aquamarine" in run.offers:
			label("The extra T5 at right previews the offered Aquamarine replacement.")
			tiles.append({"id":"aquamarine","tier":5})
		preview_tiles(tiles)
	match run.phase:
		"briefing":
			label("%d Work · %d Craft\n%s\nStaging: row 1, columns 4 and 5, in your selected order." % [run.state.moves_remaining,run.state.room.craft,objective_text(run.state.room.definition.data)])
			button("Begin room",func():
				var result := run.begin(run.revision())
				if not result.ok: error = result.code
				show_phase())
		"carry_selection":
			selected = []
			label("Choose up to two remaining T4+ gems in staging order. Choosing none is allowed.")
			var cells := {}
			for cell in run.state.board.all_cells():
				var gem := run.state.board.get_tile(cell)
				if gem != null: cells[gem.instance_id] = cell
			for tile in run.eligible_carry():
				var cell: Vector2i = cells[tile.instance_id]
				var control := CheckButton.new(); control.text = "T%d %s · row %d, column %d" % [tile.tier,str(tile.tile_id).capitalize(),cell.y+1,cell.x+1]
				control.set_meta("gem_id",tile.instance_id)
				control.set_meta("label",control.text)
				control.toggled.connect(func(on: bool):
					if on:
						if selected.size() >= 2: control.set_pressed_no_signal(false)
						else: selected.append(tile.instance_id)
					else: selected.erase(tile.instance_id)
					for choice in panel.find_children("*","CheckButton",true,false):
						var slot := selected.find(choice.get_meta("gem_id"))
						choice.text = choice.get_meta("label")+(" → staging %d" % [slot+1] if slot >= 0 else ""))
				panel.add_child(control)
			button("Confirm carry",func():
				var result := run.confirm_carry(selected,run.revision())
				if not result.ok: error = result.code
				show_phase())
		"reward_selection":
			label("Choose one reward. These three offers are fixed for this room.")
			for id in run.offers:
				var preview := P3Content.preview(id,run.state.settings,run.carry)
				label(preview.description)
				if id == "aquamarine":
					var text := ""
					for item in preview.ladder: text += "T%d %s → %s   " % [item.tier,item.before.id,item.after.id]
					label(text)
					for index in preview.carry.size():
						var converted: Dictionary = preview.carry[index]
						label("Carry slot %d: T%d %s → %s" % [index+1,converted.before.tier,converted.before.tile_id,converted.after.tile_id])
				button("Choose "+str(id).capitalize(),choose_reward.bind(id))
		"route_selection":
			label("Choose the second room")
			for id in run.route_cards:
				var spec: Dictionary = P3Rooms.SPECS[id]
				label("%s · %d Work · %d rubble\n%s" % [str(id).capitalize(),spec.work,spec.rubble.size(),objective_text(spec)])
				button("Take "+str(id).capitalize(),func():
					var result := run.choose_route(id,run.revision())
					if not result.ok: error = result.code
					show_phase())
		"next_room_ready":
			label("Carry keeps its IDs and tiers. Entry Craft: %d. The next room is prepared before this run changes." % mini(6,clampi(run.state.room.craft,1,3)+run.entry_bonus))
			button("Enter next room",enter_next)
		"results":
			label("Expedition complete" if run.state.phase == "complete" else "Expedition ended · "+run.state.room.failure_reason)
			if run.state.room.deliveries.any(func(d: Dictionary) -> bool: return d.tier >= 6): label("Distinction · delivered a T6+ gem")
			button("Restart expedition",restart)
	var first := panel.find_children("*","Button",true,false)
	if not first.is_empty(): first[0].grab_focus()

func preview_tiles(tiles: Array) -> void:
	var row := HFlowContainer.new(); panel.add_child(row)
	var row_reference: WeakRef = weakref(row); preview_pending = true
	var generation := _generation
	var ids := tiles.map(func(tile: Dictionary) -> StringName: return StringName(tile.id))
	get_node("/root/GemForge").request_required(ids,func(ready: bool):
		if not is_inside_tree() or generation != _generation: return
		preview_pending = false
		var holder: HFlowContainer = row_reference.get_ref()
		if holder == null: return
		if not ready:
			label("Gem previews unavailable; choices remain unchanged. Retry by reopening this screen.")
			return
		for tile in tiles:
			var gem := TileView.new(); gem.custom_minimum_size = Vector2(72,72)
			gem.tooltip_text = "T%d %s" % [tile.tier,str(tile.id).capitalize()]
			holder.add_child(gem); gem.set_tier_visible(true); gem.configure_from_data(StringName(tile.id),tile.tier,Vector2i.ZERO))

func objective_text(data: Dictionary) -> String:
	if data.objective == "extract": return "Deliver %d T%d+ gems through the marked bottom outlets. Own-cell obstacles and locks block delivery; adjacent rubble blocks travel." % [data.demand,data.minimum_tier]
	return "Clear all marked two-hit rubble. Match beside it or use Chisel."

func choose_reward(id: String) -> void:
	if _loading: return
	_loading = true; var generation := _generation; var revision := run.revision()
	var settings := run.state.settings.duplicate()
	if id != "next_room_craft": settings.append(id)
	var catalog: GameCatalog = P3Content.catalog(settings).catalog
	get_node("/root/GemForge").request_required(catalog.roster(),func(ready: bool):
		if not is_inside_tree() or generation != _generation: return
		var result := run.choose_reward(id,revision,ready)
		error = "" if result.ok else "Reward could not load: "+result.code
		show_phase())

func enter_next() -> void:
	if _loading: return
	var prepared := run.prepare_next()
	if not prepared.ok: error = prepared.code; show_phase(); return
	_loading = true; var generation := _generation
	get_node("/root/GemForge").request_required(prepared.candidate.catalog.roster(),func(ready: bool):
		if not is_inside_tree() or generation != _generation: return
		if not run.publish_entry(prepared,ready): error = "Room assets could not load. Choices and carry were retained."
		else: error = ""
		show_phase())

func restart() -> void:
	var result := ExpeditionState.create(seed_value)
	if result.ok: run = result.run; error = ""
	else: error = result.code
	show_phase.call_deferred()

func save_run() -> void:
	if run == null: return
	if room_view != null:
		room_view.input_buffer.clear()
		room_view.clock_adapter.pause(true,"manual")
	var result := store.write_slot(run)
	error = "Expedition saved" if result.ok else "Save failed: "+result.code
	if room_view != null: room_view._notice = error; room_view._refresh()
	else: show_phase()

func continue_run() -> void:
	if _loading: return
	if room_view != null:
		room_view.input_buffer.clear()
		room_view.clock_adapter.pause(true,"manual")
	var result := store.load_slot()
	if not result.ok:
		error = "Continue failed: "+result.code
		if room_view != null: room_view._notice = error; room_view._refresh()
		else: show_phase()
		return
	_loading = true; var generation := _generation
	get_node("/root/GemForge").request_required(result.run.current().catalog.roster(),func(ready: bool):
		if not is_inside_tree() or generation != _generation: return
		_loading = false
		if not ready:
			error = "Continue assets unavailable; current expedition retained."
			if room_view != null: room_view._notice = error; room_view._refresh()
			else: show_phase()
			return
		run = result.run; seed_value = run.seed_value
		error = "Recovered last-known-good save: "+result.get("warning","") if result.recovered else ""
		show_phase())
