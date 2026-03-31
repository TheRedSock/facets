class_name TileView
extends Control

## The grid cell this tile currently represents.
var cell: Vector2i = Vector2i.ZERO

## The tile's identifier and tier for display.
var tile_id: StringName = &""
var tier: int = 0

var _label: Label
var _background: ColorRect
var _sprite_texture: TextureRect
var _outline_overlay: Control

const GAME_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const DEFAULT_GAME_OUTLINE_WIDTH := 0.5

## Cached procedural gem data (set by _update_visual, consumed by _draw).
var _gem_cut: GemCutResource = null
var _gem_visual: GemVisualResource = null
var _visual_cache_key: StringName = &""
var _gem_colors: PackedColorArray = PackedColorArray()
var _pavilion_colors: PackedColorArray = PackedColorArray()
var _edge_aa_colors: PackedColorArray = PackedColorArray()
var _use_procedural: bool = false

## Shared scaled geometry bundle from GemVisualRegistry.
var _render_geometry: Dictionary = {}
var use_gameplay_texture_cache := false
var _outline_cut: GemCutResource = null
var _outline_geometry: Dictionary = {}
var _use_runtime_outline := false


func _ready() -> void:
	# All mouse input is handled by BoardScene, not individual tiles
	mouse_filter = MOUSE_FILTER_IGNORE

	# Build visual structure programmatically
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_background.color = Color("94a3b8")
	_background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_background)

	_sprite_texture = TextureRect.new()
	_sprite_texture.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_sprite_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_sprite_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite_texture.mouse_filter = MOUSE_FILTER_IGNORE
	_sprite_texture.visible = false
	add_child(_sprite_texture)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.grow_horizontal = GROW_DIRECTION_BOTH
	_label.grow_vertical = GROW_DIRECTION_BOTH
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_label)

	_outline_overlay = Control.new()
	_outline_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_outline_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_outline_overlay.draw.connect(_draw_outline_overlay)
	add_child(_outline_overlay)

	# Scale and rotation pivot at the tile centre so animations grow symmetrically.
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	if GemVisualRegistry != null:
		GemVisualRegistry.gameplay_texture_cache_rebuilt.connect(_on_gameplay_texture_cache_rebuilt)

	_update_visual()


func _exit_tree() -> void:
	if GemVisualRegistry != null and GemVisualRegistry.gameplay_texture_cache_rebuilt.is_connected(_on_gameplay_texture_cache_rebuilt):
		GemVisualRegistry.gameplay_texture_cache_rebuilt.disconnect(_on_gameplay_texture_cache_rebuilt)
	_clear_procedural_state()
	_clear_runtime_outline()
	if _sprite_texture != null:
		_sprite_texture.texture = null


func configure(tile: TileState, new_cell: Vector2i) -> void:
	cell = new_cell
	tile_id = tile.tile_id
	tier = tile.tier
	if is_inside_tree():
		_update_visual()


func configure_from_data(p_tile_id: StringName, p_tier: int, p_cell: Vector2i) -> void:
	cell = p_cell
	tile_id = p_tile_id
	tier = p_tier
	if is_inside_tree():
		_update_visual()


func show_upgrade_full(new_tier: int, new_tile_id: StringName) -> void:
	tier = new_tier
	tile_id = new_tile_id
	if is_inside_tree():
		_update_visual()


func _update_visual() -> void:
	if _label == null:
		return

	if _try_gameplay_texture_visual():
		return

	# ---- Priority 1: Procedural gem rendering ----
	if _try_procedural_visual():
		return

	# ---- Priority 2: Coloured rectangle fallback ----
	_clear_procedural_state()
	_clear_runtime_outline()
	_use_procedural = false
	_background.visible = true
	_sprite_texture.visible = false
	_sprite_texture.texture = null
	_background.color = _get_color()
	_label.visible = false
	queue_redraw()


func _try_gameplay_texture_visual() -> bool:
	if not use_gameplay_texture_cache or GemVisualRegistry == null:
		return false
	var texture := GemVisualRegistry.get_gameplay_texture(tile_id, tier)
	if texture == null:
		return false

	var visual_bundle := _resolve_visual_bundle()
	_clear_procedural_state()
	_use_procedural = false
	_background.visible = false
	_label.visible = false
	_sprite_texture.texture = texture
	_sprite_texture.visible = true
	if not visual_bundle.is_empty():
		_setup_runtime_outline(visual_bundle["cut"])
	else:
		_clear_runtime_outline()
	return true


## Attempts to set up procedural gem rendering.  Returns true on success.
func _try_procedural_visual() -> bool:
	var visual_bundle := _resolve_visual_bundle()
	if visual_bundle.is_empty():
		return false

	var cache_key: StringName = visual_bundle["cache_key"]
	var visual: GemVisualResource = visual_bundle["visual"]
	var cut: GemCutResource = visual_bundle["cut"]

	# Track whether the cut changed — if recycling as the same gem type,
	# the scaled geometry is still valid and we can skip the expensive rebuild.
	var cut_changed := (_gem_cut != cut)
	var cache_key_changed := (_visual_cache_key != cache_key)

	_visual_cache_key = cache_key
	_gem_visual = visual
	_gem_cut = cut

	_use_procedural = true
	_clear_runtime_outline()

	# Hide the background — _draw() handles rendering.
	_background.visible = false
	_sprite_texture.visible = false
	_sprite_texture.texture = null

	# Hide label — procedural gems need no text overlay.
	_label.visible = false

	_refresh_render_cache(cut_changed or cache_key_changed)
	return true


func _clear_procedural_state() -> void:
	_gem_cut = null
	_gem_visual = null
	_visual_cache_key = &""
	_render_geometry = {}
	_gem_colors = PackedColorArray()
	_pavilion_colors = PackedColorArray()
	_edge_aa_colors = PackedColorArray()


func _clear_runtime_outline() -> void:
	_outline_cut = null
	_outline_geometry = {}
	_use_runtime_outline = false
	if _outline_overlay != null:
		_outline_overlay.queue_redraw()


func _setup_runtime_outline(cut: GemCutResource) -> void:
	_outline_cut = cut
	_use_runtime_outline = true
	_refresh_runtime_outline()


func _resolve_visual_bundle() -> Dictionary:
	if GemVisualRegistry == null or not GemVisualRegistry.has_visuals():
		return {}
	var cache_key: StringName = tile_id
	var visual := GemVisualRegistry.get_visual(tile_id)
	if visual == null:
		visual = GemVisualRegistry.get_visual_for_tier(tier)
		cache_key = StringName("_tier_%d" % tier)
	if visual == null:
		return {}
	var cut := GemVisualRegistry.get_cut(visual.cut_id)
	if cut == null:
		return {}
	return {
		"cache_key": cache_key,
		"visual": visual,
		"cut": cut,
	}


func _draw() -> void:
	if not _use_procedural or _gem_cut == null or _gem_visual == null:
		return

	var facets: Array = _render_geometry.get("facets", [])
	var unit_facets: Array = _render_geometry.get("unit_facets", [])
	var facet_normals: Array = _render_geometry.get("facet_normals", [])
	var pavilion: Array = _render_geometry.get("pavilion", [])
	var silhouette: PackedVector2Array = _render_geometry.get("silhouette", PackedVector2Array())
	var edges: PackedVector2Array = _render_geometry.get("edges", PackedVector2Array())
	var edge_aa_a: PackedVector2Array = _render_geometry.get("edge_aa_a", PackedVector2Array())
	var edge_aa_b: PackedVector2Array = _render_geometry.get("edge_aa_b", PackedVector2Array())
	var low_detail := _is_low_detail_enabled()

	# ---- Draw filled facets ----
	for i in facets.size():
		if i < _gem_colors.size():
			draw_colored_polygon(facets[i], _gem_colors[i])
			if i < unit_facets.size() and i < facet_normals.size():
				_draw_texture_overlay(facets[i], unit_facets[i], facet_normals[i], _gem_colors[i])

	# ---- Draw pavilion extinction overlay ----
	if not low_detail and _pavilion_colors.size() > 0:
		for i in pavilion.size():
			if i < _pavilion_colors.size():
				draw_colored_polygon(pavilion[i], _pavilion_colors[i])

	# ---- Draw facet anti-aliasing edge lines ----
	if not low_detail:
		for i in edge_aa_a.size():
			draw_line(edge_aa_a[i], edge_aa_b[i], _edge_aa_colors[i], 0.5, true)

	# ---- Draw silhouette outline ----
	if DebugFlags.gem_silhouette_outline and silhouette.size() >= 4:
		draw_polyline(silhouette, GAME_OUTLINE_COLOR, _get_game_outline_width(), true)

	# ---- Draw internal edge lines ----
	if not low_detail and _gem_visual.edge_width > 0.01:
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
	var overlay_color := GemRenderer.compute_texture_overlay_color(facet_color, _gem_visual)
	var colors := PackedColorArray()
	colors.resize(facet_points.size())
	for i in facet_points.size():
		colors[i] = overlay_color
	draw_polygon(facet_points, colors, uvs, _gem_visual.color_texture)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	if _use_procedural:
		_refresh_render_cache()
	elif _use_runtime_outline:
		_refresh_runtime_outline()


func _refresh_render_cache(force_redraw: bool = true) -> void:
	if not _use_procedural or _gem_cut == null or _gem_visual == null:
		return
	var draw_size := Vector2i(maxi(int(round(size.x)), 1), maxi(int(round(size.y)), 1))
	var render_data := GemVisualRegistry.get_cached_render_data(
		_visual_cache_key, _gem_cut, _gem_visual, draw_size)
	_render_geometry = render_data.get("geometry", {})
	_gem_colors = render_data.get("facet_colors", PackedColorArray())
	_pavilion_colors = render_data.get("pavilion_colors", PackedColorArray())
	_edge_aa_colors = render_data.get("edge_aa_colors", PackedColorArray())
	if force_redraw:
		queue_redraw()


func _refresh_runtime_outline() -> void:
	if not _use_runtime_outline or _outline_cut == null:
		return
	var draw_size := Vector2i(maxi(int(round(size.x)), 1), maxi(int(round(size.y)), 1))
	_outline_geometry = GemVisualRegistry.get_cached_scaled_geometry(_outline_cut, draw_size)
	if _outline_overlay != null:
		_outline_overlay.queue_redraw()


func _draw_outline_overlay() -> void:
	if not _use_runtime_outline:
		return
	if not DebugFlags.gem_silhouette_outline:
		return
	var silhouette: PackedVector2Array = _outline_geometry.get("silhouette", PackedVector2Array())
	if silhouette.size() < 4:
		return
	_outline_overlay.draw_polyline(silhouette, GAME_OUTLINE_COLOR, _get_game_outline_width(), true)


func refresh_debug_visuals() -> void:
	queue_redraw()
	if _outline_overlay != null:
		_outline_overlay.queue_redraw()


func _is_low_detail_enabled() -> bool:
	return DebugFlags != null and DebugFlags.gem_low_detail_gameplay


func _get_game_outline_width() -> float:
	if DebugFlags != null and DebugFlags.gem_outline_width_override >= 0.0:
		return DebugFlags.gem_outline_width_override
	return DEFAULT_GAME_OUTLINE_WIDTH


func _on_gameplay_texture_cache_rebuilt(_profile: Dictionary) -> void:
	if use_gameplay_texture_cache and is_inside_tree():
		_update_visual()


func _get_color() -> Color:
	# Use TileRegistry colors if available, fall back to hardcoded palette
	if TileRegistry != null and TileRegistry.has_definitions():
		return TileRegistry.get_tier_color(tier)
	var palette := {
		1: Color("f8fafc"), 2: Color("a855f7"), 3: Color("84cc16"), 4: Color("f97316"),
		5: Color("3b82f6"), 6: Color("10b981"), 7: Color("ef4444"), 8: Color("f0f0ff"),
	}
	return palette.get(tier, Color("94a3b8"))
