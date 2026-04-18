extends Control
## 81-sample spectrum editor (380–780 nm, 5 nm steps). Piecewise linear between draggable knots;
## knots can be added/removed for arbitrary wavelength control.

signal samples_changed(samples: PackedFloat32Array)

const SPECTRUM_LEN := 81
const LAMBDA_MIN_NM := 380.0
const LAMBDA_MAX_NM := 780.0

## Sorted knot sample indices; always includes 0 and 80.
var _knot_indices: Array[int] = []
var _samples: PackedFloat32Array = PackedFloat32Array()
var _overlay: PackedFloat32Array = PackedFloat32Array()
var _show_overlay: bool = false
var _dragging_knot: int = -1
## Manual Y-axis max; 0 = auto from data (min 1.0).
var y_axis_max: float = 0.0
var _plot_rect: Rect2 = Rect2()
var _strip_rect: Rect2 = Rect2()
var _hover_plot: bool = false
var _hover_nm: float = 400.0
var _hover_val: float = 0.0
var _hover_idx: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(320, 240)
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	if _samples.size() != SPECTRUM_LEN:
		_samples.resize(SPECTRUM_LEN)
		for i in SPECTRUM_LEN:
			_samples[i] = 0.0
	_init_default_knots()
	queue_redraw()


func _init_default_knots() -> void:
	_knot_indices.clear()
	for i in range(0, SPECTRUM_LEN, 10):
		_knot_indices.append(i)
	if _knot_indices.back() != SPECTRUM_LEN - 1:
		_knot_indices.append(SPECTRUM_LEN - 1)
	_dedupe_sort_knots()


func _dedupe_sort_knots() -> void:
	var seen := {}
	var out: Array[int] = []
	for k in _knot_indices:
		var kk: int = clampi(k, 0, SPECTRUM_LEN - 1)
		if not seen.has(kk):
			seen[kk] = true
			out.append(kk)
	out.sort()
	if out.is_empty() or out[0] != 0:
		out.insert(0, 0)
	if out.back() != SPECTRUM_LEN - 1:
		out.append(SPECTRUM_LEN - 1)
	_knot_indices = out


func set_samples(s: PackedFloat32Array) -> void:
	_samples = _ensure_len(s)
	if _knot_indices.is_empty():
		_init_default_knots()
	queue_redraw()


func get_samples() -> PackedFloat32Array:
	return _samples.duplicate()


func set_overlay_samples(s: PackedFloat32Array) -> void:
	if s.is_empty():
		_show_overlay = false
		_overlay.clear()
	else:
		_show_overlay = true
		_overlay = _ensure_len(s)
	queue_redraw()


func set_y_axis_max(v: float) -> void:
	y_axis_max = maxf(0.0, v)
	queue_redraw()


func _ensure_len(s: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SPECTRUM_LEN)
	for i in SPECTRUM_LEN:
		out[i] = s[i] if i < s.size() else 0.0
	return out


## Piecewise linear interpolation between knot anchors (updates interior samples only).
func _resample_from_knots() -> void:
	_dedupe_sort_knots()
	for seg in range(_knot_indices.size() - 1):
		var i0: int = _knot_indices[seg]
		var i1: int = _knot_indices[seg + 1]
		var v0: float = _samples[i0]
		var v1: float = _samples[i1]
		var span: int = i1 - i0
		if span <= 0:
			continue
		for j in range(1, span):
			var t: float = float(j) / float(span)
			_samples[i0 + j] = lerpf(v0, v1, t)


func _max_y_data() -> float:
	var m := 0.001
	for i in SPECTRUM_LEN:
		m = maxf(m, _samples[i])
	if _show_overlay:
		for i in _overlay.size():
			m = maxf(m, _overlay[i])
	return m


func _axis_max_val() -> float:
	if y_axis_max > 0.0:
		return y_axis_max
	return maxf(1.0, _max_y_data())


func _index_to_nm(idx: int) -> float:
	return LAMBDA_MIN_NM + float(idx) * 5.0


func _approx_wavelength_color(nm: float) -> Color:
	var t := clampf((nm - 380.0) / 400.0, 0.0, 1.0)
	return Color.from_hsv(lerpf(0.78, 0.0, t), 0.82, 0.92)


func _draw() -> void:
	var bg := Color(0.06, 0.07, 0.09)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# Layout: color strip (14px), plot, labels
	var strip_h := 14.0
	var label_h := 22.0
	var margin := 8.0
	_strip_rect = Rect2(Vector2(margin, margin), Vector2(size.x - margin * 2.0, strip_h))
	_plot_rect = Rect2(
		Vector2(margin, margin + strip_h + 4.0),
		Vector2(size.x - margin * 2.0, size.y - margin * 2.0 - strip_h - 4.0 - label_h)
	)
	# Wavelength reference strip
	var steps := 48
	for s in steps:
		var t0: float = float(s) / float(steps)
		var t1: float = float(s + 1) / float(steps)
		var nm0: float = lerpf(LAMBDA_MIN_NM, LAMBDA_MAX_NM, t0)
		var col := _approx_wavelength_color(nm0)
		var x0: float = _strip_rect.position.x + t0 * _strip_rect.size.x
		var x1: float = _strip_rect.position.x + t1 * _strip_rect.size.x
		draw_rect(Rect2(Vector2(x0, _strip_rect.position.y), Vector2(x1 - x0 + 0.5, _strip_rect.size.y)), col)

	draw_rect(_plot_rect, Color(0.12, 0.13, 0.16))
	for g in range(5):
		var tt: float = float(g) / 4.0
		var x: float = _plot_rect.position.x + tt * _plot_rect.size.x
		draw_line(Vector2(x, _plot_rect.position.y), Vector2(x, _plot_rect.position.y + _plot_rect.size.y), Color(0.22, 0.24, 0.3, 0.5), 1.0)
	for gy in range(5):
		var tty: float = float(gy) / 4.0
		var y: float = _plot_rect.position.y + tty * _plot_rect.size.y
		draw_line(Vector2(_plot_rect.position.x, y), Vector2(_plot_rect.position.x + _plot_rect.size.x, y), Color(0.22, 0.24, 0.3, 0.5), 1.0)

	var axis_max: float = _axis_max_val()
	var prev: Vector2
	if _show_overlay and _overlay.size() == SPECTRUM_LEN:
		for i in SPECTRUM_LEN:
			var px: float = _plot_rect.position.x + (float(i) / float(SPECTRUM_LEN - 1)) * _plot_rect.size.x
			var py: float = _plot_rect.position.y + _plot_rect.size.y - (_overlay[i] / axis_max) * _plot_rect.size.y
			var pt := Vector2(px, py)
			if i > 0:
				draw_line(prev, pt, Color(0.45, 0.45, 0.5, 0.6), 1.5)
			prev = pt

	for i in SPECTRUM_LEN:
		var px2: float = _plot_rect.position.x + (float(i) / float(SPECTRUM_LEN - 1)) * _plot_rect.size.x
		var py2: float = _plot_rect.position.y + _plot_rect.size.y - (_samples[i] / axis_max) * _plot_rect.size.y
		var pt2 := Vector2(px2, py2)
		if i > 0:
			var px0: float = _plot_rect.position.x + (float(i - 1) / float(SPECTRUM_LEN - 1)) * _plot_rect.size.x
			var py0: float = _plot_rect.position.y + _plot_rect.size.y - (_samples[i - 1] / axis_max) * _plot_rect.size.y
			draw_line(Vector2(px0, py0), pt2, Color(0.35, 0.75, 0.95), 2.0)

	for ki in _knot_indices.size():
		var idx: int = _knot_indices[ki]
		var kx: float = _plot_rect.position.x + (float(idx) / float(SPECTRUM_LEN - 1)) * _plot_rect.size.x
		var ky: float = _plot_rect.position.y + _plot_rect.size.y - (_samples[idx] / axis_max) * _plot_rect.size.y
		var c := Color(0.95, 0.55, 0.25) if _dragging_knot == ki else Color(0.9, 0.9, 0.95)
		draw_circle(Vector2(kx, ky), 5.0, c)

	var fnt := get_theme_default_font()
	if fnt:
		draw_string(fnt, Vector2(_plot_rect.position.x, size.y - 4), "380 nm", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.58, 0.65))
		draw_string(fnt, Vector2(_plot_rect.position.x + _plot_rect.size.x - 52, size.y - 4), "780 nm", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.58, 0.65))
		var yinfo := "Y max: auto (%.3g)" % _max_y_data() if y_axis_max <= 0.0 else "Y max: %.3g (fixed)" % y_axis_max
		draw_string(fnt, Vector2(_plot_rect.position.x + 48, size.y - 4), yinfo, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 0.5, 0.58))
		if _hover_plot:
			var hr := "%.0f nm  α≈%.4g  i=%d" % [_hover_nm, _hover_val, _hover_idx]
			draw_string(fnt, Vector2(_plot_rect.position.x + _plot_rect.size.x * 0.35, _plot_rect.position.y + 12), hr, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.88, 0.95))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				if mb.double_click:
					_add_knot_at_mouse(mb.position)
				else:
					_dragging_knot = _hit_knot(mb.position)
			else:
				if _dragging_knot >= 0:
					samples_changed.emit(_samples.duplicate())
				_dragging_knot = -1
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_remove_nearest_inner_knot(mb.position)
			samples_changed.emit(_samples.duplicate())
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_update_hover(mm.position)
		if _dragging_knot >= 0:
			var am: float = _axis_max_val()
			var local_y: float = clampf(mm.position.y, _plot_rect.position.y, _plot_rect.position.y + _plot_rect.size.y)
			var norm: float = 1.0 - (local_y - _plot_rect.position.y) / maxf(_plot_rect.size.y, 0.001)
			var idx: int = _knot_indices[_dragging_knot]
			_samples[idx] = maxf(0.0, norm * am)
			_resample_from_knots()
			queue_redraw()
			accept_event()


func _update_hover(p: Vector2) -> void:
	_hover_plot = _plot_rect.has_point(p)
	if not _hover_plot:
		queue_redraw()
		return
	var t: float = (p.x - _plot_rect.position.x) / maxf(_plot_rect.size.x, 0.001)
	t = clampf(t, 0.0, 1.0)
	_hover_idx = clampi(int(round(t * float(SPECTRUM_LEN - 1))), 0, SPECTRUM_LEN - 1)
	_hover_nm = _index_to_nm(_hover_idx)
	_hover_val = _samples[_hover_idx]
	queue_redraw()


func _add_knot_at_mouse(p: Vector2) -> void:
	if not _plot_rect.has_point(p):
		return
	var t: float = (p.x - _plot_rect.position.x) / maxf(_plot_rect.size.x, 0.001)
	var new_idx: int = clampi(int(round(t * float(SPECTRUM_LEN - 1))), 1, SPECTRUM_LEN - 2)
	for k in _knot_indices:
		if k == new_idx:
			return
	_knot_indices.append(new_idx)
	_dedupe_sort_knots()
	_resample_from_knots()


func _remove_nearest_inner_knot(p: Vector2) -> void:
	if _knot_indices.size() <= 2:
		return
	var hit := _hit_knot(p)
	if hit < 0:
		return
	var idx: int = _knot_indices[hit]
	if idx <= 0 or idx >= SPECTRUM_LEN - 1:
		return
	_knot_indices.remove_at(hit)
	_resample_from_knots()


func _hit_knot(p: Vector2) -> int:
	var am: float = _axis_max_val()
	for ki in _knot_indices.size():
		var idx: int = _knot_indices[ki]
		var kx: float = _plot_rect.position.x + (float(idx) / float(SPECTRUM_LEN - 1)) * _plot_rect.size.x
		var ky: float = _plot_rect.position.y + _plot_rect.size.y - (_samples[idx] / am) * _plot_rect.size.y
		if p.distance_to(Vector2(kx, ky)) < 10.0:
			return ki
	return -1


## Add a Gaussian absorption band in model units (adds to all 81 samples).
func add_gaussian_band(center_nm: float, sigma_nm: float, strength: float) -> void:
	var sig := maxf(sigma_nm, 1.0)
	for i in SPECTRUM_LEN:
		var nm: float = LAMBDA_MIN_NM + float(i) * 5.0
		var d: float = (nm - center_nm) / sig
		_samples[i] = maxf(0.0, _samples[i] + strength * exp(-0.5 * d * d))
	samples_changed.emit(_samples.duplicate())
	queue_redraw()
