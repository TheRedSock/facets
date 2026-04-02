class_name GameplayGemBakeView
extends Control

## Hidden bake surface used to render one gameplay gem into a texture cache entry.
## This preserves the runtime-generated gem pipeline while letting gameplay animate
## sprites instead of re-drawing all polygons every frame.

var _gem_visual: GemVisualResource = null
var _gem_colors: PackedColorArray = PackedColorArray()
var _pavilion_colors: PackedColorArray = PackedColorArray()
var _edge_aa_colors: PackedColorArray = PackedColorArray()
var _render_geometry: Dictionary = {}
var _valid := false

const MIN_DRAWABLE_POLYGON_AREA := 0.5


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func update_render_bundle(visual: GemVisualResource, render_data: Dictionary) -> void:
	_gem_visual = visual
	_render_geometry = render_data.get("geometry", {})
	_gem_colors = render_data.get("facet_colors", PackedColorArray())
	_pavilion_colors = render_data.get("pavilion_colors", PackedColorArray())
	_edge_aa_colors = render_data.get("edge_aa_colors", PackedColorArray())
	_valid = _gem_visual != null and not _render_geometry.is_empty()
	queue_redraw()


func clear_render_bundle() -> void:
	_gem_visual = null
	_render_geometry = {}
	_gem_colors = PackedColorArray()
	_pavilion_colors = PackedColorArray()
	_edge_aa_colors = PackedColorArray()
	_valid = false


func _draw() -> void:
	if not _valid or _gem_visual == null:
		return

	var facets: Array = _render_geometry.get("facets", [])
	var unit_facets: Array = _render_geometry.get("unit_facets", [])
	var facet_normals: Array = _render_geometry.get("facet_normals", [])
	var pavilion: Array = _render_geometry.get("pavilion", [])
	var silhouette: PackedVector2Array = _render_geometry.get("silhouette", PackedVector2Array())
	var edges: PackedVector2Array = _render_geometry.get("edges", PackedVector2Array())
	var edge_aa_a: PackedVector2Array = _render_geometry.get("edge_aa_a", PackedVector2Array())
	var edge_aa_b: PackedVector2Array = _render_geometry.get("edge_aa_b", PackedVector2Array())

	for i in facets.size():
		if i < _gem_colors.size():
			var safe_facet := _sanitize_polygon(facets[i])
			if safe_facet.size() < 3:
				continue
			draw_colored_polygon(safe_facet, _gem_colors[i])
			if i < unit_facets.size() and i < facet_normals.size():
				_draw_texture_overlay(facets[i], unit_facets[i], facet_normals[i], _gem_colors[i])

	if _pavilion_colors.size() > 0:
		for i in pavilion.size():
			if i < _pavilion_colors.size():
				var safe_pavilion := _sanitize_polygon(pavilion[i])
				if safe_pavilion.size() < 3:
					continue
				draw_colored_polygon(safe_pavilion, _pavilion_colors[i])

	for i in edge_aa_a.size():
		draw_line(edge_aa_a[i], edge_aa_b[i], _edge_aa_colors[i], 0.5, true)

	if _gem_visual.edge_width > 0.01:
		var edge_count := int(edges.size() / 2.0)
		for i in edge_count:
			draw_line(edges[i * 2], edges[i * 2 + 1],
				_gem_visual.edge_color, _gem_visual.edge_width, true)


func _draw_texture_overlay(
	facet_points: PackedVector2Array,
	unit_points: PackedVector2Array,
	facet_normal: Vector3,
	facet_color: Color,
) -> void:
	if not _gem_visual.use_texture or _gem_visual.color_texture == null:
		return
	if unit_points.size() != facet_points.size():
		return

	var sanitized := _sanitize_polygon_pair(facet_points, unit_points)
	var safe_facet: PackedVector2Array = sanitized.get("facet_points", PackedVector2Array())
	var safe_unit: PackedVector2Array = sanitized.get("unit_points", PackedVector2Array())
	if safe_facet.size() < 3 or safe_unit.size() != safe_facet.size():
		return

	var uvs := GemRenderer.build_texture_uvs(
		safe_unit,
		facet_normal,
		_gem_visual
	)
	var modulate := GemRenderer.compute_texture_overlay_color(facet_color, _gem_visual)
	var colors := PackedColorArray()
	colors.resize(safe_facet.size())
	for i in safe_facet.size():
		colors[i] = modulate
	draw_polygon(safe_facet, colors, uvs, _gem_visual.color_texture)


func _sanitize_polygon(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	var cleaned := PackedVector2Array()
	for point in points:
		if cleaned.is_empty() or point.distance_squared_to(cleaned[cleaned.size() - 1]) > 0.0001:
			cleaned.append(point)
	if cleaned.size() >= 2 and cleaned[0].distance_squared_to(cleaned[cleaned.size() - 1]) <= 0.0001:
		cleaned.remove_at(cleaned.size() - 1)
	if cleaned.size() < 3:
		return PackedVector2Array()
	if _polygon_area_abs(cleaned) < MIN_DRAWABLE_POLYGON_AREA:
		return PackedVector2Array()
	if Geometry2D.triangulate_polygon(cleaned).size() < 3:
		return PackedVector2Array()
	return cleaned


func _sanitize_polygon_pair(
	facet_points: PackedVector2Array,
	unit_points: PackedVector2Array,
) -> Dictionary:
	if facet_points.size() != unit_points.size() or facet_points.size() < 3:
		return {}
	var facet_clean := PackedVector2Array()
	var unit_clean := PackedVector2Array()
	for i in facet_points.size():
		var facet_point := facet_points[i]
		if facet_clean.is_empty() or facet_point.distance_squared_to(facet_clean[facet_clean.size() - 1]) > 0.0001:
			facet_clean.append(facet_point)
			unit_clean.append(unit_points[i])
	if facet_clean.size() >= 2 and facet_clean[0].distance_squared_to(facet_clean[facet_clean.size() - 1]) <= 0.0001:
		facet_clean.remove_at(facet_clean.size() - 1)
		unit_clean.remove_at(unit_clean.size() - 1)
	if facet_clean.size() < 3:
		return {}
	if _polygon_area_abs(facet_clean) < MIN_DRAWABLE_POLYGON_AREA:
		return {}
	if Geometry2D.triangulate_polygon(facet_clean).size() < 3:
		return {}
	return {
		"facet_points": facet_clean,
		"unit_points": unit_clean,
	}


func _polygon_area_abs(points: PackedVector2Array) -> float:
	var doubled_area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		doubled_area += (a.x * b.y) - (b.x * a.y)
	return absf(doubled_area) * 0.5
