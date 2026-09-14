class_name ActionPlayer
extends RefCounted
signal wake
## Committed-action player. Owns every tween, including landing decoration.
var board: BoardScene
var serial_reference := false
var last_plan: Array = []
var observations: Array = []
var _views_by_id := {}
var epoch := 0
var _tweens: Array[Tween] = []
var _after: BoardState

func _init(view: BoardScene) -> void:
	board = view

func cancel(snap: bool = true) -> void:
	epoch += 1
	for tween in _tweens:
		if tween != null and tween.is_valid(): tween.kill()
	_tweens.clear()
	# Resume suspended callers synchronously before their scene is destroyed.
	wake.emit()
	# Spawned views may not have reached a cell-map milestone when canceled.
	if is_instance_valid(board):
		var mapped := board._tile_views.values()
		for view in _views_by_id.values():
			if is_instance_valid(view) and view not in mapped: board._release_view(view)
	_views_by_id.clear()
	if snap and _after != null and is_instance_valid(board) and board.is_inside_tree(): board.snap_to(_after)
	_after = null

func current(token: int) -> bool:
	return token == epoch and is_instance_valid(board) and board.is_inside_tree()

func _tween() -> Tween:
	var tween := board.create_tween().set_parallel(true)
	_tweens.append(tween)
	return tween

func _wait(tween: Tween, token: int) -> bool:
	var tree := board.get_tree()
	tree.process_frame.connect(_wake)
	while current(token) and tween.is_valid() and tween.is_running(): await wake
	if tree.process_frame.is_connected(_wake): tree.process_frame.disconnect(_wake)
	_tweens.erase(tween)
	return current(token)

func _wake() -> void:
	wake.emit()

func invalid(a: Vector2i, b: Vector2i) -> void:
	cancel(false)
	var token := epoch
	var tween := _tween()
	var count := 0
	for pair in [[a,b],[b,a]]:
		var view: TileView = board._tile_views.get(pair[0])
		if view == null: continue
		count += 1
		tween.tween_property(view,"position",board._cell_to_pixel(pair[0]).lerp(board._cell_to_pixel(pair[1]),0.25),AnimationSequencer.invalid_swap_duration)
	if count == 0: tween.kill(); _tweens.erase(tween); return
	if not await _wait(tween,token): return
	tween = _tween()
	for pos in [a,b]:
		var view: TileView = board._tile_views.get(pos)
		if view != null: tween.tween_property(view,"position",board._cell_to_pixel(pos),AnimationSequencer.invalid_swap_duration)
	await _wait(tween,token)

func play(result: Dictionary, instant: bool = false) -> void:
	if instant or (serial_reference and not result.before.room_board):
		await _play_serial(result,instant)
		return
	cancel(false)
	var token := epoch
	_after = result.after
	observations.clear()
	last_plan = MotionPlan.build(result)
	for pos in result.before.all_cells():
		var tile: TileState = result.before.get_tile(pos)
		if tile != null and board._tile_views.has(pos): _views_by_id[tile.instance_id] = board._tile_views[pos]
	if result.command.has("origin"):
		board.presentation_cue.emit("tile_swap")
		var a: Vector2i = result.command.origin; var b: Vector2i = result.command.destination
		var first: TileView = board._tile_views.get(a); var second: TileView = board._tile_views.get(b)
		if first == null or second == null: cancel(true); return
		var tween := _tween()
		tween.tween_property(first,"position",board._cell_to_pixel(b),AnimationSequencer.swap_duration)
		tween.tween_property(second,"position",board._cell_to_pixel(a),AnimationSequencer.swap_duration)
		if not await _wait(tween,token): return
		board._tile_views[a] = second; board._tile_views[b] = first
		first.cell = b; second.cell = a
	for phase in last_plan:
		if not current(token): return
		if phase.kind == "match":
			await _match(phase.step,token)
			if not current(token): return
			for event in phase.step.get("overlay_events",[]): board.apply_overlay_fact(event)
			await _impact(phase.step.get("overlay_events",[]),token)
			if not current(token): return
			for event in phase.step.get("recovery_events",[]): await _recovery(event,token)
		elif phase.concurrent and not serial_reference: await _travel(phase,token)
		else: await _ordered_travel(phase.steps,token)
	if current(token):
		board.snap_to(_after)
		_after = null
		_views_by_id.clear()

func _match(step: Dictionary, token: int) -> void:
	if not step.match_events.is_empty(): board.presentation_cue.emit("match_commit")
	observations.append({"kind":"match","frame":Engine.get_process_frames()})
	var tween := _tween()
	var targets := {}
	for component in step.match_events:
		for source in component.sources: targets[source.tile.instance_id] = component.survivor
	for event in step.remove_events:
		var view: TileView = _views_by_id.get(event.instance_id)
		if view == null: continue
		if targets.get(event.instance_id) != null: tween.tween_property(view,"position",board._cell_to_pixel(targets[event.instance_id]),AnimationSequencer.removal_duration)
		tween.tween_property(view,"scale",Vector2(0.3,0.3),AnimationSequencer.removal_duration)
		tween.tween_property(view,"modulate:a",0.0,AnimationSequencer.removal_duration)
	if not step.remove_events.is_empty():
		if not await _wait(tween,token): return
	else: tween.kill(); _tweens.erase(tween)
	for event in step.remove_events:
		var view: TileView = _views_by_id.get(event.instance_id)
		if view != null:
			board._tile_views.erase(view.cell); board._release_view(view); _views_by_id.erase(event.instance_id)
	if step.upgrade_events.is_empty(): return
	board.presentation_cue.emit("tile_promoted")
	tween = _tween()
	for event in step.upgrade_events:
		var view: TileView = _views_by_id.get(event.instance_id)
		if view == null: continue
		view.show_upgrade_full(event.new_tier,event.tile_id)
		if not current(token): return
		view.play_role(&"upgrade")
		if not current(token): return
		view.scale = Vector2.ONE * AnimationSequencer.upgrade_scale_factor
		tween.tween_property(view,"scale",Vector2.ONE,AnimationSequencer.upgrade_scale_duration)
	await _wait(tween,token)

func _impact(events: Array, token: int) -> void:
	if events.is_empty(): return
	board.impact_cells.clear()
	for event in events:
		if event.cell not in board.impact_cells: board.impact_cells.append(event.cell)
		if event.type == "obstacle_damaged": board.presentation_cue.emit("obstacle_hit")
		elif event.type == "obstacle_broken": board.presentation_cue.emit("obstacle_broken")
	board.impact_alpha = 1.0
	var tween := _tween(); tween.tween_property(board,"impact_alpha",0.0,0.16)
	if not await _wait(tween,token): return
	board.impact_cells.clear()

func _travel(phase: Dictionary, token: int) -> void:
	var tween := _tween()
	for journey in phase.journeys:
		var view: TileView = _views_by_id.get(journey.instance_id)
		if journey.spawn:
			view = board._acquire_view(StringName(journey.source.tile_id),journey.source.tier,journey.to)
			_views_by_id[journey.instance_id] = view
			if not current(token): board._release_view(view); return
			view.position = board._cell_to_pixel(journey.from)
			view.modulate.a = 0.0
			tween.tween_property(view,"modulate:a",1.0,minf(0.1,journey.duration)).set_delay(journey.start)
		if view == null: continue
		observations.append({"kind":"start","instance_id":journey.instance_id,"frame":Engine.get_process_frames(),"from":journey.from,"to":journey.to})
		tween.tween_property(view,"position",board._cell_to_pixel(journey.to),journey.duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(journey.start)
		tween.tween_callback(_landed.bind(journey.instance_id,token)).set_delay(journey.start+journey.duration)
		var bounce := AnimationSequencer.landing_bounce_duration
		if bounce > 0.0:
			tween.tween_property(view,"scale",Vector2(1.05,0.95),bounce * 0.5).set_delay(journey.start+journey.duration)
			tween.tween_property(view,"scale",Vector2.ONE,bounce * 0.5).set_delay(journey.start+journey.duration + bounce * 0.5)
	if not await _wait(tween,token): return
	# Publish the cell map together, after all moving instances have landed.
	for journey in phase.journeys:
		if not journey.spawn:
			var view: TileView = _views_by_id.get(journey.instance_id)
			if view != null: board._tile_views.erase(view.cell)
	for journey in phase.journeys:
		var view: TileView = _views_by_id.get(journey.instance_id)
		if view != null: view.cell = journey.to; board._tile_views[journey.to] = view

func _landed(instance_id: String, token: int) -> void:
	if current(token): observations.append({"kind":"land","instance_id":instance_id,"frame":Engine.get_process_frames()})

func _recovery(event: Dictionary, token: int) -> void:
	observations.append({"kind":"recovery","frame":Engine.get_process_frames()})
	if not event.recovered: return
	var tween := _tween()
	for item in event.before:
		var view: TileView = _views_by_id.get(item.instance_id)
		if view != null: tween.tween_property(view,"modulate:a",0.0,0.12)
	if not await _wait(tween,token): return
	for item in event.before: board._tile_views.erase(item.cell)
	tween = _tween()
	for item in event.after:
		var view: TileView = _views_by_id.get(item.instance_id)
		if view == null: continue
		view.cell = item.cell; view.position = board._cell_to_pixel(item.cell); board._tile_views[item.cell] = view
		tween.tween_property(view,"modulate:a",1.0,0.16)
	await _wait(tween,token)

func _ordered_travel(steps: Array, token: int) -> void:
	# Custom topology fallback: preserve cell reservations and every path segment.
	# Portals fade at departure and arrival; never fly across unrelated cells.
	for step in steps:
		for event in step.gravity_events:
			var view: TileView = _views_by_id.get(event.instance_id)
			if view == null: continue
			var tween := _tween()
			if event.kind == "portal": tween.tween_property(view,"modulate:a",0.0,0.1)
			else: tween.tween_property(view,"position",board._cell_to_pixel(event.to),AnimationSequencer.fall_duration(1)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			if not await _wait(tween,token): return
			board._tile_views.erase(view.cell); view.cell = event.to; board._tile_views[event.to] = view
			if event.kind == "portal":
				view.position = board._cell_to_pixel(event.to)
				tween = _tween(); tween.tween_property(view,"modulate:a",1.0,0.1)
				if not await _wait(tween,token): return
		if step.spawn_events.is_empty(): continue
		var tween := _tween()
		for event in step.spawn_events:
			var view := board._acquire_view(event.tile_id,event.tier,event.cell)
			_views_by_id[event.instance_id] = view
			if not current(token): board._release_view(view); return
			board._tile_views[event.cell] = view
			# In-place arrival avoids crossing blockers/unsupported authored entries.
			view.position = board._cell_to_pixel(event.cell); view.modulate.a = 0.0
			tween.tween_property(view,"modulate:a",1.0,AnimationSequencer.fall_duration(1))
		if not await _wait(tween,token): return

func _play_serial(result: Dictionary, instant: bool = false) -> void:
	cancel(false)
	var token := epoch
	_after = result.after
	if instant: board.snap_to(_after); _after = null; return
	var a: Vector2i = result.command.origin; var b: Vector2i = result.command.destination
	var view_a: TileView = board._tile_views.get(a); var view_b: TileView = board._tile_views.get(b)
	if view_a == null or view_b == null: board.snap_to(_after); _after = null; return
	var tween := _tween()
	tween.tween_property(view_a,"position",board._cell_to_pixel(b),AnimationSequencer.swap_duration)
	tween.tween_property(view_b,"position",board._cell_to_pixel(a),AnimationSequencer.swap_duration)
	if not await _wait(tween,token): return
	board._tile_views[a] = view_b; board._tile_views[b] = view_a
	view_a.cell = b; view_b.cell = a
	for step in result.timeline.cascade_steps:
		if not current(token): return
		var removals: Array = step.get("remove_events",[])
		var upgrades: Array = step.get("upgrade_events",[])
		if not removals.is_empty():
			var targets := {}
			for component in step.match_events:
				for pos in component.cells: targets[pos] = component.survivor
			tween = _tween()
			for event in removals:
				var view: TileView = board._tile_views.get(event.cell)
				if view == null: continue
				if targets.get(event.cell) != null: tween.tween_property(view,"position",board._cell_to_pixel(targets[event.cell]),AnimationSequencer.removal_duration)
				tween.tween_property(view,"scale",Vector2(0.3,0.3),AnimationSequencer.removal_duration)
				tween.tween_property(view,"modulate:a",0.0,AnimationSequencer.removal_duration)
			if not await _wait(tween,token): return
			for event in removals:
				var view: TileView = board._tile_views.get(event.cell)
				if view != null: board._release_view(view); board._tile_views.erase(event.cell)
		if not upgrades.is_empty():
			tween = _tween()
			for event in upgrades:
				var view: TileView = board._tile_views.get(event.cell)
				if view == null: continue
				view.show_upgrade_full(event.new_tier,event.tile_id)
				if not current(token): return
				view.play_role(&"upgrade")
				if not current(token): return
				view.scale = Vector2.ONE * AnimationSequencer.upgrade_scale_factor
				tween.tween_property(view,"scale",Vector2.ONE,AnimationSequencer.upgrade_scale_duration)
			if not await _wait(tween,token): return
		# Preserve actual segment order, including bends and teleport landings.
		for event in step.get("gravity_events",[]):
			var view: TileView = board._tile_views.get(event.from)
			if view == null: continue
			tween = _tween()
			tween.tween_property(view,"position",board._cell_to_pixel(event.to),AnimationSequencer.fall_duration(1.0))
			if not await _wait(tween,token): return
			board._tile_views.erase(event.from); board._tile_views[event.to] = view; view.cell = event.to
		var spawns: Array = step.get("spawn_events",[])
		if not spawns.is_empty():
			tween = _tween()
			for event in spawns:
				var view := board._acquire_view(event.tile_id,event.tier,event.cell)
				if not current(token): return
				board._tile_views[event.cell] = view
				view.position = board._cell_to_pixel(event.cell - event.direction)
				view.modulate.a = 0.0
				tween.tween_property(view,"position",board._cell_to_pixel(event.cell),AnimationSequencer.fall_duration(1.0))
				tween.tween_property(view,"modulate:a",1.0,AnimationSequencer.fall_duration(1.0))
			if not await _wait(tween,token): return
	if current(token):
		board.snap_to(_after)
		_after = null
