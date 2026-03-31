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
			draw_colored_polygon(facets[i], _gem_colors[i])
			if i < unit_facets.size() and i < facet_normals.size():
				_draw_texture_overlay(facets[i], unit_facets[i], facet_normals[i], _gem_colors[i])

	if _pavilion_colors.size() > 0:
		for i in pavilion.size():
			if i < _pavilion_colors.size():
				draw_colored_polygon(pavilion[i], _pavilion_colors[i])

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

	var uvs := GemRenderer.build_texture_uvs(
		unit_points,
		facet_normal,
		_gem_visual
	)
	var modulate := GemRenderer.compute_texture_overlay_color(facet_color, _gem_visual)
	var colors := PackedColorArray()
	colors.resize(facet_points.size())
	for i in facet_points.size():
		colors[i] = modulate
	draw_polygon(facet_points, colors, uvs, _gem_visual.color_texture)
