class_name BoardScene
extends Control

signal cell_pressed(cell: Vector2i)
signal swap_requested(cell_a: Vector2i, cell_b: Vector2i)

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

## Grid background for visual framing.
var _grid_bg: ColorRect

## The canvas node that holds all tile views.
@onready var tile_canvas: Control = %TileCanvas


func _ready() -> void:
	_grid_bg = ColorRect.new()
	_grid_bg.color = Color(0.15, 0.15, 0.2, 1.0)
	_grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid_bg)
	move_child(_grid_bg, 0)

	resized.connect(_on_resized)


func _on_resized() -> void:
	if _board_state != null:
		_compute_layout()
		_reposition_all()


# ---- Public API ----


func set_board_state(board_state: BoardState) -> void:
	_board_state = board_state
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	_compute_layout()
	_rebuild_all()


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
		await _play_cascade_step(step)
		if AnimationSequencer.cascade_pause > 0.0:
			await get_tree().create_timer(AnimationSequencer.cascade_pause).timeout


# ---- Layout Calculation ----


func _compute_layout() -> void:
	if _board_state == null:
		return

	var available := size
	if available.x <= 0 or available.y <= 0:
		available = get_viewport_rect().size

	var cols := _board_state.size.x
	var rows := _board_state.size.y

	var padding := 16.0
	var usable_w := available.x - padding * 2.0
	var usable_h := available.y - padding * 2.0

	var cell_w := int((usable_w - (cols - 1) * _spacing) / cols)
	var cell_h := int((usable_h - (rows - 1) * _spacing) / rows)
	var cell_dim := mini(cell_w, cell_h)
	cell_dim = mini(cell_dim, 120)
	cell_dim = maxi(cell_dim, 40)
	_cell_size = Vector2i(cell_dim, cell_dim)

	var board_pixel_w := cols * (_cell_size.x + _spacing) - _spacing
	var board_pixel_h := rows * (_cell_size.y + _spacing) - _spacing
	_board_offset = Vector2(
		(available.x - board_pixel_w) / 2.0,
		(available.y - board_pixel_h) / 2.0)

	if _grid_bg != null:
		var bg_padding := 10.0
		_grid_bg.position = _board_offset - Vector2(bg_padding, bg_padding)
		_grid_bg.size = Vector2(board_pixel_w + bg_padding * 2, board_pixel_h + bg_padding * 2)

	# Size the tile canvas to the board area so clip_contents hides
	# tiles positioned above the top edge (spawn slide-in).
	if tile_canvas != null:
		tile_canvas.position = _board_offset
		tile_canvas.size = Vector2(board_pixel_w, board_pixel_h)


func _reposition_all() -> void:
	for cell_pos in _tile_views:
		var view: TileView = _tile_views[cell_pos]
		if is_instance_valid(view):
			view.position = _cell_to_pixel(cell_pos)
			view.custom_minimum_size = Vector2(_cell_size)
			view.size = Vector2(_cell_size)


# ---- Animation Phases ----


func _play_cascade_step(step: Dictionary) -> void:
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

	# Phase 3: Unified gravity + spawn fall.
	# Spawn tiles are pre-created above the board and stacked per-column so they
	# slide in from beyond the clip boundary together with existing falling tiles.
	var gravity_events: Array = step.get("gravity_events", [])
	var spawn_events: Array = step.get("spawn_events", [])

	if not gravity_events.is_empty() or not spawn_events.is_empty():
		# Pre-create spawn tiles above the board, stacked per column.
		# Sort spawns per column by target row (topmost first) so they stack
		# at row -1, -2, -3, etc.
		var spawns_by_col: Dictionary = {}  # int (col) -> Array of spawn events
		for event in spawn_events:
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			if not spawns_by_col.has(cell.x):
				spawns_by_col[cell.x] = []
			spawns_by_col[cell.x].append(event)

		# Sort each column's spawns by target row (descending = deepest first).
		# The deepest target gets start row -1 (closest to the board edge) so
		# tiles maintain their column order as they fall — no crossing.
		for col in spawns_by_col:
			var col_spawns: Array = spawns_by_col[col]
			col_spawns.sort_custom(func(a, b):
				return a.get("cell", Vector2i.ZERO).y > b.get("cell", Vector2i.ZERO).y
			)

		# Create spawn views at stacked positions above the board.
		# Use untracked creation so they don't overwrite existing tile entries
		# that gravity events still need to look up by their 'from' cell.
		var spawn_views: Array[Dictionary] = []  # {view, target_cell, start_row}
		for col in spawns_by_col:
			var col_spawns: Array = spawns_by_col[col]
			for i in col_spawns.size():
				var event: Dictionary = col_spawns[i]
				var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
				var spawn_tile_id: StringName = event.get("tile_id", &"")
				var spawn_tier: int = event.get("tier", 1)
				var start_row := -(i + 1)  # -1, -2, -3, ...
				var view := _create_tile_view_untracked(spawn_tile_id, spawn_tier, cell)
				view.position = _cell_to_pixel(Vector2i(cell.x, start_row))
				spawn_views.append({
					"view": view,
					"target_cell": cell,
					"start_row": start_row,
				})

		# Build a single tween for all gravity moves + spawn falls
		var tween := create_tween().set_parallel(true)
		var has_targets := false

		for event in gravity_events:
			var from: Vector2i = event.get("from", Vector2i(-1, -1))
			var to: Vector2i = event.get("to", Vector2i(-1, -1))
			if _tile_views.has(from):
				var view: TileView = _tile_views[from]
				var distance := AnimationSequencer.cell_distance(from, to)
				var duration := AnimationSequencer.fall_duration(distance)
				tween.tween_property(view, "position",
					_cell_to_pixel(to), duration) \
					.set_ease(Tween.EASE_IN) \
					.set_trans(Tween.TRANS_QUAD)
				_tile_views.erase(from)
				_tile_views[to] = view
				view.cell = to
				has_targets = true

		for spawn_data in spawn_views:
			var view: TileView = spawn_data["view"]
			var target_cell: Vector2i = spawn_data["target_cell"]
			var start_row: int = spawn_data["start_row"]
			var distance := target_cell.y - start_row
			var duration := AnimationSequencer.fall_duration(distance)
			tween.tween_property(view, "position",
				_cell_to_pixel(target_cell), duration) \
				.set_ease(Tween.EASE_IN) \
				.set_trans(Tween.TRANS_QUAD)
			# Register in _tile_views now that gravity has updated existing tile tracking
			_tile_views[target_cell] = view
			view.cell = target_cell
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

		for event in remove_events:
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			if _tile_views.has(cell):
				var view: TileView = _tile_views[cell]
				phase2_tween.tween_property(view, "modulate:a", 0.0,
					AnimationSequencer.removal_duration)
				phase2_tween.tween_property(view, "scale",
					Vector2(0.5, 0.5), AnimationSequencer.removal_duration)
				_tile_views.erase(cell)
				phase2_tween.tween_callback(view.queue_free).set_delay(
					AnimationSequencer.removal_duration)
				phase2_has_targets = true

		for event in upgrade_events:
			var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
			var new_tier: int = event.get("new_tier", 0)
			var new_tile_id: StringName = event.get("tile_id", &"")
			if _tile_views.has(cell):
				var view: TileView = _tile_views[cell]
				# Reset highlight modulate before showing upgrade
				phase2_tween.tween_property(view, "modulate", Color.WHITE, 0.05)
				phase2_tween.tween_callback(view.show_upgrade_full.bind(new_tier, new_tile_id))
				phase2_tween.tween_property(view, "scale",
					Vector2.ONE * AnimationSequencer.upgrade_scale_factor, AnimationSequencer.upgrade_scale_duration)
				phase2_tween.tween_property(view, "scale",
					Vector2.ONE, AnimationSequencer.upgrade_scale_duration).set_delay(
					AnimationSequencer.upgrade_scale_duration)
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
				# Don't null phase2_tween — it may still be pulsing
	else:
		# No removals/upgrades — reset any highlighted cells
		for cell in highlighted_cells:
			if _tile_views.has(cell):
				_tile_views[cell].modulate = Color.WHITE

	return phase2_tween


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


# ---- Board Construction ----


func _rebuild_all() -> void:
	if tile_canvas == null or _board_state == null:
		return

	for key in _tile_views:
		var view: TileView = _tile_views[key]
		if is_instance_valid(view):
			view.queue_free()
	_tile_views.clear()

	for pos in _board_state.all_cells():
		var tile: TileState = _board_state.get_tile(pos)
		if tile != null:
			var view := _create_tile_view(tile.tile_id, tile.tier, pos)
			view.position = _cell_to_pixel(pos)
			view.modulate = Color.WHITE


func _create_tile_view(p_tile_id: StringName, p_tier: int, p_cell: Vector2i) -> TileView:
	var view := _create_tile_view_untracked(p_tile_id, p_tier, p_cell)
	_tile_views[p_cell] = view
	return view


## Creates a tile view and adds it to the canvas without registering it in _tile_views.
## Used for spawn tiles that are staged above the board before gravity runs.
func _create_tile_view_untracked(p_tile_id: StringName, p_tier: int, p_cell: Vector2i) -> TileView:
	var view: TileView
	if tile_view_scene != null:
		view = tile_view_scene.instantiate()
	else:
		view = TileView.new()
	view.custom_minimum_size = Vector2(_cell_size)
	view.size = Vector2(_cell_size)
	tile_canvas.add_child(view)
	view.configure_from_data(p_tile_id, p_tier, p_cell)
	return view


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
