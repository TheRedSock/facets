class_name MergeInputBuffer
extends RefCounted
## One presentation-only intent. Rule admission happens at the NEXT opportunity.
signal queued
var pending := {}
var selected_id := ""
var press_id := ""
var dragged := false
var press_position := Vector2.ZERO

func clear() -> void:
	pending = {}; reset_gesture()

func reset_gesture() -> void:
	selected_id = ""; press_id = ""; dragged = false

func put(first: String, second: String) -> bool:
	if first.is_empty() or second.is_empty() or first == second: return false
	pending = {"origin_id":first,"destination_id":second,"queued_us":Time.get_ticks_usec()}
	reset_gesture(); queued.emit(); return true

func take(board: BoardState) -> Dictionary:
	var intent := pending; clear()
	if intent.is_empty(): return {}
	var positions := {}
	for pos in board.all_cells():
		var tile := board.get_tile(pos)
		if tile != null and tile.instance_id in [intent.origin_id,intent.destination_id]: positions[tile.instance_id] = pos
	if positions.size() != 2: return {"ok":false,"code":"gem_removed","intent":intent}
	return {"ok":true,"origin":positions[intent.origin_id],"destination":positions[intent.destination_id],"intent":intent}

func pick(point: Vector2, board: BoardScene, views: Dictionary) -> String:
	var local := point-board._board_offset
	if not Rect2(Vector2.ZERO,board.tile_canvas.size).has_point(local): return ""
	# Use currently drawn live poses during travel, never departed merge ghosts.
	var chosen := ""; var distance := INF
	for id: String in views:
		var view: TileView = views[id]
		if not is_instance_valid(view) or not view.visible or view.modulate.a <= 0.05: continue
		var rect := Rect2(view.position,Vector2(board._cell_size))
		var d := local.distance_squared_to(rect.get_center())
		if rect.has_point(local) and d < distance: chosen = id; distance = d
	return chosen

func tap(id: String) -> void:
	if id.is_empty() or id == selected_id: selected_id = ""; return
	if selected_id.is_empty(): selected_id = id
	else: put(selected_id,id)

func handle(event: InputEvent, board: BoardScene, views: Dictionary) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var direction := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT: direction = Vector2i.LEFT
			KEY_RIGHT: direction = Vector2i.RIGHT
			KEY_UP: direction = Vector2i.UP
			KEY_DOWN: direction = Vector2i.DOWN
			KEY_ENTER, KEY_SPACE: tap(pick(board._board_offset+board._cell_to_pixel(board.cursor_cell)+Vector2(board._cell_size)*0.5,board,views))
		board.cursor_cell = (board.cursor_cell+direction).clamp(Vector2i.ZERO,board._board_state.size-Vector2i.ONE)
		board._overlay.queue_redraw(); board.accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			board.grab_focus(); press_id = pick(event.position,board,views)
			press_position = event.position; dragged = false
		else:
			if not dragged: tap(press_id)
			press_id = ""; dragged = false
	elif event is InputEventMouseMotion and not press_id.is_empty() and not dragged:
		if event.position.distance_to(press_position) < minf(board._cell_size.x,board._cell_size.y)*0.4: return
		var id := pick(event.position,board,views)
		if not id.is_empty() and id != press_id:
			put(press_id,id); dragged = true

func draw(overlay: Control, board: BoardScene, views: Dictionary) -> void:
	var ids: Array = [selected_id] if pending.is_empty() else [pending.origin_id,pending.destination_id]
	var points: Array[Vector2] = []
	for id in ids:
		var view: TileView = views.get(id)
		if not is_instance_valid(view): continue
		var rect := Rect2(board._board_offset+view.position,Vector2(board._cell_size)).grow(-5)
		overlay.draw_rect(rect,Color("7de6ed"),false,3)
		points.append(rect.get_center())
	if points.size() == 2: overlay.draw_line(points[0],points[1],Color("7de6ed"),3,true)
