class_name BoardScene
extends Control

signal cell_pressed(cell: Vector2i)
signal swap_requested(cell_a: Vector2i, cell_b: Vector2i)
signal async_group_finished(group_id: int)
signal delivery_failed(message:String)

@export var tile_view_scene: PackedScene

## Persistent tile view tracking: grid cell -> TileView node.
var _tile_views: Dictionary = {}

## Board dimensions and pixel layout.
var _board_state: BoardState
var _cell_size := Vector2i(80, 80)
var _spacing := 6
var _board_offset := Vector2.ZERO

## Input state for tap-select-tap-swap and click-drag-swap.
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _input_locked: bool = false
var _drag_origin: Vector2i = Vector2i(-1, -1)
var _drag_completed: bool = false

## Grid background for visual framing (custom draw for outline + checkerboard).
var _grid_bg: Control

## The canvas node that holds all tile views.
@onready var tile_canvas: Control = %TileCanvas

## Pool of inactive tile views for reuse — eliminates node creation overhead
## during gameplay (instantiate + add_child + _ready is ~2ms per tile).
var _view_pool: Array[TileView] = []
var _layout_refresh_scheduled := false
var _layout_refresh_needs_rebuild := false
var _async_group_completion_queue: Array[int] = []


func _ready() -> void:
	_grid_bg = Control.new()
	_grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_bg.draw.connect(_draw_board_background)
	add_child(_grid_bg)
	move_child(_grid_bg, 0)

	resized.connect(_on_resized)


func _on_resized() -> void:
	if _board_state != null:
		_schedule_layout_refresh(false)


## Draws the board background: a filled rounded rect, alternating cell shading,
## and a rounded outline border. All coordinates are local to _grid_bg.
func _draw_board_background() -> void:
	if _board_state == null or _grid_bg == null:
		return

	var bg_padding := 10.0
	var bg_rect := Rect2(Vector2.ZERO, _grid_bg.size)

	# Background fill
	var bg_color := Color(0.12, 0.12, 0.16, 1.0)
	_grid_bg.draw_rect(bg_rect, bg_color)

	# Alternating cell shading (checkerboard)
	var cell_dark := Color(0.16, 0.16, 0.20, 1.0)
	var cell_light := Color(0.20, 0.20, 0.25, 1.0)
	var cols := _board_state.size.x
	var rows := _board_state.size.y
	for y in rows:
		for x in cols:
			var cell_pos := Vector2i(x, y)
			if _board_state.is_blocked(cell_pos):
				continue
			var shade := cell_dark if (x + y) % 2 == 0 else cell_light
			var px := bg_padding + x * (_cell_size.x + _spacing)
			var py := bg_padding + y * (_cell_size.y + _spacing)
			_grid_bg.draw_rect(Rect2(px, py, _cell_size.x, _cell_size.y), shade)

	# Outline border
	var outline_color := Color(0.30, 0.30, 0.38, 1.0)
	var outline_width := 2.0
	var inset := outline_width * 0.5
	var outline_rect := Rect2(
		inset, inset,
		_grid_bg.size.x - outline_width,
		_grid_bg.size.y - outline_width)
	_grid_bg.draw_rect(outline_rect, outline_color, false, outline_width)


# ---- Public API ----


func set_board_state(board_state: BoardState) -> void:
	_board_state = board_state
	_schedule_layout_refresh(true)


func _schedule_layout_refresh(needs_rebuild: bool) -> void:
	_layout_refresh_needs_rebuild = _layout_refresh_needs_rebuild or needs_rebuild
	if _layout_refresh_scheduled or not is_inside_tree():
		return
	_layout_refresh_scheduled = true
	get_tree().process_frame.connect(_run_scheduled_layout_refresh, CONNECT_ONE_SHOT)


func _run_scheduled_layout_refresh() -> void:
	_layout_refresh_scheduled = false
	var needs_rebuild := _layout_refresh_needs_rebuild
	_layout_refresh_needs_rebuild = false
	_compute_layout()
	if not is_inside_tree():
		return
	if needs_rebuild:
		_rebuild_all()
	else:
		_reposition_all()


## Animates two tiles swapping positions, then updates internal tracking.
func animate_swap(cell_a: Vector2i, cell_b: Vector2i) -> void:
	var view_a: TileView = _tile_views.get(cell_a)
	var view_b: TileView = _tile_views.get(cell_b)
	if view_a == null and view_b == null:
		return

	var pos_a := _cell_to_pixel(cell_a)
	var pos_b := _cell_to_pixel(cell_b)

	var tween := create_tween().set_parallel(true)
	if view_a != null:
		tween.tween_property(view_a, "position", pos_b, AnimationSequencer.swap_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if view_b != null:
		tween.tween_property(view_b, "position", pos_a, AnimationSequencer.swap_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	# Update tracking to reflect the swapped positions
	_tile_views.erase(cell_a)
	_tile_views.erase(cell_b)
	if view_a != null:
		_tile_views[cell_b] = view_a
		view_a.cell = cell_b
	if view_b != null:
		_tile_views[cell_a] = view_b
		view_b.cell = cell_a


## Animates an invalid swap (tiles slide halfway then bounce back).
func animate_invalid_swap(cell_a: Vector2i, cell_b: Vector2i) -> void:
	var view_a: TileView = _tile_views.get(cell_a)
	var view_b: TileView = _tile_views.get(cell_b)
	if view_a == null and view_b == null:
		return

	var pos_a := _cell_to_pixel(cell_a)
	var pos_b := _cell_to_pixel(cell_b)
	var mid := (pos_a + pos_b) * 0.5
	var quarter_a := (pos_a + mid) * 0.5
	var quarter_b := (pos_b + mid) * 0.5

	# Slide halfway
	var tween := create_tween().set_parallel(true)
	if view_a != null:
		tween.tween_property(view_a, "position", quarter_b, AnimationSequencer.invalid_swap_duration)
	if view_b != null:
		tween.tween_property(view_b, "position", quarter_a, AnimationSequencer.invalid_swap_duration)
	await tween.finished

	# Bounce back
	var tween2 := create_tween().set_parallel(true)
	if view_a != null:
		tween2.tween_property(view_a, "position", pos_a, AnimationSequencer.invalid_swap_duration)
	if view_b != null:
		tween2.tween_property(view_b, "position", pos_b, AnimationSequencer.invalid_swap_duration)
	await tween2.finished


## Plays an EventTimeline produced by the simulation.
func play_timeline(timeline: EventTimeline) -> void:
	if timeline == null or timeline.is_empty():
		return

	for step in timeline.cascade_steps:
		await animate_cascade_step(step)


## Plays a fully precomputed authoritative timeline, overlapping independent
## regions whenever their touched-cell dependencies have already completed.
func play_authoritative_async_timeline(timeline: EventTimeline) -> void:
	if timeline == null or timeline.is_empty():
		return

	var groups := _build_async_timeline_groups(timeline)
	if groups.size() <= 1:
		await play_timeline(timeline)
		return

	_async_group_completion_queue.clear()
	var started: Dictionary = {}
	var completed: Dictionary = {}
	var running := 0

	while completed.size() < groups.size():
		var launched := false
		for group in groups:
			var group_id: int = group.get("id", -1)
			if started.has(group_id):
				continue
			if not _are_async_group_dependencies_complete(group, completed):
				continue
			started[group_id] = true
			running += 1
			launched = true
			call_deferred("_run_authoritative_async_group", group)

		if not _async_group_completion_queue.is_empty():
			while not _async_group_completion_queue.is_empty():
				var finished_group_id: int = _async_group_completion_queue.pop_front()
				if completed.has(finished_group_id):
					continue
				completed[finished_group_id] = true
				running = maxi(0, running - 1)
			continue

		if launched:
			await get_tree().process_frame
			continue

		if running <= 0:
			break
		await async_group_finished


## Animates a single cascade step with its trailing pause.
## Used by direct timeline playback and by async timeline groups.
func animate_cascade_step(step: Dictionary, include_pause: bool = true) -> void:
	await _play_cascade_step(step)
	if include_pause:
		await await_cascade_pause()


func await_cascade_pause() -> void:
	if AnimationSequencer.cascade_pause > 0.0:
		await get_tree().create_timer(AnimationSequencer.cascade_pause).timeout


func _run_authoritative_async_group(group: Dictionary) -> void:
	var group_id: int = group.get("id", -1)
	await _play_cascade_step(group, "async_%d_" % group_id)
	_async_group_completion_queue.append(group_id)
	async_group_finished.emit(group_id)


func _build_async_timeline_groups(timeline: EventTimeline) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var prior_groups: Array[Dictionary] = []
	var next_group_id := 0

	for step in timeline.cascade_steps:
		var step_groups := _split_step_into_async_groups(step, next_group_id)
		next_group_id += step_groups.size()
		for group in step_groups:
			group["dependencies"] = _collect_async_group_dependencies(group, prior_groups)
		groups.append_array(step_groups)
		prior_groups.append_array(step_groups)

	return groups


func _split_step_into_async_groups(step: Dictionary, starting_group_id: int) -> Array[Dictionary]:
	var components := _build_async_step_components(step)
	if components.is_empty():
		return []

	var chain_steps: Array = step.get("chain_steps", [])
	if chain_steps.is_empty():
		chain_steps = [{
			"match_events": step.get("match_events", []),
			"remove_events": step.get("remove_events", []),
			"upgrade_events": step.get("upgrade_events", []),
		}]

	var groups: Array[Dictionary] = []
	for component_index in components.size():
		var touched_cells: Array[Vector2i] = components[component_index]
		var group_chain_steps: Array[Dictionary] = []
		for round_data in chain_steps:
			var round_matches := _filter_match_events_by_cells(
				round_data.get("match_events", []), touched_cells)
			var round_removes := _filter_cell_events_by_cells(
				round_data.get("remove_events", []), touched_cells)
			var round_upgrades := _filter_cell_events_by_cells(
				round_data.get("upgrade_events", []), touched_cells)
			if round_matches.is_empty() and round_removes.is_empty() and round_upgrades.is_empty():
				continue
			group_chain_steps.append({
				"match_events": round_matches,
				"remove_events": round_removes,
				"upgrade_events": round_upgrades,
			})

		groups.append({
			"id": starting_group_id + component_index,
			"cascade_index": step.get("cascade_index", 0),
			"chain_steps": group_chain_steps,
			"match_events": _flatten_round_events(group_chain_steps, "match_events"),
			"remove_events": _flatten_round_events(group_chain_steps, "remove_events"),
			"upgrade_events": _flatten_round_events(group_chain_steps, "upgrade_events"),
			"gravity_events": _filter_move_events_by_cells(step.get("gravity_events", []), touched_cells),
			"spawn_events": _filter_cell_events_by_cells(step.get("spawn_events", []), touched_cells),
			"board_hash": step.get("board_hash", -1),
			"touched_cells": touched_cells,
			"dependencies": [],
		})

	return groups


func _build_async_step_components(step: Dictionary) -> Array:
	var packets: Array = []
	var chain_steps: Array = step.get("chain_steps", [])
	if chain_steps.is_empty():
		chain_steps = [{
			"match_events": step.get("match_events", []),
			"remove_events": step.get("remove_events", []),
			"upgrade_events": step.get("upgrade_events", []),
		}]

	for round_data in chain_steps:
		packets.append_array(_build_round_async_packets(round_data))

	for event in step.get("gravity_events", []):
		var move_cells := _collect_unique_cells([
			event.get("from", Vector2i(-1, -1)),
			event.get("to", Vector2i(-1, -1)),
		])
		if not move_cells.is_empty():
			packets.append(move_cells)

	for event in step.get("spawn_events", []):
		var spawn_cells := _collect_unique_cells([event.get("cell", Vector2i(-1, -1))])
		if not spawn_cells.is_empty():
			packets.append(spawn_cells)

	return _merge_async_packets_into_components(packets)


func _build_round_async_packets(round_data: Dictionary) -> Array:
	var packets: Array = []
	var remove_events: Array = round_data.get("remove_events", [])
	var upgrade_events: Array = round_data.get("upgrade_events", [])
	var claimed_removes: Dictionary = {}
	var claimed_upgrades: Dictionary = {}

	for match_event in round_data.get("match_events", []):
		var packet_cells := _collect_unique_cells(match_event.get("cells", []))
		for event in remove_events:
			var remove_cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			if remove_cell in packet_cells:
				claimed_removes[remove_cell] = true
		for event in upgrade_events:
			var upgrade_cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			if upgrade_cell in packet_cells:
				claimed_upgrades[upgrade_cell] = true
		if not packet_cells.is_empty():
			packets.append(packet_cells)

	for event in remove_events:
		var remove_cell: Vector2i = event.get("cell", Vector2i(-1, -1))
		if remove_cell != Vector2i(-1, -1) and not claimed_removes.has(remove_cell):
			packets.append([remove_cell])

	for event in upgrade_events:
		var upgrade_cell: Vector2i = event.get("cell", Vector2i(-1, -1))
		if upgrade_cell != Vector2i(-1, -1) and not claimed_upgrades.has(upgrade_cell):
			packets.append([upgrade_cell])

	return packets


func _merge_async_packets_into_components(
	packets: Array
) -> Array:
	var components: Array = []

	for packet_cells in packets:
		var matching_indices: Array[int] = []
		for component_index in components.size():
			if _cells_overlap(packet_cells, components[component_index]):
				matching_indices.append(component_index)

		if matching_indices.is_empty():
			components.append(packet_cells.duplicate())
			continue

		var merged_cells: Array = packet_cells.duplicate()
		for i in range(matching_indices.size() - 1, -1, -1):
			var component_index: int = matching_indices[i]
			merged_cells = _merge_cell_lists(merged_cells, components[component_index])
			components.remove_at(component_index)
		components.append(merged_cells)

	return components


func _collect_async_group_dependencies(
	group: Dictionary,
	prior_groups: Array[Dictionary]
) -> Array[int]:
	var dependencies: Array[int] = []
	var touched_cells: Array[Vector2i] = group.get("touched_cells", [])
	for prior_group in prior_groups:
		if _cells_overlap(touched_cells, prior_group.get("touched_cells", [])):
			dependencies.append(prior_group.get("id", -1))
	return dependencies


func _are_async_group_dependencies_complete(group: Dictionary, completed: Dictionary) -> bool:
	for dependency in group.get("dependencies", []):
		if not completed.has(dependency):
			return false
	return true


func _flatten_round_events(rounds: Array[Dictionary], key: String) -> Array[Dictionary]:
	var flattened: Array[Dictionary] = []
	for round_data in rounds:
		flattened.append_array(round_data.get(key, []))
	return flattened


func _filter_match_events_by_cells(
	match_events: Array,
	touched_cells: Array[Vector2i]
) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for event in match_events:
		for cell in event.get("cells", []):
			if cell in touched_cells:
				filtered.append(event)
				break
	return filtered


func _filter_cell_events_by_cells(
	events: Array,
	touched_cells: Array[Vector2i]
) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for event in events:
		var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
		if cell in touched_cells:
			filtered.append(event)
	return filtered


func _filter_move_events_by_cells(
	move_events: Array,
	touched_cells: Array[Vector2i]
) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for event in move_events:
		var from: Vector2i = event.get("from", Vector2i(-1, -1))
		var to: Vector2i = event.get("to", Vector2i(-1, -1))
		if from in touched_cells or to in touched_cells:
			filtered.append(event)
	return filtered


func _collect_unique_cells(cells: Array) -> Array[Vector2i]:
	var unique_cells: Array[Vector2i] = []
	for cell in cells:
		if cell is Vector2i and cell != Vector2i(-1, -1) and cell not in unique_cells:
			unique_cells.append(cell)
	return unique_cells


func _cells_overlap(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for cell in a:
		if cell in b:
			return true
	return false


func _merge_cell_lists(a: Array[Vector2i], b: Array[Vector2i]) -> Array[Vector2i]:
	var merged := a.duplicate()
	for cell in b:
		if cell not in merged:
			merged.append(cell)
	return merged


# ---- Layout Calculation ----


func _compute_layout() -> void:
	if _board_state == null:
		return

	var available := size
	if available.x <= 0 or available.y <= 0:
		available = get_viewport_rect().size
	var cols := _board_state.size.x
	var rows := _board_state.size.y
	_cell_size = estimate_cell_size(_board_state.size)

	var board_pixel_w := cols * (_cell_size.x + _spacing) - _spacing
	var board_pixel_h := rows * (_cell_size.y + _spacing) - _spacing
	_board_offset = Vector2(
		round((available.x - board_pixel_w) / 2.0),
		round((available.y - board_pixel_h) / 2.0))

	if _grid_bg != null:
		var bg_padding := 10.0
		_grid_bg.position = _board_offset - Vector2(bg_padding, bg_padding)
		_grid_bg.size = Vector2(board_pixel_w + bg_padding * 2, board_pixel_h + bg_padding * 2)
		_grid_bg.queue_redraw()

	# Size the tile canvas to the board area so clip_contents hides
	# tiles positioned above the top edge (spawn slide-in).
	if tile_canvas != null:
		tile_canvas.position = _board_offset
		tile_canvas.size = Vector2(board_pixel_w, board_pixel_h)


func estimate_cell_size(board_size: Vector2i) -> Vector2i:
	if board_size.x <= 0 or board_size.y <= 0:
		return Vector2i(80, 80)
	var available := size
	if available.x <= 0 or available.y <= 0:
		available = get_viewport_rect().size
	var padding := 8.0
	var usable_w := available.x - padding * 2.0
	var usable_h := available.y - padding * 2.0
	var cell_w := int((usable_w - (board_size.x - 1) * _spacing) / board_size.x)
	var cell_h := int((usable_h - (board_size.y - 1) * _spacing) / board_size.y)
	var cell_dim := mini(cell_w, cell_h)
	cell_dim = clampi(cell_dim, 40, 200)
	return Vector2i(cell_dim, cell_dim)


func _reposition_all() -> void:
	for cell_pos in _tile_views:
		var view: TileView = _tile_views[cell_pos]
		if is_instance_valid(view):
			view.position = _cell_to_pixel(cell_pos)
			view.custom_minimum_size = Vector2(_cell_size)
			view.size = Vector2(_cell_size)


# ---- Animation Phases ----


func _play_cascade_step(step: Dictionary, perf_label_prefix: String = "") -> void:
	# If chain_steps are present, play each round's highlight + remove/upgrade
	# sequentially, then gravity + spawn once at the end.
	var chain_steps: Array = step.get("chain_steps", [])
	var last_phase2_tween: Tween = null

	if not chain_steps.is_empty():
		for i in chain_steps.size():
			var round_data: Dictionary = chain_steps[i]
			var is_last_round := (i == chain_steps.size() - 1)
			last_phase2_tween = await _play_match_remove_upgrade(
				round_data.get("match_events", []),
				round_data.get("remove_events", []),
				round_data.get("upgrade_events", []),
				is_last_round,
			)
			# Brief pause between chain rounds (not after the last one)
			if not is_last_round and AnimationSequencer.chain_pause > 0.0:
				await get_tree().create_timer(AnimationSequencer.chain_pause).timeout
	else:
		# Legacy path: no chain_steps, use flat event arrays
		last_phase2_tween = await _play_match_remove_upgrade(
			step.get("match_events", []),
			step.get("remove_events", []),
			step.get("upgrade_events", []),
			true,
		)

	# Phase 3: Unified gravity + spawn fall with stagger and landing bounce.
	# Gravity events are consolidated per tile (multi-step -> single move) so
	# fall duration is computed from full travel distance. Tiles closer to the
	# destination start falling first, creating a cascading ripple.
	var gravity_events: Array = step.get("gravity_events", [])
	var spawn_events: Array = step.get("spawn_events", [])

	if not gravity_events.is_empty() or not spawn_events.is_empty():
		# --- Consolidate gravity events per tile ---
		# Physics produces per-round single-cell moves; merge into one
		# (original_from -> final_to) entry per tile for correct distance.
		var gravity_moves: Array[Dictionary] = []
		var grav_index: Dictionary = {}  # view instance_id -> index in gravity_moves
		for event in gravity_events:
			var from: Vector2i = event.get("from", Vector2i(-1, -1))
			var to: Vector2i = event.get("to", Vector2i(-1, -1))
			if _tile_views.has(from):
				var view: TileView = _tile_views[from]
				var vid := view.get_instance_id()
				if grav_index.has(vid):
					gravity_moves[grav_index[vid]]["final_to"] = to
				else:
					grav_index[vid] = gravity_moves.size()
					gravity_moves.append({
						"view": view,
						"original_from": from,
						"final_to": to,
					})
				_tile_views.erase(from)
				_tile_views[to] = view
				view.cell = to

		# --- Pre-create spawn tiles above the board, stacked per column ---
		var spawns_by_col: Dictionary = {}
		for event in spawn_events:
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			if not spawns_by_col.has(cell.x):
				spawns_by_col[cell.x] = []
			spawns_by_col[cell.x].append(event)

		for col in spawns_by_col:
			var col_spawns: Array = spawns_by_col[col]
			col_spawns.sort_custom(func(a, b):
				return a.get("cell", Vector2i.ZERO).y > b.get("cell", Vector2i.ZERO).y
			)

		var spawn_moves: Array[Dictionary] = []
		for col in spawns_by_col:
			var col_spawns: Array = spawns_by_col[col]
			for i in col_spawns.size():
				var event: Dictionary = col_spawns[i]
				var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
				var spawn_tile_id: StringName = event.get("tile_id", &"")
				var spawn_tier: int = event.get("tier", 1)
				var start_row := -(i + 1)
				var view := _acquire_view(spawn_tile_id, spawn_tier, cell)
				view.position = _cell_to_pixel(Vector2i(cell.x, start_row))
				spawn_moves.append({
					"view": view,
					"original_from": Vector2i(cell.x, start_row),
					"final_to": cell,
				})
				_tile_views[cell] = view
				view.cell = cell

		# --- Compute per-column stagger delays ---
		# Group by destination column, sort bottom-first so tiles closest to
		# the gap start falling first.
		var all_moves: Array[Dictionary] = []
		all_moves.append_array(gravity_moves)
		all_moves.append_array(spawn_moves)

		var stagger_cols: Dictionary = {}
		for move in all_moves:
			var col: int = move["final_to"].x
			if not stagger_cols.has(col):
				stagger_cols[col] = []
			stagger_cols[col].append(move)

		for col in stagger_cols:
			var col_moves: Array = stagger_cols[col]
			col_moves.sort_custom(func(a, b):
				return a["final_to"].y > b["final_to"].y
			)
			for i in col_moves.size():
				col_moves[i]["stagger"] = minf(
					float(i) * AnimationSequencer.gravity_stagger_delay,
					AnimationSequencer.gravity_stagger_max)

		# --- Build parallel tween with stagger ---
		# Each tile's landing bounce fires individually via tween_callback when
		# that tile reaches its destination, rather than collectively after all
		# tiles land.  This avoids short-fall tiles sitting motionless while
		# waiting for long-fall tiles to finish.
		var tween := create_tween().set_parallel(true)
		var has_targets := false

		for move in all_moves:
			var view: TileView = move["view"]
			var orig_from: Vector2i = move["original_from"]
			var final_to: Vector2i = move["final_to"]
			var distance := AnimationSequencer.cell_distance(orig_from, final_to)
			var duration := AnimationSequencer.fall_duration(distance)
			var stagger: float = move.get("stagger", 0.0)
			tween.tween_property(view, "position",
				_cell_to_pixel(final_to), duration) \
				.set_ease(Tween.EASE_IN) \
				.set_trans(AnimationSequencer.gravity_trans) \
				.set_delay(stagger)
			move["distance"] = distance
			# Per-tile landing bounce: fires at (stagger + duration), exactly when
			# this tile arrives, instead of after all tiles finish.
			tween.tween_callback(
				_start_single_landing_bounce.bind(move)
			).set_delay(stagger + duration)
			has_targets = true

		if has_targets:
			await tween.finished

	# Ensure last remove/upgrade phase is fully done before the next cascade step
	if last_phase2_tween != null and last_phase2_tween.is_running():
		await last_phase2_tween.finished


## Plays the match highlight + remove/upgrade phases for one chain round.
## Returns the phase2 tween (may still be running if is_last_round is true,
## because the last round uses the gravity overlap).
func _play_match_remove_upgrade(
	match_events: Array,
	remove_events: Array,
	upgrade_events: Array,
	is_last_round: bool,
) -> Tween:
	# Phase 1: Match highlight
	var highlighted_cells: Array[Vector2i] = []
	if not match_events.is_empty():
		var tween := create_tween().set_parallel(true)
		var has_targets := false
		for event in match_events:
			var cells: Array = event.get("cells", [])
			for cell in cells:
				if _tile_views.has(cell):
					var view: TileView = _tile_views[cell]
					tween.tween_property(view, "modulate",
						Color(1.5, 1.5, 1.5, 1.0),
						AnimationSequencer.match_highlight_duration)
					highlighted_cells.append(cell)
					has_targets = true
		if has_targets:
			await tween.finished

	# Phase 2: Removals + upgrades
	var phase2_tween: Tween = null
	var phase2_has_targets := false
	if not remove_events.is_empty() or not upgrade_events.is_empty():
		phase2_tween = create_tween().set_parallel(true)
		var upgrade_pulse_duration := maxf(AnimationSequencer.upgrade_scale_duration, 0.0)
		var upgrade_peak_scale := maxf(AnimationSequencer.upgrade_scale_factor, 1.0)
		var upgrade_reset_delay := maxf(AnimationSequencer.removal_duration, upgrade_pulse_duration)

		# Build mapping: which removed cells should fly to which upgrade cell.
		# Correlate via match_events — each match's cells contain exactly one
		# upgrade cell and N-1 remove cells.
		var upgrade_cell_set: Dictionary = {}
		for event in upgrade_events:
			upgrade_cell_set[event.get("cell", Vector2i(-1, -1))] = true

		var remove_target: Dictionary = {}  # remove_cell -> upgrade_cell
		for match_event in match_events:
			var cells: Array = match_event.get("cells", [])
			var match_upgrade_cell: Vector2i = Vector2i(-1, -1)
			for cell in cells:
				if upgrade_cell_set.has(cell):
					match_upgrade_cell = cell
					break
			if match_upgrade_cell != Vector2i(-1, -1):
				for cell in cells:
					if cell != match_upgrade_cell:
						remove_target[cell] = match_upgrade_cell

		# Animate upgrades first (so z_index and scale are set before remove tweens)
		for event in upgrade_events:
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			var new_tier: int = event.get("new_tier", 0)
			var new_tile_id: StringName = event.get("tile_id", &"")
			if _tile_views.has(cell):
				var view: TileView = _tile_views[cell]
				# Render above converging tiles
				view.z_index = 1
				# Show the new gem visual immediately, then expand from zero
				view.modulate = Color.WHITE
				view.show_upgrade_full(new_tier, new_tile_id)
				view.play_role(&"upgrade")
				view.scale = Vector2.ZERO
				if upgrade_pulse_duration <= 0.0:
					view.scale = Vector2.ONE
				else:
					var grow_duration := upgrade_pulse_duration * 0.5
					var settle_duration := maxf(0.0, upgrade_pulse_duration - grow_duration)
					phase2_tween.tween_property(view, "scale",
						Vector2.ONE * upgrade_peak_scale, grow_duration) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					if settle_duration > 0.0:
						phase2_tween.tween_callback(
							_start_upgrade_settle.bind(view, settle_duration)
						).set_delay(grow_duration)
					else:
						phase2_tween.tween_callback(view.set.bind(&"scale", Vector2.ONE)).set_delay(
							grow_duration)
				# Reset z_index after animation completes
				phase2_tween.tween_callback(view.set.bind(&"z_index", 0)).set_delay(
					upgrade_reset_delay)
				phase2_has_targets = true

		# Animate removals
		for event in remove_events:
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			if _tile_views.has(cell):
				var view: TileView = _tile_views[cell]
				_tile_views.erase(cell)
				if remove_target.has(cell):
					# Fly toward the upgrade cell: move + moderate shrink.
					# Old gems stay visually prominent during travel so they
					# appear to "cause" the new gem's expansion.  The expanding
					# upgrade gem (z_index 1) covers them on arrival; a rapid
					# fire-and-forget cleanup handles the final fade behind it.
					var target_pos := _cell_to_pixel(remove_target[cell])
					phase2_tween.tween_property(view, "position", target_pos,
						AnimationSequencer.removal_duration) \
						.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					phase2_tween.tween_property(view, "scale",
						Vector2(0.5, 0.5), AnimationSequencer.removal_duration) \
						.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					# Fire-and-forget: rapid fade + shrink hidden behind the upgrade gem
					phase2_tween.tween_callback(
						_start_merge_cleanup.bind(view)).set_delay(
						AnimationSequencer.removal_duration)
				else:
					# No upgrade target (T8 pure removal, etc.) — standard fadeout
					phase2_tween.tween_property(view, "modulate:a", 0.0,
						AnimationSequencer.removal_duration)
					phase2_tween.tween_property(view, "scale",
						Vector2(0.5, 0.5), AnimationSequencer.removal_duration)
					phase2_tween.tween_callback(_release_view.bind(view)).set_delay(
						AnimationSequencer.removal_duration)
				phase2_has_targets = true

		if phase2_has_targets:
			if is_last_round:
				# Last round: use gravity overlap (gravity starts before fadeout finishes)
				var overlap_wait := maxf(0.0,
					AnimationSequencer.removal_duration - AnimationSequencer.removal_gravity_overlap)
				await get_tree().create_timer(overlap_wait).timeout
			else:
				# Mid-chain round: wait for removals to finish, then start the next
				# chain round immediately. The upgrade pulse keeps playing — the next
				# round's highlight + fadeout will layer on top of it naturally.
				await get_tree().create_timer(AnimationSequencer.removal_duration).timeout
				# Don't null phase2_tween — it may still be expanding
	else:
		# No removals/upgrades — reset any highlighted cells
		for cell in highlighted_cells:
			if _tile_views.has(cell):
				_tile_views[cell].modulate = Color.WHITE

	return phase2_tween


## Starts an async landing bounce for a single tile that just landed.
## Fire-and-forget — not awaited, so the cascade continues immediately.
## Bounce magnitude scales slightly with fall distance but stays within grid borders.
func _start_single_landing_bounce(move: Dictionary) -> void:
	if AnimationSequencer.landing_bounce_duration <= 0.0:
		return
	var view: TileView = move["view"]
	var distance: int = move.get("distance", 1)
	if not is_instance_valid(view) or distance <= 0:
		return
	var cell_step := float(_cell_size.y + _spacing)
	var orig_from: Vector2i = move["original_from"]
	var final_to: Vector2i = move["final_to"]
	var fall_dir := Vector2(final_to - orig_from).normalized()
	# Rebound between 3.5% and 5% of cell step, scaling with fall distance
	var rebound_px := clampf(float(distance) * 0.01, 0.01, 0.05) * cell_step
	var target_pos := _cell_to_pixel(final_to)
	var rebound_pos := target_pos - fall_dir * rebound_px
	var dur := AnimationSequencer.landing_bounce_duration
	var bounce_tween := create_tween()
	bounce_tween.tween_property(view, "position", rebound_pos, dur * 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	bounce_tween.tween_property(view, "position", target_pos, dur * 0.65) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## Rapid fire-and-forget cleanup for old gems that have arrived at the upgrade cell.
## The expanding upgrade gem (z_index 1) already covers them visually; this just
## finishes the shrink + fade and frees the node.
func _start_merge_cleanup(view: TileView) -> void:
	if not is_instance_valid(view):
		return
	# Force behind the upgrade gem (whose z_index resets to 0 on the same frame)
	view.z_index = -1
	var t := create_tween().set_parallel(true)
	t.tween_property(view, "scale", Vector2.ZERO, 0.06)
	t.tween_property(view, "modulate:a", 0.0, 0.06)
	t.tween_callback(_release_view.bind(view)).set_delay(0.06)


func _start_upgrade_settle(view: TileView, duration: float) -> void:
	if not is_instance_valid(view):
		return
	var t := create_tween()
	t.tween_property(view, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---- Input Handling ----


func _gui_input(event: InputEvent) -> void:
	if _input_locked:
		return

	# --- Mouse press: start a potential drag ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := _pixel_to_cell(event.position)
			_drag_origin = cell
			_drag_completed = false
		else:
			# Mouse released — if drag didn't complete, treat as a tap
			if not _drag_completed and _drag_origin != Vector2i(-1, -1):
				_handle_tap(_drag_origin)
			_drag_origin = Vector2i(-1, -1)
			_drag_completed = false
		return

	# --- Mouse motion while held: detect drag into adjacent cell ---
	if event is InputEventMouseMotion and _drag_origin != Vector2i(-1, -1) and not _drag_completed:
		var current_cell := _pixel_to_cell(event.position)
		if current_cell == Vector2i(-1, -1) or current_cell == _drag_origin:
			return
		var diff := (_drag_origin - current_cell).abs()
		if (diff.x + diff.y) == 1:
			# Valid adjacent drag — emit swap and consume the drag
			_deselect()
			_drag_completed = true
			swap_requested.emit(_drag_origin, current_cell)


## Handles a tap (press + release on the same cell without dragging).
## Implements the two-tap swap: first tap selects, second tap on adjacent cell swaps.
func _handle_tap(cell: Vector2i) -> void:
	if cell == Vector2i(-1, -1):
		_deselect()
		return

	if _selected_cell == Vector2i(-1, -1):
		_select_cell(cell)
		cell_pressed.emit(cell)
	elif _selected_cell == cell:
		_deselect()
	else:
		var diff := (_selected_cell - cell).abs()
		if (diff.x + diff.y) == 1:
			swap_requested.emit(_selected_cell, cell)
		_deselect()


func _select_cell(cell: Vector2i) -> void:
	_deselect()
	_selected_cell = cell
	if _tile_views.has(cell):
		var view: TileView = _tile_views[cell]
		view.modulate = Color(1.0, 1.0, 0.7, 1.0)


func _deselect() -> void:
	if _selected_cell != Vector2i(-1, -1) and _tile_views.has(_selected_cell):
		var view: TileView = _tile_views[_selected_cell]
		view.modulate = Color.WHITE
	_selected_cell = Vector2i(-1, -1)


# ---- Board Construction & Tile View Pool ----


func _rebuild_all() -> void:
	if tile_canvas == null or _board_state == null:
		return

	# Return all tracked views to the pool
	for key in _tile_views:
		_release_view(_tile_views[key])
	_tile_views.clear()

	# Pre-populate pool so gameplay never needs to instantiate nodes.
	# Board tiles + headroom for spawns/animations.
	var needed := _board_state.size.x * _board_state.size.y + 24
	_ensure_pool(needed)

	for pos in _board_state.all_cells():
		var tile: TileState = _board_state.get_tile(pos)
		if tile != null:
			var view := _acquire_view(tile.tile_id, tile.tier, pos)
			view.position = _cell_to_pixel(pos)
			_tile_views[pos] = view


## Ensures the pool has at least `count` total views (active + pooled).
func _ensure_pool(count: int) -> void:
	var existing := _view_pool.size()
	# Also count active views — they'll return to the pool eventually
	for _key in _tile_views:
		existing += 1
	while existing < count:
		var view := _make_bare_view()
		view.visible = false
		_view_pool.append(view)
		existing += 1


## Creates a raw TileView node and adds it to the canvas.
## Only called during pool pre-population, never during gameplay.
func _make_bare_view() -> TileView:
	assert(tile_view_scene!=null,"BoardScene requires its declared TileView scene")
	var view:TileView=tile_view_scene.instantiate()
	view.delivery_failed.connect(func(message:String)->void:delivery_failed.emit(message))
	view.custom_minimum_size = Vector2(_cell_size)
	view.size = Vector2(_cell_size)
	tile_canvas.add_child(view)
	return view


## Grabs a view from the pool (or creates one as fallback), configures it,
## and makes it visible.  Does NOT register it in _tile_views — caller decides.
func _acquire_view(p_tile_id: StringName, p_tier: int, p_cell: Vector2i) -> TileView:
	var view: TileView
	if not _view_pool.is_empty():
		view = _view_pool.pop_back()
	else:
		# Pool exhausted — create on the fly (shouldn't happen after pre-warm)
		push_warning("[BoardScene] Pool miss — creating TileView at runtime")
		view = _make_bare_view()
	view.visible = true
	view.modulate = Color.WHITE
	view.scale = Vector2.ONE
	view.z_index = 0
	view.custom_minimum_size = Vector2(_cell_size)
	view.size = Vector2(_cell_size)
	view.configure_from_data(p_tile_id, p_tier, p_cell)
	return view


## Resets a view and returns it to the pool for later reuse.
## Safe to call multiple times on the same view (idempotent via visible check).
func _release_view(view: TileView) -> void:
	if not is_instance_valid(view) or not view.visible:
		return  # already released or freed
	view.visible = false
	view.modulate = Color.WHITE
	view.scale = Vector2.ONE
	view.z_index = 0
	_view_pool.append(view)


# ---- Coordinate Conversion ----


## Converts a grid cell to a pixel position local to the TileCanvas.
## Negative rows (e.g. -1, -2) produce positions above the board for spawn staging.
func _cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * (_cell_size.x + _spacing),
		cell.y * (_cell_size.y + _spacing))


func _pixel_to_cell(pixel: Vector2) -> Vector2i:
	var adjusted := pixel - _board_offset
	if adjusted.x < 0 or adjusted.y < 0:
		return Vector2i(-1, -1)
	var cell_step_x := _cell_size.x + _spacing
	var cell_step_y := _cell_size.y + _spacing
	var cell_x := int(adjusted.x / cell_step_x)
	var cell_y := int(adjusted.y / cell_step_y)
	var local_x := adjusted.x - cell_x * cell_step_x
	var local_y := adjusted.y - cell_y * cell_step_y
	if local_x > _cell_size.x or local_y > _cell_size.y:
		return Vector2i(-1, -1)
	var candidate := Vector2i(cell_x, cell_y)
	if _board_state != null and _board_state.in_bounds(candidate) and \
	   not _board_state.is_blocked(candidate):
		return candidate
	return Vector2i(-1, -1)
