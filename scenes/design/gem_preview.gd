class_name GemPreview
extends Control

## Standalone gem preview control for the design tool.
## Renders a gem from a cut_id and GemVisualResource using the same
## pipeline as TileView: GemCutGenerators -> GemRenderer -> draw_colored_polygon.

var _gem_cut: GemCutResource = null
var _gem_visual: GemVisualResource = null
var _gem_colors: PackedColorArray = PackedColorArray()
var _pavilion_colors: PackedColorArray = PackedColorArray()
var _valid: bool = false

## Cached scaled geometry — eliminates per-draw allocations.
var _scaled_facets: Array[PackedVector2Array] = []
var _scaled_pavilion: Array[PackedVector2Array] = []
var _scaled_silhouette: PackedVector2Array = PackedVector2Array()
var _scaled_edges: PackedVector2Array = PackedVector2Array()
var _edge_aa_a: PackedVector2Array = PackedVector2Array()
var _edge_aa_b: PackedVector2Array = PackedVector2Array()
var _edge_aa_colors: PackedColorArray = PackedColorArray()
var _cached_draw_size: Vector2 = Vector2.ZERO


func update_preview(cut_id: StringName, visual: GemVisualResource) -> void:
	_gem_cut = GemCutGenerators.generate(cut_id)
	if _gem_cut == null:
		_valid = false
		queue_redraw()
		return
	_gem_visual = visual
	_gem_colors = GemRenderer.compute_all_facet_colors(_gem_cut, _gem_visual)
	_pavilion_colors = GemRenderer.compute_pavilion_colors(_gem_cut, _gem_visual)
	_valid = true
	# Invalidate cached geometry so _draw() rebuilds it.
	_cached_draw_size = Vector2.ZERO
	queue_redraw()


## Rebuilds all cached scaled geometry from unit-space cut data.
func _rebuild_scaled_geometry() -> void:
	var s := minf(size.x, size.y)
	var offset := (size - Vector2(s, s)) * 0.5

	# Scale facet polygons.
	_scaled_facets.resize(_gem_cut.facet_count())
	for i in _gem_cut.facet_count():
		var verts := _gem_cut.facet_vertices[i]
		var scaled := PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		_scaled_facets[i] = scaled

	# Scale pavilion polygons.
	_scaled_pavilion.resize(_gem_cut.pavilion_count())
	for i in _gem_cut.pavilion_count():
		var verts := _gem_cut.pavilion_vertices[i]
		var scaled := PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		_scaled_pavilion[i] = scaled

	# Scale silhouette (with closing point).
	if _gem_cut.silhouette.size() >= 3:
		var sil := _gem_cut.silhouette
		_scaled_silhouette = PackedVector2Array()
		_scaled_silhouette.resize(sil.size() + 1)
		for j in sil.size():
			_scaled_silhouette[j] = sil[j] * s + offset
		_scaled_silhouette[sil.size()] = _scaled_silhouette[0]
	else:
		_scaled_silhouette = PackedVector2Array()

	# Scale edge endpoints (flat pairs for internal edge lines).
	_scaled_edges = PackedVector2Array()
	for seg in _gem_cut.edge_segments:
		if seg.size() >= 2:
			_scaled_edges.append(seg[0] * s + offset)
			_scaled_edges.append(seg[1] * s + offset)

	# Pre-compute edge AA data.
	_edge_aa_a = PackedVector2Array()
	_edge_aa_b = PackedVector2Array()
	_edge_aa_colors = PackedColorArray()
	if _gem_cut.edge_facet_a.size() == _gem_cut.edge_segments.size():
		for i in _gem_cut.edge_segments.size():
			var fa := _gem_cut.edge_facet_a[i]
			var fb := _gem_cut.edge_facet_b[i]
			if fa < 0 or fb < 0:
				continue
			if fa >= _gem_colors.size() or fb >= _gem_colors.size():
				continue
			var seg := _gem_cut.edge_segments[i]
			if seg.size() < 2:
				continue
			var a := seg[0] * s + offset
			var b := seg[1] * s + offset
			var dir := b - a
			var length := dir.length()
			if length < 4.0:
				continue
			var t := 1.5 / length
			a += dir * t
			b -= dir * t
			var ca := _gem_colors[fa]
			var cb := _gem_colors[fb]
			_edge_aa_a.append(a)
			_edge_aa_b.append(b)
			_edge_aa_colors.append(Color(
				(ca.r + cb.r) * 0.5, (ca.g + cb.g) * 0.5,
				(ca.b + cb.b) * 0.5, 0.65))

	_cached_draw_size = size


func _draw() -> void:
	if not _valid or _gem_cut == null or _gem_visual == null:
		return

	# Rebuild cached geometry if size changed since last build.
	if size != _cached_draw_size:
		_rebuild_scaled_geometry()

	# ---- Filled facets ----
	for i in _scaled_facets.size():
		if i < _gem_colors.size():
			draw_colored_polygon(_scaled_facets[i], _gem_colors[i])

	# ---- Pavilion extinction overlay ----
	if _pavilion_colors.size() > 0:
		for i in _scaled_pavilion.size():
			if i < _pavilion_colors.size():
				draw_colored_polygon(_scaled_pavilion[i], _pavilion_colors[i])

	# ---- Facet anti-aliasing edge lines ----
	for i in _edge_aa_a.size():
		draw_line(_edge_aa_a[i], _edge_aa_b[i], _edge_aa_colors[i], 0.5, true)

	# ---- Silhouette outline (always visible in designer) ----
	if _scaled_silhouette.size() >= 4:
		var ol_color := _gem_visual.outline_color
		if ol_color.a < 0.2:
			ol_color = Color(0, 0, 0, 0.5)
		var ol_width := _gem_visual.outline_width
		if ol_width < 0.1:
			ol_width = 0.5
		draw_polyline(_scaled_silhouette, ol_color, ol_width, true)

	# ---- Internal edge lines ----
	if _gem_visual.edge_width > 0.01:
		var edge_count := int(_scaled_edges.size() / 2.0)
		for i in edge_count:
			draw_line(_scaled_edges[i * 2], _scaled_edges[i * 2 + 1],
				_gem_visual.edge_color, _gem_visual.edge_width, true)
