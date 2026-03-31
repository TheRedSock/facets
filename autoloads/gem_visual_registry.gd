extends Node

## Loads GemVisualResource definitions from data/visuals/, generates cuts at
## startup, and provides lookup for the rendering layer.
##
## Runtime visuals use layered caches:
## - shared color / geometry / render bundles for both procedural and baked paths
## - a gameplay texture cache for the board's sprite-backed TileViews
##
## Depends on: GemCutGenerators, GemVisualResource, GemCutResource, GemRenderer.

const VISUAL_DATA_PATH := "res://data/visuals/"
const GAMEPLAY_BAKE_SUPERSAMPLE := 2

signal gameplay_texture_cache_rebuilt(profile: Dictionary)

var _visuals: Dictionary = {}          # StringName (visual_id / tile_id) -> GemVisualResource
var _cuts: Dictionary = {}             # StringName (cut_id) -> GemCutResource
var _tier_to_visual: Dictionary = {}   # int -> GemVisualResource (first match)
var _color_cache: Dictionary = {}      # StringName (cache_key) -> [PackedColorArray, PackedColorArray]
var _scaled_geometry_cache: Dictionary = {}  # String -> geometry bundle per cut_id + draw size
var _render_cache: Dictionary = {}      # String -> render bundle per cache key + draw size
var _gameplay_texture_cache: Dictionary = {}  # StringName -> Texture2D for current gameplay profile
var _gameplay_texture_profile: Dictionary = {}
var _bake_viewport: SubViewport
var _bake_view: GameplayGemBakeView
var _loaded: bool = false
var _shutting_down := false
var _bake_in_progress := false
var _bake_draw_size := Vector2i.ZERO
var _pending_bake_draw_size := Vector2i.ZERO
var _bake_queue: Array[StringName] = []
var _bake_current_tile_id: StringName = &""


func _ready() -> void:
	_load_visuals()
	_generate_cuts()


func _exit_tree() -> void:
	_shutting_down = true
	if RenderingServer.frame_post_draw.is_connected(_on_bake_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_bake_frame_post_draw)
	if is_instance_valid(_bake_view):
		_bake_view.clear_render_bundle()
	_clear_runtime_state()
	if is_instance_valid(_bake_viewport):
		_bake_viewport.free()
	_bake_viewport = null
	_bake_view = null


## Returns the visual definition for a tile, or null.
func get_visual(tile_id: StringName) -> GemVisualResource:
	return _visuals.get(tile_id, null)


## Returns the visual for a tier (first visual found at that tier via TileRegistry).
func get_visual_for_tier(tier: int) -> GemVisualResource:
	if _tier_to_visual.has(tier):
		return _tier_to_visual[tier]
	# Try to resolve via TileRegistry.
	if TileRegistry != null and TileRegistry.has_definitions():
		var ids := TileRegistry.get_ids_for_tier(tier)
		for id in ids:
			if _visuals.has(id):
				_tier_to_visual[tier] = _visuals[id]
				return _visuals[id]
	return null


## Returns the generated GemCutResource for a cut_id, or null.
func get_cut(cut_id: StringName) -> GemCutResource:
	return _cuts.get(cut_id, null)


## Returns the baked gameplay texture for a tile_id in the active gameplay profile.
## Falls back to the first matching tier visual when the exact tile_id is missing.
func get_gameplay_texture(tile_id: StringName, tier: int = -1) -> Texture2D:
	if _gameplay_texture_cache.has(tile_id):
		return _gameplay_texture_cache[tile_id]
	var fallback_tier := tier
	if fallback_tier < 0:
		fallback_tier = _resolve_visual_tier(tile_id)
	if fallback_tier > 0:
		return _gameplay_texture_cache.get(StringName("_tier_%d" % fallback_tier), null)
	return null


func get_gameplay_texture_profile() -> Dictionary:
	return _gameplay_texture_profile.duplicate(true)


func is_gameplay_texture_cache_current(draw_size: Vector2i) -> bool:
	return _is_gameplay_profile_current(draw_size) and not _bake_in_progress


## Ensures the gameplay texture cache exists for the requested board cell size.
## Safe to re-run on demand (e.g. after a future resolution/settings change).
func ensure_gameplay_texture_cache(draw_size: Vector2i) -> void:
	if _shutting_down:
		return
	if draw_size.x <= 0 or draw_size.y <= 0:
		return
	if _is_gameplay_profile_current(draw_size):
		return
	if _bake_in_progress:
		_pending_bake_draw_size = draw_size
		return

	var bake_render_size := _make_bake_render_size(draw_size)
	preload_runtime_assets([draw_size, bake_render_size])
	_ensure_bake_surface(bake_render_size)
	_gameplay_texture_cache.clear()
	_gameplay_texture_profile = {"cell_size": draw_size}
	_bake_draw_size = bake_render_size
	_bake_queue = []
	for tile_id in _visuals:
		_bake_queue.append(tile_id)
	_bake_in_progress = true
	_bake_current_tile_id = &""
	_begin_next_bake_step()


## Returns cached [facet_colors, pavilion_colors] for the given cache key.
## Computes and caches on first call; subsequent calls return the cached arrays.
## cache_key should be tile_id for normal gems, or a synthetic key for fallback paths.
func get_cached_colors(
	cache_key: StringName,
	cut: GemCutResource,
	visual: GemVisualResource,
) -> Array:
	if _color_cache.has(cache_key):
		return _color_cache[cache_key]
	var facet_colors := GemRenderer.compute_all_facet_colors(cut, visual)
	var pavilion_colors := GemRenderer.compute_pavilion_colors(cut, visual)
	var entry := [facet_colors, pavilion_colors]
	_color_cache[cache_key] = entry
	return entry


## Returns cached render data for a tile visual at the requested draw size.
## This shares scaled geometry across all TileViews of the same cut and pixel size,
## while still preserving per-tile-id color caches.
func get_cached_render_data(
	cache_key: StringName,
	cut: GemCutResource,
	visual: GemVisualResource,
	draw_size: Vector2i,
) -> Dictionary:
	var geometry := get_cached_scaled_geometry(cut, draw_size)
	var colors := get_cached_colors(cache_key, cut, visual)
	var render_key := _make_render_cache_key(cache_key, draw_size)
	if _render_cache.has(render_key):
		return _render_cache[render_key]

	var entry := {
		"geometry": geometry,
		"facet_colors": colors[0],
		"pavilion_colors": colors[1],
		"edge_aa_colors": _build_edge_aa_colors(geometry, colors[0]),
	}
	_render_cache[render_key] = entry
	return entry


## Returns cached scaled geometry for the given cut and pixel size.
func get_cached_scaled_geometry(cut: GemCutResource, draw_size: Vector2i) -> Dictionary:
	if cut == null:
		return {}
	var geometry_key := _make_scaled_geometry_key(cut.cut_id, draw_size)
	if _scaled_geometry_cache.has(geometry_key):
		return _scaled_geometry_cache[geometry_key]
	var geometry := _build_scaled_geometry(cut, draw_size)
	_scaled_geometry_cache[geometry_key] = geometry
	return geometry


## Explicit gameplay preload hook.  Keeps expensive first-use cache misses off the
## animation path by warming colors and scaled render bundles before the board animates.
func preload_runtime_assets(draw_sizes: Array[Vector2i] = []) -> void:
	_pre_warm_colors()
	for draw_size in draw_sizes:
		if draw_size.x <= 0 or draw_size.y <= 0:
			continue
		for tile_id in _visuals:
			var visual: GemVisualResource = _visuals[tile_id]
			var cut: GemCutResource = _cuts.get(visual.cut_id, null)
			if cut != null:
				get_cached_render_data(tile_id, cut, visual, draw_size)
				var tier := _resolve_visual_tier(tile_id)
				if tier > 0:
					get_cached_render_data(StringName("_tier_%d" % tier), cut, visual, draw_size)


## Clears the color cache.  Call if visual parameters change at runtime
## (e.g. from the Gem Designer export or debug tweaks).
func invalidate_color_cache() -> void:
	_color_cache.clear()
	_render_cache.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_profile.clear()


## Clears the scaled-geometry and render bundle caches.
func invalidate_render_cache() -> void:
	_scaled_geometry_cache.clear()
	_render_cache.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_profile.clear()


## Returns true if visuals have been loaded.
func has_visuals() -> bool:
	return _loaded and not _visuals.is_empty()


# ---- Internal ----


func _load_visuals() -> void:
	var dir := DirAccess.open(VISUAL_DATA_PATH)
	if dir == null:
		push_warning("GemVisualRegistry: Could not open %s — no visuals loaded" % VISUAL_DATA_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := VISUAL_DATA_PATH + file_name
			var resource = load(path)
			if resource is GemVisualResource:
				_visuals[resource.visual_id] = resource
		file_name = dir.get_next()
	dir.list_dir_end()

	_loaded = true
	if _visuals.is_empty():
		push_warning("GemVisualRegistry: No .tres visual definitions found in %s" % VISUAL_DATA_PATH)
	else:
		print("GemVisualRegistry: Loaded %d visual definitions" % _visuals.size())


func _generate_cuts() -> void:
	# Collect all unique cut_ids referenced by loaded visuals.
	var needed: Dictionary = {}
	for visual_id in _visuals:
		var vis: GemVisualResource = _visuals[visual_id]
		if vis.cut_id != &"":
			needed[vis.cut_id] = true

	# Generate each cut.
	for cut_id in needed:
		var cut := GemCutGenerators.generate(cut_id)
		if cut != null:
			_cuts[cut_id] = cut

	if not _cuts.is_empty():
		print("GemVisualRegistry: Generated %d gem cuts" % _cuts.size())


## Eagerly computes and caches facet colors for all loaded gem types.
func _pre_warm_colors() -> void:
	if not _color_cache.is_empty():
		return
	for tile_id in _visuals:
		var visual: GemVisualResource = _visuals[tile_id]
		var cut: GemCutResource = _cuts.get(visual.cut_id, null)
		if cut != null:
			get_cached_colors(tile_id, cut, visual)
			var tier := _resolve_visual_tier(tile_id)
			if tier > 0:
				get_cached_colors(StringName("_tier_%d" % tier), cut, visual)
	if not _color_cache.is_empty():
		print("GemVisualRegistry: Pre-warmed %d color caches" % _color_cache.size())


func _make_scaled_geometry_key(cut_id: StringName, draw_size: Vector2i) -> String:
	return "%s@%dx%d" % [String(cut_id), draw_size.x, draw_size.y]


func _make_render_cache_key(cache_key: StringName, draw_size: Vector2i) -> String:
	return "%s@%dx%d" % [String(cache_key), draw_size.x, draw_size.y]


func _build_scaled_geometry(cut: GemCutResource, draw_size: Vector2i) -> Dictionary:
	var size_v := Vector2(draw_size)
	var s := minf(size_v.x, size_v.y)
	var offset := (size_v - Vector2(s, s)) * 0.5

	var scaled_facets: Array[PackedVector2Array] = []
	scaled_facets.resize(cut.facet_count())
	for i in cut.facet_count():
		var verts := cut.facet_vertices[i]
		var scaled := PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		scaled_facets[i] = scaled

	var scaled_pavilion: Array[PackedVector2Array] = []
	scaled_pavilion.resize(cut.pavilion_count())
	for i in cut.pavilion_count():
		var verts := cut.pavilion_vertices[i]
		var scaled := PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		scaled_pavilion[i] = scaled

	var scaled_silhouette := PackedVector2Array()
	if cut.silhouette.size() >= 3:
		scaled_silhouette.resize(cut.silhouette.size() + 1)
		for j in cut.silhouette.size():
			scaled_silhouette[j] = cut.silhouette[j] * s + offset
		scaled_silhouette[cut.silhouette.size()] = scaled_silhouette[0]

	var scaled_edges := PackedVector2Array()
	for seg in cut.edge_segments:
		if seg.size() >= 2:
			scaled_edges.append(seg[0] * s + offset)
			scaled_edges.append(seg[1] * s + offset)

	var edge_aa_a := PackedVector2Array()
	var edge_aa_b := PackedVector2Array()
	var edge_aa_pairs := PackedInt32Array()
	if cut.edge_facet_a.size() == cut.edge_segments.size():
		for i in cut.edge_segments.size():
			var fa := cut.edge_facet_a[i]
			var fb := cut.edge_facet_b[i]
			if fa < 0 or fb < 0:
				continue
			var seg := cut.edge_segments[i]
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
			edge_aa_a.append(a)
			edge_aa_b.append(b)
			edge_aa_pairs.append(fa)
			edge_aa_pairs.append(fb)

	return {
		"facets": scaled_facets,
		"pavilion": scaled_pavilion,
		"silhouette": scaled_silhouette,
		"edges": scaled_edges,
		"edge_aa_a": edge_aa_a,
		"edge_aa_b": edge_aa_b,
		"edge_aa_pairs": edge_aa_pairs,
	}


func _build_edge_aa_colors(geometry: Dictionary, facet_colors: PackedColorArray) -> PackedColorArray:
	var edge_aa_colors := PackedColorArray()
	var edge_aa_pairs: PackedInt32Array = geometry.get("edge_aa_pairs", PackedInt32Array())
	var pair_count := int(edge_aa_pairs.size() / 2.0)
	edge_aa_colors.resize(pair_count)
	for i in pair_count:
		var fa := edge_aa_pairs[i * 2]
		var fb := edge_aa_pairs[i * 2 + 1]
		if fa < 0 or fb < 0 or fa >= facet_colors.size() or fb >= facet_colors.size():
			edge_aa_colors[i] = Color(0, 0, 0, 0)
			continue
		var ca := facet_colors[fa]
		var cb := facet_colors[fb]
		edge_aa_colors[i] = Color(
			(ca.r + cb.r) * 0.5,
			(ca.g + cb.g) * 0.5,
			(ca.b + cb.b) * 0.5,
			0.65
		)
	return edge_aa_colors


func _resolve_visual_tier(tile_id: StringName) -> int:
	if TileRegistry == null or not TileRegistry.has_definitions():
		return -1
	var tile_def := TileRegistry.get_definition(tile_id)
	if tile_def == null:
		return -1
	return tile_def.tier


func _is_gameplay_profile_current(draw_size: Vector2i) -> bool:
	if _gameplay_texture_cache.is_empty():
		return false
	return _gameplay_texture_profile.get("cell_size", Vector2i.ZERO) == draw_size


func _ensure_bake_surface(draw_size: Vector2i) -> void:
	if _bake_viewport == null:
		_bake_viewport = SubViewport.new()
		_bake_viewport.disable_3d = true
		_bake_viewport.transparent_bg = true
		_bake_viewport.msaa_2d = int(ProjectSettings.get_setting(
			"rendering/anti_aliasing/quality/msaa_2d",
			0
		))
		_bake_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_bake_viewport)

		_bake_view = GameplayGemBakeView.new()
		_bake_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bake_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bake_viewport.add_child(_bake_view)

	_bake_viewport.size = draw_size


func _begin_next_bake_step() -> void:
	if _shutting_down:
		return
	while not _bake_queue.is_empty():
		var tile_id: StringName = _bake_queue.pop_front()
		var visual: GemVisualResource = _visuals.get(tile_id, null)
		if visual == null:
			continue
		var cut: GemCutResource = _cuts.get(visual.cut_id, null)
		if cut == null:
			continue
		var render_data := get_cached_render_data(tile_id, cut, visual, _bake_draw_size)
		_bake_current_tile_id = tile_id
		_bake_view.update_render_bundle(visual, render_data)
		_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.frame_post_draw.connect(_on_bake_frame_post_draw, CONNECT_ONE_SHOT)
		return
	_finish_bake_queue()


func _on_bake_frame_post_draw() -> void:
	if _shutting_down or not _bake_in_progress or not is_instance_valid(_bake_viewport):
		return
	var image := _bake_viewport.get_texture().get_image()
	var texture: Texture2D = null
	if image != null:
		var target_size: Vector2i = _gameplay_texture_profile.get("cell_size", _bake_draw_size)
		if target_size.x > 0 and target_size.y > 0 and image.get_size() != target_size:
			image.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)
		texture = ImageTexture.create_from_image(image)
	_gameplay_texture_cache[_bake_current_tile_id] = texture

	var tier := _resolve_visual_tier(_bake_current_tile_id)
	if tier > 0 and not _gameplay_texture_cache.has(StringName("_tier_%d" % tier)):
		_gameplay_texture_cache[StringName("_tier_%d" % tier)] = texture

	_bake_current_tile_id = &""
	_begin_next_bake_step()


func _finish_bake_queue() -> void:
	_bake_in_progress = false
	_bake_current_tile_id = &""
	if _shutting_down:
		return
	gameplay_texture_cache_rebuilt.emit(get_gameplay_texture_profile())
	if _pending_bake_draw_size != Vector2i.ZERO:
		var next_draw_size := _pending_bake_draw_size
		_pending_bake_draw_size = Vector2i.ZERO
		if not _is_gameplay_profile_current(next_draw_size):
			ensure_gameplay_texture_cache(next_draw_size)


func _clear_runtime_state() -> void:
	_pending_bake_draw_size = Vector2i.ZERO
	_bake_draw_size = Vector2i.ZERO
	_bake_queue.clear()
	_bake_current_tile_id = &""
	_bake_in_progress = false
	_gameplay_texture_profile.clear()
	_gameplay_texture_cache.clear()
	_render_cache.clear()
	_scaled_geometry_cache.clear()
	_color_cache.clear()
	_tier_to_visual.clear()
	_cuts.clear()
	_visuals.clear()
	_loaded = false


func _make_bake_render_size(draw_size: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(draw_size.x * GAMEPLAY_BAKE_SUPERSAMPLE, 1),
		maxi(draw_size.y * GAMEPLAY_BAKE_SUPERSAMPLE, 1)
	)
