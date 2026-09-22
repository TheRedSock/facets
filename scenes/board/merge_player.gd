class_name MergePlayer
extends RefCounted
## Live views are keyed by stable rule IDs; departing ghosts never enter hit maps.
signal motion_finished
var board: BoardScene
var reduced_motion := false
var live := {}
var ghosts := {}
var decorations := {}
var motion_busy := false
var observations: Array = []
var _motion: Tween
var _epoch := 0
var _swap: RoomCommand
var _swap_ends_us := 0
var _gravity_ends_us := 0
var _gravity_after: BoardState

func _init(view: BoardScene) -> void:
	board = view

func reset(snapshot: BoardState) -> void:
	cancel()
	board.snap_to(snapshot)
	_sync_ids(snapshot)

func _sync_ids(snapshot: BoardState) -> void:
	live.clear()
	for pos in snapshot.all_cells():
		var tile := snapshot.get_tile(pos)
		if tile != null and board._tile_views.has(pos): live[tile.instance_id] = board._tile_views[pos]

func _stop_decoration(id: String) -> void:
	var tween: Tween = decorations.get(id)
	if tween != null and tween.is_valid(): tween.kill()
	decorations.erase(id)
	var view: TileView = live.get(id)
	if view != null: view.scale = Vector2.ONE

func begin_swap(command: RoomCommand, seconds: float = 0.15) -> void:
	_swap = command; motion_busy = true; _swap_ends_us = Time.get_ticks_usec()+int(seconds*1000000)
	for id in [command.data.origin_id,command.data.destination_id]: _stop_decoration(id)
	board.presentation_cue.emit("tile_swap")
	observations.append({"kind":"swap_started","us":Time.get_ticks_usec(),"origin_id":command.data.origin_id,"destination_id":command.data.destination_id})
	_swap_motion(seconds)

func _swap_motion(seconds: float) -> void:
	_motion = board.create_tween().set_parallel(true)
	for pair in [[_swap.data.origin_id,_swap.data.destination],[_swap.data.destination_id,_swap.data.origin]]:
		var view: TileView = live.get(pair[0])
		if view != null: _motion.tween_property(view,"position",board._cell_to_pixel(pair[1]),seconds)
	_motion.chain().tween_callback(_finish_swap)

func _finish_swap() -> void:
	if _swap == null: return
	var first: TileView = live.get(_swap.data.origin_id); var second: TileView = live.get(_swap.data.destination_id)
	if first != null and second != null:
		first.cell = _swap.data.destination; second.cell = _swap.data.origin
		board._tile_views[first.cell] = first; board._tile_views[second.cell] = second
	_swap = null; motion_busy = false; motion_finished.emit()

func show_merge(batch: Dictionary) -> void:
	var after: BoardState = batch.after
	var destinations := {}
	for fact in batch.facts:
		if fact.type == "match_committed":
			for source in fact.sources: destinations[source.tile.instance_id] = fact.survivor
	for fact in batch.facts:
		if fact.type != "tile_removed": continue
		var id: String = fact.instance_id
		var view: TileView = live.get(id)
		if view == null: continue
		_stop_decoration(id); live.erase(id); ghosts[id] = view
		var tween := board.create_tween().set_parallel(true)
		decorations[id] = tween
		if not reduced_motion:
			var target: Variant = destinations.get(id)
			if target != null: tween.tween_property(view,"position",board._cell_to_pixel(target),0.18)
			tween.tween_property(view,"scale",Vector2.ONE*0.3,0.18)
		tween.tween_property(view,"modulate:a",0.0,0.18)
		tween.chain().tween_callback(_release_ghost.bind(id))
	board._board_state = after.duplicate_board()
	board._tile_views.clear()
	for pos in after.all_cells():
		var tile := after.get_tile(pos)
		if tile == null: continue
		var view: TileView = live.get(tile.instance_id)
		if view == null:
			view = board._acquire_view(tile.tile_id,tile.tier,pos); live[tile.instance_id] = view
		view.cell = pos; view.position = board._cell_to_pixel(pos)
		board._tile_views[pos] = view
		if view.tier != tile.tier or view.tile_id != tile.tile_id:
			_stop_decoration(tile.instance_id)
			view.show_upgrade_full(tile.tier,tile.tile_id)
			if not reduced_motion:
				view.play_role(&"upgrade"); view.scale = Vector2.ONE*1.15
				var tween := board.create_tween()
				decorations[tile.instance_id] = tween
				tween.tween_property(view,"scale",Vector2.ONE,1.0/3.0)
	if board._overlay != null: board._overlay.queue_redraw()
	observations.append({"kind":"merge_presented","us":Time.get_ticks_usec(),"batch":batch.batch_id,"live":live.size(),"ghosts":ghosts.size()})

func present_fact_cues(facts: Array) -> void:
	# Committed presentation only; never play speculative or rejected effects.
	# Coalesce simultaneous identical cues, preserving the bounded audio pool.
	var mapping := {"match_committed":"match_commit","tile_promoted":"tile_promoted",
		"obstacle_damaged":"obstacle_hit","obstacle_broken":"obstacle_broken"}
	var played := {}
	for fact in facts:
		var cue: String = mapping.get(fact.type,"")
		if not cue.is_empty() and not played.has(cue):
			played[cue] = true; board.presentation_cue.emit(cue)

func _release_ghost(id: String) -> void:
	var view: TileView = ghosts.get(id)
	ghosts.erase(id); decorations.erase(id)
	if view != null: board._release_view(view)

func gravity_seconds(batch: Dictionary) -> float:
	var seconds := 0.0
	for phase in MotionPlan.build(batch):
		if phase.kind == "travel": seconds += phase.motion_seconds + AnimationSequencer.landing_bounce_duration
	return seconds

func play_gravity(batch: Dictionary) -> void:
	motion_busy = true; var epoch := _epoch
	_gravity_after = batch.after
	_gravity_ends_us = Time.get_ticks_usec()+int(gravity_seconds(batch)*1000000)
	observations.append({"kind":"gravity_started","us":Time.get_ticks_usec(),"batch":batch.batch_id})
	# The existing trajectory player retains explicit paths and topology fallback.
	if reduced_motion:
		if board._action_player == null: board._action_player = ActionPlayer.new(board)
		await board._action_player.reduced_gravity(batch,gravity_seconds(batch))
	else: await board.play_committed_action(batch,false)
	if epoch != _epoch or not is_instance_valid(board) or not board.is_inside_tree(): return
	_sync_ids(batch.after)
	_gravity_after = null
	motion_busy = false; motion_finished.emit()

func relayout() -> void:
	if _swap != null:
		if _motion != null and _motion.is_valid(): _motion.kill()
		var remaining := maxf(0.001,float(_swap_ends_us-Time.get_ticks_usec())/1000000.0)
		# Preserve remaining duration, with endpoints recalculated for the new grid.
		for pair in [[_swap.data.origin_id,_swap.data.origin],[_swap.data.destination_id,_swap.data.destination]]:
			var view: TileView = live.get(pair[0])
			if view != null: view.position = board._cell_to_pixel(pair[1])
		_swap_motion(remaining)
	elif motion_busy and _gravity_after != null:
		# Resize is an explicit assisted visual snap. Keep the original deadline,
		# close input and wait out the remaining motion interval on a coherent board.
		_epoch += 1
		board.cancel_action_playback(false); board.snap_to(_gravity_after)
		_sync_ids(_gravity_after)
		_motion = board.create_tween()
		_motion.tween_interval(maxf(0.001,float(_gravity_ends_us-Time.get_ticks_usec())/1000000.0))
		_motion.tween_callback(func(): _gravity_after = null; motion_busy = false; motion_finished.emit())
		observations.append({"kind":"resize_gravity_snap","us":Time.get_ticks_usec()})
	elif not motion_busy:
		board._reposition_all()
	for id in ghosts.keys():
		_stop_decoration(id); _release_ghost(id)

func cancel() -> void:
	_epoch += 1
	if _motion != null and _motion.is_valid(): _motion.kill()
	_motion = null; _gravity_after = null
	for tween: Tween in decorations.values():
		if tween != null and tween.is_valid(): tween.kill()
	decorations.clear()
	for id in ghosts.keys(): _release_ghost(id)
	live.clear(); motion_busy = false; _swap = null
	if is_instance_valid(board): board.cancel_action_playback(false)
