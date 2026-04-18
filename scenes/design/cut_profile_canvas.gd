extends Control
## Normalized 2D polygon editor for cut ring `points` (PackedVector2Array in ~0–1 space).

## Emitted once when a vertex drag ends (heavy contract updates should connect here).
signal polygon_committed(points: PackedVector2Array)
## Optional live preview while dragging (no heavy work).
signal polygon_dragging(points: PackedVector2Array)

var _points: PackedVector2Array = PackedVector2Array()
## Other rings' outlines (same canvas space), drawn faintly for context.
var _ghost_polygons: Array[PackedVector2Array] = []
var _drag_index: int = -1
var _hover_index: int = -1
## When enabled and the point count divides evenly by sector_count, dragging one
## vertex propagates the canonical point across rotational sectors.
var sector_count: int = 0
var sector_rotation_radians: float = 0.0
var symmetry_rotation_enabled: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(280, 260)
	mouse_filter = MOUSE_FILTER_STOP


func set_polygon(pts: PackedVector2Array) -> void:
	_points = pts.duplicate()
	queue_redraw()


func get_polygon() -> PackedVector2Array:
	return _points.duplicate()


func set_ghost_polygons(polygons: Array) -> void:
	_ghost_polygons.clear()
	for p in polygons:
		if p is PackedVector2Array:
			_ghost_polygons.append(p)
	queue_redraw()


func _apply_drag_position(new_pos: Vector2) -> void:
	if _drag_index < 0 or _drag_index >= _points.size():
		return
	if not symmetry_rotation_enabled or sector_count < 2 or _points.size() % sector_count != 0:
		_points[_drag_index] = new_pos
		return
	var per_sector := _points.size() / sector_count
	if per_sector <= 0:
		_points[_drag_index] = new_pos
		return
	var local_index := _drag_index % per_sector
	var sector_index := _drag_index / per_sector
	var center := Vector2(0.5, 0.5)
	var sector_angle := TAU / float(sector_count)
	var canonical := (new_pos - center).rotated(-(sector_rotation_radians + sector_angle * float(sector_index)))
	for s in sector_count:
		var idx := local_index + s * per_sector
		if idx < 0 or idx >= _points.size():
			continue
		_points[idx] = center + canonical.rotated(sector_rotation_radians + sector_angle * float(s))


func _to_canvas(p: Vector2) -> Vector2:
	var pad := 12.0
	var r := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	return Vector2(r.position.x + p.x * r.size.x, r.position.y + (1.0 - p.y) * r.size.y)


func _from_canvas(screen: Vector2) -> Vector2:
	var pad := 12.0
	var r := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var lx: float = clampf((screen.x - r.position.x) / maxf(r.size.x, 0.001), 0.0, 1.0)
	var ly: float = clampf(1.0 - (screen.y - r.position.y) / maxf(r.size.y, 0.001), 0.0, 1.0)
	return Vector2(lx, ly)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09))
	var pad := 12.0
	var frame := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	draw_rect(frame, Color(0.11, 0.12, 0.15))
	for ghost in _ghost_polygons:
		if ghost.size() < 2:
			continue
		var gpts: PackedVector2Array = PackedVector2Array()
		for p in ghost:
			gpts.append(_to_canvas(p))
		for i in gpts.size():
			var j: int = (i + 1) % gpts.size()
			draw_line(gpts[i], gpts[j], Color(0.35, 0.5, 0.62, 0.35), 1.0)

	if _points.size() < 2:
		return
	var canvas_pts: PackedVector2Array = PackedVector2Array()
	for p in _points:
		canvas_pts.append(_to_canvas(p))
	for i in canvas_pts.size():
		var j: int = (i + 1) % canvas_pts.size()
		draw_line(canvas_pts[i], canvas_pts[j], Color(0.45, 0.8, 0.95), 1.5)
	for i in canvas_pts.size():
		var hov := i == _hover_index or i == _drag_index
		draw_circle(canvas_pts[i], 5.0, Color(0.95, 0.55, 0.25) if hov else Color(0.85, 0.88, 0.95))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_index = _hit_vertex(mb.position)
			else:
				if _drag_index >= 0:
					polygon_committed.emit(_points.duplicate())
				_drag_index = -1
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover_index = _hit_vertex(mm.position)
		if _drag_index >= 0:
			_apply_drag_position(_from_canvas(mm.position))
			polygon_dragging.emit(_points.duplicate())
		queue_redraw()
		accept_event()


func _hit_vertex(screen: Vector2) -> int:
	for i in _points.size():
		var c := _to_canvas(_points[i])
		if c.distance_to(screen) < 9.0:
			return i
	return -1
