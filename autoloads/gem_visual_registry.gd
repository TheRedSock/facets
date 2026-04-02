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
const GAMEPLAY_BAKE_BACKEND_2D_ONLY := &"2d_only"
const GAMEPLAY_BAKE_BACKEND_3D_ONLY := &"3d_only"
const GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED := &"offline_traced"
const GAMEPLAY_BAKE_BACKEND_HYBRID := &"hybrid"
const GAMEPLAY_VARIANT_TYPE_LIGHTING := &"lighting"
const GAMEPLAY_VARIANT_TYPE_ROTATION := &"rotation"
const GAMEPLAY_LIGHTING_GRID_SIZE := Vector2i(5, 5)
const GAMEPLAY_BASE_ROTATION_VIEW_COUNT := 6
const GAMEPLAY_ROTATION_DEFAULT_AXIS_STEPS := 0
const GAMEPLAY_ROTATION_DEFAULT_STEP_DEGREES := 18.0
const GAMEPLAY_LIGHTING_SWEEP_X_DEGREES := 46.0
const GAMEPLAY_LIGHTING_SWEEP_Y_DEGREES := 30.0
const GameplayBakeBackendOfflineTracedScript = preload("res://scenes/tile/gem_gameplay_bake_backend_offline_traced.gd")

signal gameplay_texture_cache_rebuilt(profile: Dictionary)
signal gameplay_texture_bake_progress(progress: Dictionary)

var _visuals: Dictionary = {}          # StringName (visual_id / tile_id) -> GemVisualResource
var _cuts: Dictionary = {}             # StringName (cut_id) -> GemCutResource
var _cut_variants: Dictionary = {}     # String -> rotated GemCutResource per cut_id + rotation
var _tier_to_visual: Dictionary = {}   # int -> GemVisualResource (first match)
var _color_cache: Dictionary = {}      # StringName (cache_key) -> [PackedColorArray, PackedColorArray]
var _scaled_geometry_cache: Dictionary = {}  # String -> geometry bundle per cut_id + draw size
var _render_cache: Dictionary = {}      # String -> render bundle per cache key + draw size
var _gameplay_texture_cache: Dictionary = {}  # StringName composite variant key -> Texture2D
var _gameplay_texture_metadata_cache: Dictionary = {}  # StringName composite variant key -> metadata
var _gameplay_texture_profile: Dictionary = {}
var _gameplay_bake_backends: Dictionary = {}  # StringName -> GemGameplayBakeBackend
var _loaded: bool = false
var _shutting_down := false
var _bake_in_progress := false
var _bake_draw_size := Vector2i.ZERO
var _pending_bake_draw_size := Vector2i.ZERO
var _pending_bake_tile_scope: PackedStringArray = PackedStringArray()
var _bake_step_scheduled := false
var _bake_queue: Array[Dictionary] = []
var _bake_current_tile_id: StringName = &""
var _current_bake_request: Dictionary = {}
var _bake_total_requests := 0
var _bake_completed_requests := 0
var _gameplay_bake_backend_preference: StringName = GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED
var _gameplay_runtime_bake_fallback_enabled := false
var _last_gameplay_bake_report: Dictionary = {}


func _ready() -> void:
	_load_visuals()
	_generate_cuts()
	_initialize_bake_backends()


func _exit_tree() -> void:
	_shutting_down = true
	_shutdown_bake_backends()
	_clear_runtime_state()


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


func get_visual_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for tile_id in _visuals.keys():
		ids.append(tile_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var tier_a := _resolve_visual_tier(a)
		var tier_b := _resolve_visual_tier(b)
		if tier_a != tier_b:
			if tier_a < 0:
				return false
			if tier_b < 0:
				return true
			return tier_a < tier_b
		return String(a) < String(b)
	)
	return ids


## Returns the generated GemCutResource for a cut_id, or null.
func get_cut(cut_id: StringName) -> GemCutResource:
	return _cuts.get(cut_id, null)


## Returns the effective cut for a visual, including any per-visual rotation.
func get_visual_cut(visual: GemVisualResource) -> GemCutResource:
	return get_visual_cut_with_offset(visual, 0.0)


func get_visual_cut_with_offset(
	visual: GemVisualResource,
	additional_rotation_degrees: float = 0.0,
) -> GemCutResource:
	if visual == null:
		return null
	var base_cut: GemCutResource = _cuts.get(visual.cut_id, null)
	if base_cut == null:
		return null
	var total_rotation := visual.rotation_degrees + additional_rotation_degrees
	if is_zero_approx(total_rotation) and base_cut.orientation_fit_axis_aligned_scale >= 0.999:
		return base_cut

	var variant_key := _make_cut_variant_key(visual.cut_id, total_rotation)
	if _cut_variants.has(variant_key):
		return _cut_variants[variant_key]

	var rotated_cut := GemCutBuilders.create_visual_variant(base_cut, total_rotation)
	if rotated_cut != null:
		_cut_variants[variant_key] = rotated_cut
	return rotated_cut


## Returns the baked gameplay texture for a tile_id in the active gameplay profile.
## Falls back to the first matching tier visual when the exact tile_id is missing.
func get_gameplay_texture(tile_id: StringName, tier: int = -1) -> Texture2D:
	return get_gameplay_lighting_texture(tile_id, tier, _get_default_lighting_bin())


func get_gameplay_lighting_texture(
	tile_id: StringName,
	tier: int,
	lighting_bin: Vector2i,
) -> Texture2D:
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return null
	return _gameplay_texture_cache.get(
		_make_gameplay_variant_cache_key(base_key, GAMEPLAY_VARIANT_TYPE_LIGHTING, lighting_bin),
		null
	)


func get_gameplay_rotation_texture(
	tile_id: StringName,
	tier: int,
	rotation_bin: int,
) -> Texture2D:
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return null
	return _gameplay_texture_cache.get(
		_make_gameplay_variant_cache_key(base_key, GAMEPLAY_VARIANT_TYPE_ROTATION, Vector2i(-1, -1), rotation_bin),
		null
	)


func get_gameplay_lighting_blend_set(
	tile_id: StringName,
	tier: int,
	normalized_position: Vector2,
) -> Array[Dictionary]:
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return []
	var blend_entries := compute_gameplay_lighting_blend(normalized_position)
	var textured_entries: Array[Dictionary] = []
	for entry in blend_entries:
		var texture := get_gameplay_lighting_texture(
			tile_id,
			tier,
			entry.get("lighting_bin", _get_default_lighting_bin())
		)
		if texture == null:
			continue
		textured_entries.append({
			"texture": texture,
			"weight": entry.get("weight", 0.0),
			"lighting_bin": entry.get("lighting_bin", Vector2i.ZERO),
			"metadata": _get_gameplay_variant_metadata(
				base_key,
				GAMEPLAY_VARIANT_TYPE_LIGHTING,
				entry.get("lighting_bin", _get_default_lighting_bin())
			),
		})
	return textured_entries


func get_gameplay_rotation_blend_set(
	tile_id: StringName,
	tier: int,
	rotation_progress: float,
) -> Array[Dictionary]:
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return []
	var blend_entries := compute_gameplay_rotation_blend(rotation_progress)
	var textured_entries: Array[Dictionary] = []
	for entry in blend_entries:
		var texture := get_gameplay_rotation_texture(
			tile_id,
			tier,
			entry.get("rotation_bin", 0)
		)
		if texture == null:
			continue
		textured_entries.append({
			"texture": texture,
			"weight": entry.get("weight", 0.0),
			"rotation_bin": entry.get("rotation_bin", 0),
			"metadata": _get_gameplay_variant_metadata(
				base_key,
				GAMEPLAY_VARIANT_TYPE_ROTATION,
				Vector2i(-1, -1),
				entry.get("rotation_bin", 0)
			),
		})
	return textured_entries


func compute_gameplay_lighting_blend(normalized_position: Vector2) -> Array[Dictionary]:
	var grid := GAMEPLAY_LIGHTING_GRID_SIZE
	var clamped := Vector2(clampf(normalized_position.x, 0.0, 1.0), clampf(normalized_position.y, 0.0, 1.0))
	if grid.x <= 1 or grid.y <= 1:
		return [{
			"lighting_bin": Vector2i.ZERO,
			"weight": 1.0,
		}]
	var scaled_x := clamped.x * float(grid.x - 1)
	var scaled_y := clamped.y * float(grid.y - 1)
	var x0 := clampi(int(floor(scaled_x)), 0, grid.x - 1)
	var y0 := clampi(int(floor(scaled_y)), 0, grid.y - 1)
	var x1 := mini(x0 + 1, grid.x - 1)
	var y1 := mini(y0 + 1, grid.y - 1)
	var tx := scaled_x - float(x0)
	var ty := scaled_y - float(y0)
	var raw_entries := [
		{"lighting_bin": Vector2i(x0, y0), "weight": (1.0 - tx) * (1.0 - ty)},
		{"lighting_bin": Vector2i(x1, y0), "weight": tx * (1.0 - ty)},
		{"lighting_bin": Vector2i(x0, y1), "weight": (1.0 - tx) * ty},
		{"lighting_bin": Vector2i(x1, y1), "weight": tx * ty},
	]
	return _merge_variant_weight_entries(raw_entries, "lighting_bin")


func compute_gameplay_rotation_blend(rotation_progress: float) -> Array[Dictionary]:
	var rotation_view_count := _get_default_rotation_view_count()
	if rotation_view_count <= 1:
		return [{
			"rotation_bin": 0,
			"weight": 1.0,
		}]
	var wrapped := fposmod(rotation_progress, 1.0)
	var scaled := wrapped * float(rotation_view_count)
	var low_bin := int(floor(scaled)) % rotation_view_count
	var frac: float = scaled - floor(scaled)
	var high_bin := (low_bin + 1) % rotation_view_count
	if is_zero_approx(frac):
		return [{
			"rotation_bin": low_bin,
			"weight": 1.0,
		}]
	return [
		{"rotation_bin": low_bin, "weight": 1.0 - frac},
		{"rotation_bin": high_bin, "weight": frac},
	]


func get_gameplay_variant_settings() -> Dictionary:
	return {
		"lighting_grid_size": GAMEPLAY_LIGHTING_GRID_SIZE,
		"rotation_bin_count": _get_default_rotation_view_count(),
		"rotation_views": get_gameplay_rotation_view_descriptors(),
		"default_lighting_bin": _get_default_lighting_bin(),
	}


func get_gameplay_rotation_view_descriptors(options: Dictionary = {}) -> Array[Dictionary]:
	var suite := _build_rotation_view_suite(options)
	var descriptors: Array[Dictionary] = []
	for rotation_bin in suite.size():
		var view: Dictionary = suite[rotation_bin]
		descriptors.append({
			"rotation_bin": rotation_bin,
			"label": String(view.get("label", "rot_%02d" % rotation_bin)),
			"axis": view.get("axis", &""),
			"view_pitch_degrees": float(view.get("view_pitch_degrees", 0.0)),
			"view_yaw_degrees": float(view.get("view_yaw_degrees", 0.0)),
			"view_roll_degrees": float(view.get("view_roll_degrees", 0.0)),
		})
	return descriptors


func compute_gameplay_light_dir(lighting_bin: Vector2i) -> Vector3:
	return _compute_variant_light_dir(lighting_bin)


func build_gameplay_bake_requests_for_tile(
	tile_id: StringName,
	draw_size: Vector2i,
	target_size: Vector2i = Vector2i.ZERO,
	variant_options: Dictionary = {},
) -> Array[Dictionary]:
	var visual := get_visual(tile_id)
	if visual == null:
		return []
	var cut := get_visual_cut(visual)
	if cut == null:
		return []
	if target_size == Vector2i.ZERO:
		target_size = draw_size
	return _build_gameplay_bake_requests(tile_id, visual, cut, draw_size, target_size, variant_options)


func _resolve_gameplay_texture_base_key(tile_id: StringName, tier: int = -1) -> StringName:
	if _gameplay_texture_cache.has(_make_gameplay_variant_cache_key(
		tile_id,
		GAMEPLAY_VARIANT_TYPE_LIGHTING,
		_get_default_lighting_bin()
	)):
		return tile_id
	var fallback_tier := tier
	if fallback_tier < 0:
		fallback_tier = _resolve_visual_tier(tile_id)
	if fallback_tier > 0:
		var tier_key := StringName("_tier_%d" % fallback_tier)
		if _gameplay_texture_cache.has(_make_gameplay_variant_cache_key(
			tier_key,
			GAMEPLAY_VARIANT_TYPE_LIGHTING,
			_get_default_lighting_bin()
		)):
			return tier_key
	return &""


func get_gameplay_texture_profile() -> Dictionary:
	return _gameplay_texture_profile.duplicate(true)


func set_gameplay_bake_backend_preference(preference: StringName) -> void:
	preference = GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED
	if _gameplay_bake_backend_preference == preference:
		return
	_gameplay_bake_backend_preference = preference
	_gameplay_texture_cache.clear()
	_gameplay_texture_profile.clear()
	_last_gameplay_bake_report.clear()


func get_gameplay_bake_backend_preference() -> StringName:
	return _gameplay_bake_backend_preference


func set_gameplay_runtime_bake_fallback_enabled(enabled: bool) -> void:
	_gameplay_runtime_bake_fallback_enabled = false


func is_gameplay_runtime_bake_fallback_enabled() -> bool:
	return _gameplay_runtime_bake_fallback_enabled


func get_last_gameplay_bake_report() -> Dictionary:
	return _last_gameplay_bake_report.duplicate(true)


func is_gameplay_texture_cache_current(
	draw_size: Vector2i,
	tile_scope = [],
) -> bool:
	return _is_gameplay_profile_current(draw_size, tile_scope) and not _bake_in_progress


## Ensures the gameplay texture cache exists for the requested board cell size.
## Safe to re-run on demand (e.g. after a future resolution/settings change).
func ensure_gameplay_texture_cache(
	draw_size: Vector2i,
	tile_scope = [],
) -> void:
	if _shutting_down:
		return
	if draw_size.x <= 0 or draw_size.y <= 0:
		return
	var normalized_scope := _normalize_tile_scope(tile_scope)
	if _is_gameplay_profile_current(draw_size, normalized_scope):
		return
	if _bake_in_progress:
		_pending_bake_draw_size = draw_size
		_pending_bake_tile_scope = normalized_scope
		return

	var bake_render_size := _make_bake_render_size(draw_size)
	preload_runtime_assets([draw_size, bake_render_size])
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_texture_profile = {
		"cell_size": draw_size,
		"backend_preference": _gameplay_bake_backend_preference,
		"lighting_grid_size": GAMEPLAY_LIGHTING_GRID_SIZE,
		"rotation_bin_count": _get_default_rotation_view_count(),
		"rotation_view_signature": _build_rotation_view_signature(),
		"tile_scope": normalized_scope,
	}
	_bake_draw_size = bake_render_size
	_bake_queue = []
	if normalized_scope.is_empty():
		for tile_id in _visuals:
			var visual: GemVisualResource = _visuals[tile_id]
			var cut: GemCutResource = get_visual_cut(visual)
			if cut == null:
				continue
			_bake_queue.append_array(_build_gameplay_bake_requests(
				tile_id,
				visual,
				cut,
				_bake_draw_size,
				draw_size,
				{}
			))
	else:
		for tile_id in normalized_scope:
			var scoped_tile_id := StringName(tile_id)
			if not _visuals.has(scoped_tile_id):
				continue
			var visual: GemVisualResource = _visuals[scoped_tile_id]
			var cut: GemCutResource = get_visual_cut(visual)
			if cut == null:
				continue
			_bake_queue.append_array(_build_gameplay_bake_requests(
				scoped_tile_id,
				visual,
				cut,
				_bake_draw_size,
				draw_size,
				{}
			))
	_bake_in_progress = true
	_bake_current_tile_id = &""
	_current_bake_request = {}
	_bake_total_requests = _bake_queue.size()
	_bake_completed_requests = 0
	_begin_bake_report(draw_size, bake_render_size)
	_emit_bake_progress("queued")
	_queue_next_bake_step()


## Returns cached [facet_colors, pavilion_colors] for the given cache key.
## Computes and caches on first call; subsequent calls return the cached arrays.
## cache_key should be tile_id for normal gems, or a synthetic key for fallback paths.
func get_cached_colors(
	cache_key: StringName,
	cut: GemCutResource,
	visual: GemVisualResource,
	light_dir: Vector3 = GemRenderer.DEFAULT_LIGHT_DIR,
) -> Array:
	if _color_cache.has(cache_key):
		return _color_cache[cache_key]
	var facet_colors := GemRenderer.compute_all_facet_colors(cut, visual, light_dir)
	var pavilion_colors := GemRenderer.compute_pavilion_colors(cut, visual, light_dir)
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
	light_dir: Vector3 = GemRenderer.DEFAULT_LIGHT_DIR,
	cut_key_override: String = "",
) -> Dictionary:
	var cut_key := cut_key_override if not cut_key_override.is_empty() else get_visual_cut_key(visual)
	var geometry := get_cached_scaled_geometry(cut, cut_key, draw_size)
	var colors := get_cached_colors(cache_key, cut, visual, light_dir)
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
func get_cached_scaled_geometry(cut: GemCutResource, cut_key: String, draw_size: Vector2i) -> Dictionary:
	if cut == null:
		return {}
	var geometry_key := _make_scaled_geometry_key(cut_key, draw_size)
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
			var cut: GemCutResource = get_visual_cut(visual)
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
	_scaled_geometry_cache.clear()
	_cut_variants.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_texture_profile.clear()
	_last_gameplay_bake_report.clear()


## Clears the scaled-geometry and render bundle caches.
func invalidate_render_cache() -> void:
	_scaled_geometry_cache.clear()
	_render_cache.clear()
	_cut_variants.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_texture_profile.clear()
	_last_gameplay_bake_report.clear()


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


func _initialize_bake_backends() -> void:
	_shutdown_bake_backends()
	_register_bake_backend(GameplayBakeBackendOfflineTracedScript.new())


func _register_bake_backend(backend) -> void:
	if backend == null:
		return
	backend.texture_baked.connect(_on_backend_texture_baked)
	add_child(backend)
	_gameplay_bake_backends[backend.backend_id] = backend


func _shutdown_bake_backends() -> void:
	for backend in _gameplay_bake_backends.values():
		if backend == null:
			continue
		if backend.texture_baked.is_connected(_on_backend_texture_baked):
			backend.texture_baked.disconnect(_on_backend_texture_baked)
		backend.shutdown()
		backend.queue_free()
	_gameplay_bake_backends.clear()


func _select_bake_backend(request: Dictionary):
	var backend = _gameplay_bake_backends.get(GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED, null)
	if backend != null and backend.supports_request(request):
		return backend
	return null


func _begin_bake_report(cell_size: Vector2i, bake_draw_size: Vector2i) -> void:
	_last_gameplay_bake_report = {
		"profile": {
			"cell_size": cell_size,
			"draw_size": bake_draw_size,
			"backend_preference": _gameplay_bake_backend_preference,
			"tile_scope": _gameplay_texture_profile.get("tile_scope", PackedStringArray()),
		},
		"tile_metrics": [],
		"backend_counts": {},
		"total_elapsed_ms": 0.0,
	}


func _record_bake_metric(metric: Dictionary) -> void:
	if _last_gameplay_bake_report.is_empty():
		return
	var tile_metrics: Array = _last_gameplay_bake_report.get("tile_metrics", [])
	tile_metrics.append(metric)
	_last_gameplay_bake_report["tile_metrics"] = tile_metrics
	var backend_counts: Dictionary = _last_gameplay_bake_report.get("backend_counts", {})
	var backend_id: StringName = metric.get("backend_id", &"unknown")
	backend_counts[backend_id] = int(backend_counts.get(backend_id, 0)) + 1
	_last_gameplay_bake_report["backend_counts"] = backend_counts
	_last_gameplay_bake_report["total_elapsed_ms"] = float(
		_last_gameplay_bake_report.get("total_elapsed_ms", 0.0)
	) + float(metric.get("elapsed_ms", 0.0))


func _get_default_lighting_bin() -> Vector2i:
	return Vector2i(
		int(floor(float(GAMEPLAY_LIGHTING_GRID_SIZE.x - 1) * 0.5)),
		int(floor(float(GAMEPLAY_LIGHTING_GRID_SIZE.y - 1) * 0.5))
	)


func _make_gameplay_variant_cache_key(
	base_key: StringName,
	variant_type: StringName,
	lighting_bin: Vector2i = Vector2i(-1, -1),
	rotation_bin: int = -1,
) -> StringName:
	match variant_type:
		GAMEPLAY_VARIANT_TYPE_ROTATION:
			return StringName("%s@rot_%02d" % [String(base_key), maxi(rotation_bin, 0)])
		_:
			return StringName("%s@light_%d_%d" % [
				String(base_key),
				maxi(lighting_bin.x, 0),
				maxi(lighting_bin.y, 0),
			])


func _get_gameplay_variant_metadata(
	base_key: StringName,
	variant_type: StringName,
	lighting_bin: Vector2i = Vector2i(-1, -1),
	rotation_bin: int = -1,
) -> Dictionary:
	return _gameplay_texture_metadata_cache.get(
		_make_gameplay_variant_cache_key(base_key, variant_type, lighting_bin, rotation_bin),
		{}
	)


func _merge_variant_weight_entries(entries: Array, field_name: String) -> Array[Dictionary]:
	var merged_by_key: Dictionary = {}
	var merged_entries: Array[Dictionary] = []
	for entry in entries:
		var weight := float(entry.get("weight", 0.0))
		if weight <= 0.0001:
			continue
		var variant_value = entry.get(field_name, null)
		var key := str(variant_value)
		if not merged_by_key.has(key):
			var merged_entry: Dictionary = entry.duplicate(true)
			merged_entries.append(merged_entry)
			merged_by_key[key] = merged_entry
			continue
		merged_by_key[key]["weight"] = float(merged_by_key[key].get("weight", 0.0)) + weight
	var total_weight := 0.0
	for entry in merged_entries:
		total_weight += float(entry.get("weight", 0.0))
	if total_weight <= 0.0001:
		return []
	for entry in merged_entries:
		entry["weight"] = float(entry.get("weight", 0.0)) / total_weight
	return merged_entries


func _build_gameplay_bake_requests(
	tile_id: StringName,
	visual: GemVisualResource,
	cut: GemCutResource,
	draw_size: Vector2i,
	target_size: Vector2i,
	variant_options: Dictionary = {},
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var view_scale := _compute_trace_view_scale(visual, cut)
	for y in GAMEPLAY_LIGHTING_GRID_SIZE.y:
		for x in GAMEPLAY_LIGHTING_GRID_SIZE.x:
			var lighting_bin := Vector2i(x, y)
			var lighting_uv := _lighting_bin_to_centered(lighting_bin)
			requests.append({
				"tile_id": tile_id,
				"visual_id": visual.visual_id,
				"cut_id": cut.cut_id,
				"visual": visual,
				"cut": cut,
				"draw_size": draw_size,
				"target_size": target_size,
				"variant_type": GAMEPLAY_VARIANT_TYPE_LIGHTING,
				"variant_key": _make_gameplay_variant_cache_key(
					tile_id,
					GAMEPLAY_VARIANT_TYPE_LIGHTING,
					lighting_bin
				),
				"cut_key_override": get_visual_cut_key(visual),
				"lighting_bin": lighting_bin,
				"lighting_uv": lighting_uv,
				"light_dir": _compute_variant_light_dir(lighting_bin),
				"view_scale": view_scale,
			})
	var rotation_views := _build_rotation_view_suite(variant_options)
	var cut_key := get_visual_cut_key(visual)
	for rotation_bin in rotation_views.size():
		var rotation_view: Dictionary = rotation_views[rotation_bin]
		requests.append({
			"tile_id": tile_id,
			"visual_id": visual.visual_id,
			"cut_id": cut.cut_id,
			"visual": visual,
			"cut": cut,
			"draw_size": draw_size,
			"target_size": target_size,
			"variant_type": GAMEPLAY_VARIANT_TYPE_ROTATION,
			"variant_key": _make_gameplay_variant_cache_key(
				tile_id,
				GAMEPLAY_VARIANT_TYPE_ROTATION,
				Vector2i(-1, -1),
				rotation_bin
			),
			"cut_key_override": cut_key,
			"rotation_bin": rotation_bin,
			"rotation_label": StringName(rotation_view.get("label", "rot_%02d" % rotation_bin)),
			"rotation_axis": rotation_view.get("axis", &""),
			"rotation_degrees": 0.0,
			"view_pitch_degrees": float(rotation_view.get("view_pitch_degrees", 0.0)),
			"view_yaw_degrees": float(rotation_view.get("view_yaw_degrees", 0.0)),
			"view_roll_degrees": float(rotation_view.get("view_roll_degrees", 0.0)),
			"light_dir": _compute_variant_light_dir(_get_default_lighting_bin()),
			"view_scale": view_scale,
		})
	return requests


func _get_default_rotation_view_count() -> int:
	return GAMEPLAY_BASE_ROTATION_VIEW_COUNT


func _build_rotation_view_signature(options: Dictionary = {}) -> String:
	var suite := _build_rotation_view_suite(options)
	var parts := PackedStringArray()
	for view in suite:
		parts.append("%s:%.3f:%.3f:%.3f" % [
			String(view.get("label", "")),
			float(view.get("view_pitch_degrees", 0.0)),
			float(view.get("view_yaw_degrees", 0.0)),
			float(view.get("view_roll_degrees", 0.0)),
		])
	return "|".join(parts)


func _build_rotation_view_suite(options: Dictionary = {}) -> Array[Dictionary]:
	var normalized := _normalize_rotation_variant_options(options)
	var suite: Array[Dictionary] = [
		_make_rotation_view("crown", 0.0, 0.0, 0.0),
		_make_rotation_view("front", 90.0, 0.0, 0.0),
		_make_rotation_view("right", 0.0, 90.0, 0.0),
		_make_rotation_view("pavilion", 180.0, 0.0, 0.0),
		_make_rotation_view("left", 0.0, -90.0, 0.0),
		_make_rotation_view("back", -90.0, 0.0, 0.0),
	]
	var axis_steps := int(normalized.get("rotation_axis_steps", 0))
	if axis_steps <= 0:
		return suite
	var step_degrees := float(normalized.get("rotation_step_degrees", GAMEPLAY_ROTATION_DEFAULT_STEP_DEGREES))
	var axes: Array = normalized.get("rotation_axes", [])
	for raw_axis in axes:
		suite.append_array(_build_rotation_axis_sweep(StringName(raw_axis), axis_steps, step_degrees))
	return suite


func _normalize_rotation_variant_options(options: Dictionary = {}) -> Dictionary:
	var normalized_axes: Array[StringName] = []
	var seen: Dictionary = {}
	var raw_axes = options.get("rotation_axes", [])
	if raw_axes is String:
		raw_axes = String(raw_axes).replace(";", ",").split(",", false)
	for raw_axis in raw_axes:
		var axis := StringName(String(raw_axis).strip_edges().to_lower())
		if axis == &"" or seen.has(axis):
			continue
		if axis != &"pitch" and axis != &"yaw" and axis != &"roll":
			continue
		seen[axis] = true
		normalized_axes.append(axis)
	return {
		"rotation_axis_steps": maxi(int(options.get("rotation_axis_steps", GAMEPLAY_ROTATION_DEFAULT_AXIS_STEPS)), 0),
		"rotation_step_degrees": maxf(float(options.get("rotation_step_degrees", GAMEPLAY_ROTATION_DEFAULT_STEP_DEGREES)), 1.0),
		"rotation_axes": normalized_axes,
	}


func _build_rotation_axis_sweep(axis: StringName, axis_steps: int, step_degrees: float) -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	for step_index in range(1, axis_steps + 1):
		var angle := step_degrees * float(step_index)
		views.append(_make_rotation_axis_view(axis, -angle, step_index, -1))
		views.append(_make_rotation_axis_view(axis, angle, step_index, 1))
	return views


func _make_rotation_axis_view(
	axis: StringName,
	angle_degrees: float,
	step_index: int,
	direction_sign: int,
) -> Dictionary:
	var pitch := 0.0
	var yaw := 0.0
	var roll := 0.0
	match axis:
		&"pitch":
			pitch = angle_degrees
		&"yaw":
			yaw = angle_degrees
		&"roll":
			roll = angle_degrees
	var sign_label := "neg" if direction_sign < 0 else "pos"
	return _make_rotation_view(
		"%s_%s_%02d" % [String(axis), sign_label, step_index],
		pitch,
		yaw,
		roll,
		axis
	)


func _make_rotation_view(
	label: String,
	view_pitch_degrees: float,
	view_yaw_degrees: float,
	view_roll_degrees: float,
	axis: StringName = &"",
) -> Dictionary:
	return {
		"label": label,
		"axis": axis,
		"view_pitch_degrees": view_pitch_degrees,
		"view_yaw_degrees": view_yaw_degrees,
		"view_roll_degrees": view_roll_degrees,
	}


func _compute_variant_light_dir(lighting_bin: Vector2i) -> Vector3:
	var base_dir := GemRenderer.DEFAULT_LIGHT_DIR.normalized()
	var centered := _lighting_bin_to_centered(lighting_bin)
	var yaw := Basis(Vector3.UP, deg_to_rad(centered.x * GAMEPLAY_LIGHTING_SWEEP_X_DEGREES))
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(-centered.y * GAMEPLAY_LIGHTING_SWEEP_Y_DEGREES))
	return (yaw * pitch * base_dir).normalized()


func _lighting_bin_to_centered(lighting_bin: Vector2i) -> Vector2:
	var centered := Vector2.ZERO
	if GAMEPLAY_LIGHTING_GRID_SIZE.x > 1:
		centered.x = (float(lighting_bin.x) / float(GAMEPLAY_LIGHTING_GRID_SIZE.x - 1)) * 2.0 - 1.0
	if GAMEPLAY_LIGHTING_GRID_SIZE.y > 1:
		centered.y = (float(lighting_bin.y) / float(GAMEPLAY_LIGHTING_GRID_SIZE.y - 1)) * 2.0 - 1.0
	return centered


## Computes a view scale factor for the traced bake camera.  Gems pre-rotated
## 45 degrees (diamond orientation) are slightly enlarged while axis-aligned
## square cuts are slightly reduced so that both occupy approximately the same
## visual area on the game board.
func _compute_trace_view_scale(visual: GemVisualResource, cut: GemCutResource) -> float:
	if visual == null or cut == null:
		return 1.0
	var is_square_family := (
		cut.shape_category == &"square"
		or cut.orientation_fit_axis_aligned_scale < 0.999
	)
	if not is_square_family:
		return 1.0
	var rotation := absf(fmod(visual.rotation_degrees, 90.0))
	var is_rotated_diamond := rotation > 30.0 and rotation < 60.0
	if is_rotated_diamond:
		return 1.08 * visual.optics_trace_view_scale
	return cut.orientation_fit_axis_aligned_scale * visual.optics_trace_view_scale


## Eagerly computes and caches facet colors for all loaded gem types.
func _pre_warm_colors() -> void:
	if not _color_cache.is_empty():
		return
	for tile_id in _visuals:
		var visual: GemVisualResource = _visuals[tile_id]
		var cut: GemCutResource = get_visual_cut(visual)
		if cut != null:
			get_cached_colors(tile_id, cut, visual)
			var tier := _resolve_visual_tier(tile_id)
			if tier > 0:
				get_cached_colors(StringName("_tier_%d" % tier), cut, visual)
	if not _color_cache.is_empty():
		print("GemVisualRegistry: Pre-warmed %d color caches" % _color_cache.size())


func get_visual_cut_key(visual: GemVisualResource) -> String:
	if visual == null:
		return ""
	return _make_cut_variant_key(visual.cut_id, visual.rotation_degrees)


func _make_cut_variant_key(cut_id: StringName, rotation_degrees: float) -> String:
	return "%s@rot_%s" % [String(cut_id), String.num(snappedf(rotation_degrees, 0.001))]


func _make_scaled_geometry_key(cut_key: String, draw_size: Vector2i) -> String:
	return "%s@%dx%d" % [cut_key, draw_size.x, draw_size.y]


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
		"unit_facets": cut.facet_vertices,
		"facet_normals": cut.facet_normals,
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


func _normalize_tile_scope(tile_scope) -> PackedStringArray:
	var seen: Dictionary = {}
	var normalized: Array[String] = []
	for raw_tile_id in tile_scope:
		var tile_id := StringName(raw_tile_id)
		if tile_id == &"" or seen.has(tile_id):
			continue
		seen[tile_id] = true
		normalized.append(String(tile_id))
	normalized.sort()
	return PackedStringArray(normalized)


func _is_gameplay_profile_current(
	draw_size: Vector2i,
	tile_scope = [],
) -> bool:
	if _gameplay_texture_cache.is_empty():
		return false
	var normalized_scope := _normalize_tile_scope(tile_scope)
	var cached_scope := _normalize_tile_scope(_gameplay_texture_profile.get("tile_scope", []))
	return _gameplay_texture_profile.get("cell_size", Vector2i.ZERO) == draw_size \
		and _gameplay_texture_profile.get("lighting_grid_size", Vector2i.ZERO) == GAMEPLAY_LIGHTING_GRID_SIZE \
		and _gameplay_texture_profile.get("rotation_bin_count", -1) == _get_default_rotation_view_count() \
		and _gameplay_texture_profile.get("rotation_view_signature", "") == _build_rotation_view_signature() \
		and cached_scope == normalized_scope


func _begin_next_bake_step() -> void:
	if _shutting_down:
		return
	while not _bake_queue.is_empty():
		var request: Dictionary = _bake_queue.pop_front()
		var tile_id: StringName = request.get("tile_id", &"")
		var visual: GemVisualResource = request.get("visual", null)
		if visual == null:
			continue
		var cut: GemCutResource = request.get("cut", null)
		if cut == null:
			continue
		var backend = _select_bake_backend(request)
		if backend == null:
			continue
		_bake_current_tile_id = tile_id
		_current_bake_request = request.duplicate(true)
		_emit_bake_progress("baking")
		backend.request_bake(request)
		return
	_finish_bake_queue()


func _on_backend_texture_baked(tile_id: StringName, texture: Texture2D, metadata: Dictionary) -> void:
	if _shutting_down or not _bake_in_progress:
		return
	if texture == null:
		var attempted_metric := metadata.duplicate(true)
		attempted_metric["tile_id"] = tile_id
		attempted_metric["tier"] = _resolve_visual_tier(tile_id)
		attempted_metric["attempt_only"] = true
		_record_bake_metric(attempted_metric)
		_mark_bake_request_completed(metadata)
		_bake_current_tile_id = &""
		_current_bake_request = {}
		_queue_next_bake_step()
		return

	var tier := _resolve_visual_tier(tile_id)
	_store_gameplay_texture_variant(tile_id, tier, texture, metadata)

	var metric := metadata.duplicate(true)
	metric["tile_id"] = tile_id
	metric["tier"] = tier
	_record_bake_metric(metric)
	_mark_bake_request_completed(metadata)

	_bake_current_tile_id = &""
	_current_bake_request = {}
	_queue_next_bake_step()


func _store_gameplay_texture_variant(
	tile_id: StringName,
	tier: int,
	texture: Texture2D,
	metadata: Dictionary,
) -> void:
	var variant_type: StringName = metadata.get("variant_type", GAMEPLAY_VARIANT_TYPE_LIGHTING)
	var lighting_bin: Vector2i = metadata.get("lighting_bin", _get_default_lighting_bin())
	var rotation_bin: int = metadata.get("rotation_bin", -1)
	var tile_cache_key := _make_gameplay_variant_cache_key(tile_id, variant_type, lighting_bin, rotation_bin)
	_gameplay_texture_cache[tile_cache_key] = texture
	var stored_metadata: Dictionary = metadata.duplicate(true)
	stored_metadata["tile_id"] = tile_id
	stored_metadata["tier"] = tier
	stored_metadata["variant_cache_key"] = tile_cache_key
	_gameplay_texture_metadata_cache[tile_cache_key] = stored_metadata
	if tier <= 0:
		return
	var tier_base_key := StringName("_tier_%d" % tier)
	var tier_cache_key := _make_gameplay_variant_cache_key(
		tier_base_key,
		variant_type,
		lighting_bin,
		rotation_bin
	)
	if not _gameplay_texture_cache.has(tier_cache_key):
		_gameplay_texture_cache[tier_cache_key] = texture
	if not _gameplay_texture_metadata_cache.has(tier_cache_key):
		_gameplay_texture_metadata_cache[tier_cache_key] = stored_metadata.duplicate(true)


func _finish_bake_queue() -> void:
	_bake_in_progress = false
	_bake_current_tile_id = &""
	_current_bake_request = {}
	_bake_completed_requests = _bake_total_requests
	_last_gameplay_bake_report["profile"] = get_gameplay_texture_profile()
	_last_gameplay_bake_report["variant_texture_count"] = _gameplay_texture_cache.size()
	if _shutting_down:
		return
	_emit_bake_progress("complete")
	gameplay_texture_cache_rebuilt.emit(get_gameplay_texture_profile())
	if _pending_bake_draw_size != Vector2i.ZERO:
		var next_draw_size := _pending_bake_draw_size
		var next_tile_scope := _pending_bake_tile_scope
		_pending_bake_draw_size = Vector2i.ZERO
		_pending_bake_tile_scope = PackedStringArray()
		if not _is_gameplay_profile_current(next_draw_size, next_tile_scope):
			ensure_gameplay_texture_cache(next_draw_size, next_tile_scope)


func _clear_runtime_state() -> void:
	_pending_bake_draw_size = Vector2i.ZERO
	_pending_bake_tile_scope = PackedStringArray()
	_bake_step_scheduled = false
	_bake_draw_size = Vector2i.ZERO
	_bake_queue.clear()
	_bake_current_tile_id = &""
	_current_bake_request = {}
	_bake_in_progress = false
	_bake_total_requests = 0
	_bake_completed_requests = 0
	_gameplay_texture_profile.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_last_gameplay_bake_report.clear()
	_render_cache.clear()
	_scaled_geometry_cache.clear()
	_color_cache.clear()
	_tier_to_visual.clear()
	_cut_variants.clear()
	_cuts.clear()
	_visuals.clear()
	_loaded = false


func _queue_next_bake_step() -> void:
	if _bake_step_scheduled or _shutting_down:
		return
	_bake_step_scheduled = true
	call_deferred("_process_bake_step_deferred")


func _process_bake_step_deferred() -> void:
	_bake_step_scheduled = false
	if _shutting_down or not _bake_in_progress:
		return
	_begin_next_bake_step()


func _make_bake_render_size(draw_size: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(draw_size.x * GAMEPLAY_BAKE_SUPERSAMPLE, 1),
		maxi(draw_size.y * GAMEPLAY_BAKE_SUPERSAMPLE, 1)
	)


func _mark_bake_request_completed(metadata: Dictionary) -> void:
	_bake_completed_requests = mini(_bake_completed_requests + 1, _bake_total_requests)
	_emit_bake_progress("baking", metadata)


func _emit_bake_progress(stage: String, metadata: Dictionary = {}) -> void:
	var total := maxi(_bake_total_requests, 0)
	var completed := clampi(_bake_completed_requests, 0, total)
	var current_tile: StringName = metadata.get(
		"tile_id",
		_current_bake_request.get("tile_id", _bake_current_tile_id)
	)
	var progress := 0.0
	if total > 0:
		progress = float(completed) / float(total)
	gameplay_texture_bake_progress.emit({
		"stage": stage,
		"completed": completed,
		"total": total,
		"progress": progress,
		"tile_id": current_tile,
		"variant_type": metadata.get(
			"variant_type",
			_current_bake_request.get("variant_type", GAMEPLAY_VARIANT_TYPE_LIGHTING)
		),
		"backend_id": metadata.get("backend_id", &""),
	})
