extends Node

## Loads GemVisualResource definitions from data/visuals/, generates cuts at
## startup, and provides lookup for the rendering layer.
##
## Runtime visuals use layered caches:
## - shared color / geometry / render bundles for both procedural and baked paths
## - a gameplay texture cache for the board's sprite-backed TileViews
##
## Depends on: GemCutGenerators, GemVisualResource, GemProjectedCutResource, GemRenderer.

const VISUAL_DATA_PATH := "res://data/visuals/"
const GAMEPLAY_BAKE_SUPERSAMPLE := 2
const GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED := &"offline_traced"
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const GAMEPLAY_VARIANT_TYPE_LIGHTING := &"lighting"
const GAMEPLAY_VARIANT_TYPE_ROTATION := &"rotation"
const GAMEPLAY_VARIANT_TYPE_SHOWROOM := GemTracedBakeContractScript.GAMEPLAY_VARIANT_TYPE_SHOWROOM
const DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE := GemTracedBakeContract.DEFAULT_LIGHTING_GRID_SIZE
const DEFAULT_GAMEPLAY_BASE_ROTATION_VIEW_COUNT := GemTracedBakeContract.DEFAULT_ROTATION_BASE_VIEW_COUNT
const GAMEPLAY_ROTATION_DEFAULT_AXIS_STEPS := 0
const GAMEPLAY_ROTATION_DEFAULT_STEP_DEGREES := 18.0
const GAMEPLAY_LIGHTING_SWEEP_X_DEGREES := 46.0
const GAMEPLAY_LIGHTING_SWEEP_Y_DEGREES := 30.0
const GemCutProjectorScript = preload("res://core/visuals/gem_cut_projector.gd")
const GameplayBakeBackendOfflineTracedScript = preload("res://scenes/tile/gem_gameplay_bake_backend_offline_traced.gd")
const GemViewSphereSamplingScript = preload("res://core/visuals/gem_view_sphere_sampling.gd")
const GemAtlasCacheScript = preload("res://core/visuals/gem_atlas_cache.gd")

signal gameplay_texture_cache_rebuilt(profile: Dictionary)
signal gameplay_texture_bake_progress(progress: Dictionary)

var _visuals: Dictionary = {}          # StringName (visual_id / tile_id) -> GemVisualResource
var _cut_models: Dictionary = {}       # String (geometry signature) -> GemCutModelResource
var _cut_model_variants: Dictionary = {}  # String -> rotated GemCutModelResource per geometry signature + rotation
var _cuts: Dictionary = {}             # String (geometry signature) -> GemProjectedCutResource
var _cut_variants: Dictionary = {}     # String -> rotated GemProjectedCutResource per geometry signature + rotation
var _tier_to_visual: Dictionary = {}   # int -> GemVisualResource (first match)
var _color_cache: Dictionary = {}      # StringName (cache_key) -> [PackedColorArray, PackedColorArray]
var _scaled_geometry_cache: Dictionary = {}  # String -> geometry bundle per geometry signature + draw size
var _render_cache: Dictionary = {}      # String -> render bundle per cache key + draw size
var _gameplay_texture_cache: Dictionary = {}  # StringName composite variant key -> Texture2D
var _gameplay_texture_metadata_cache: Dictionary = {}  # StringName composite variant key -> metadata
var _gameplay_lighting_atlas_by_key: Dictionary = {}  # StringName base_key -> Texture2DArray
var _gameplay_rotation_atlas_by_key: Dictionary = {}  # StringName base_key -> Texture2DArray
var _gameplay_blend_placeholder_atlas: Texture2DArray = null
var _gem_atlas_run_cache = GemAtlasCacheScript.new()
var _gameplay_run_tile_scope: PackedStringArray = PackedStringArray()
var _gameplay_run_tile_scope_previous: PackedStringArray = PackedStringArray()
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
var _last_gameplay_bake_report: Dictionary = {}
var _gameplay_variant_settings: Dictionary = GemTracedBakeContractScript.default_variant_settings()
## Per-tile showroom frames for quaternion lookup (manifest and/or designer session).
var _showroom_cache: Dictionary = {}  # StringName -> Dictionary (orientations, textures, sigma, meta)
var _bake_started_usec := 0
var _bake_warmup_elapsed_ms := 0.0
var _bake_queue_build_elapsed_ms := 0.0


func _ready() -> void:
	_load_visuals()
	_generate_cuts()
	_initialize_bake_backends()
	_sync_gameplay_variant_settings_from_offline_manifest(false)


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


## Returns the projected 2D cut for a geometry signature, or null.
func get_cut(geometry_signature: String):
	return _cuts.get(geometry_signature, null)


## Returns the canonical 3D cut model for a geometry signature, or null.
func get_cut_model(geometry_signature: String):
	return _cut_models.get(geometry_signature, null)


## Returns the effective cut model for a visual, including any per-visual rotation.
func get_visual_cut_model(visual: GemVisualResource):
	return get_visual_cut_model_with_offset(visual, 0.0)


func get_visual_cut_model_with_offset(
	visual: GemVisualResource,
	additional_rotation_degrees: float = 0.0,
):
	if visual == null:
		return null
	var geometry_key := _ensure_visual_geometry_cached(visual)
	if geometry_key.is_empty():
		return null
	var base_model = _cut_models.get(geometry_key, null)
	if base_model == null:
		return null
	var total_rotation := visual.rotation_degrees + additional_rotation_degrees
	if is_zero_approx(total_rotation) and base_model.orthographic_axis_fit_scale >= 0.999:
		return base_model
	var variant_key := _make_cut_variant_key(geometry_key, total_rotation)
	if _cut_model_variants.has(variant_key):
		return _cut_model_variants[variant_key]
	var rotated_model = GemCutCompiler3D.create_visual_variant(base_model, total_rotation)
	if rotated_model != null:
		_cut_model_variants[variant_key] = rotated_model
	return rotated_model


## Returns the effective projected cut for a visual, including any per-visual rotation.
func get_visual_cut(visual: GemVisualResource) -> GemProjectedCutResource:
	return get_visual_cut_with_offset(visual, 0.0)


func get_visual_cut_with_offset(
	visual: GemVisualResource,
	additional_rotation_degrees: float = 0.0,
) -> GemProjectedCutResource:
	if visual == null:
		return null
	var geometry_key := _ensure_visual_geometry_cached(visual)
	if geometry_key.is_empty():
		return null
	var base_cut = _cuts.get(geometry_key, null)
	if base_cut == null:
		return null
	var total_rotation := visual.rotation_degrees + additional_rotation_degrees
	if is_zero_approx(total_rotation) and base_cut.orthographic_axis_fit_scale >= 0.999:
		return base_cut

	var variant_key := _make_cut_variant_key(geometry_key, total_rotation)
	if _cut_variants.has(variant_key):
		return _cut_variants[variant_key]

	var rotated_model = get_visual_cut_model_with_offset(visual, additional_rotation_degrees)
	var rotated_cut = GemCutProjectorScript.project(rotated_model) if rotated_model != null else null
	if rotated_cut != null:
		_cut_variants[variant_key] = rotated_cut
	return rotated_cut


## Returns the baked gameplay texture for a tile_id in the active gameplay profile.
## Falls back to the first matching tier visual when the exact tile_id is missing.
func get_gameplay_texture(tile_id: StringName, tier: int = -1) -> Texture2D:
	var lighting_texture := get_gameplay_lighting_texture(tile_id, tier, _get_default_lighting_bin())
	if lighting_texture != null:
		return lighting_texture
	return get_gameplay_rotation_texture(tile_id, tier, 0)


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


func get_gameplay_blend_placeholder_atlas() -> Texture2DArray:
	if _gameplay_blend_placeholder_atlas == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ta := Texture2DArray.new()
		ta.create_from_images([img])
		_gameplay_blend_placeholder_atlas = ta
	return _gameplay_blend_placeholder_atlas


## Lighting grid row-major: layer = bin.y * grid.x + bin.x (matches bake request order).
func lighting_atlas_layer_index(lighting_bin: Vector2i, grid: Vector2i) -> int:
	return lighting_bin.y * grid.x + lighting_bin.x


## Builds a 4-layer array for the gameplay blend shader (unused slots may be transparent).
func build_gameplay_sprite_atlas_from_textures(textures: Array) -> Texture2DArray:
	var w := 1
	var h := 1
	var fmt := Image.FORMAT_RGBA8
	for t in textures:
		if t is Texture2D and t != null:
			var sz: Vector2 = (t as Texture2D).get_size()
			w = maxi(w, int(round(sz.x)))
			h = maxi(h, int(round(sz.y)))
	var imgs: Array[Image] = []
	for i in 4:
		var tex: Texture2D = textures[i] if i < textures.size() else null
		var im: Image = null
		if tex != null:
			im = tex.get_image()
		if im == null:
			var blank := Image.create(w, h, false, fmt)
			blank.fill(Color(0, 0, 0, 0))
			imgs.append(blank)
		else:
			if im.get_width() != w or im.get_height() != h:
				var dup := im.duplicate()
				dup.resize(w, h, Image.INTERPOLATE_BILINEAR)
				imgs.append(dup)
			else:
				imgs.append(im.duplicate())
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func _gameplay_blend_dict_from_textures(textures: Array, weights: Vector4) -> Dictionary:
	return {
		"atlas": build_gameplay_sprite_atlas_from_textures(textures),
		"layer_index": Vector4(0.0, 1.0, 2.0, 3.0),
		"weights": weights,
	}


func _gameplay_blend_dict_pack_lighting(
	tile_id: StringName,
	tier: int,
	blend_entries: Array,
	baked_grid: Vector2i,
	atlas: Texture2DArray,
) -> Dictionary:
	var empty := {
		"atlas": null,
		"layer_index": Vector4.ZERO,
		"weights": Vector4.ZERO,
	}
	if blend_entries.is_empty():
		return empty
	var layer_index := Vector4.ZERO
	var weights := Vector4.ZERO
	var slot := 0
	for entry in blend_entries:
		if slot >= 4:
			break
		var wt := clampf(float(entry.get("weight", 0.0)), 0.0, 1.0)
		var layer_f := float(
			lighting_atlas_layer_index(
				entry.get("lighting_bin", Vector2i.ZERO),
				baked_grid
			)
		)
		match slot:
			0:
				layer_index.x = layer_f
				weights.x = wt
			1:
				layer_index.y = layer_f
				weights.y = wt
			2:
				layer_index.z = layer_f
				weights.z = wt
			3:
				layer_index.w = layer_f
				weights.w = wt
		slot += 1
	if atlas != null:
		return {"atlas": atlas, "layer_index": layer_index, "weights": weights}
	var tex_list: Array = []
	for entry in blend_entries:
		if tex_list.size() >= 4:
			break
		var bin: Vector2i = entry.get("lighting_bin", _get_default_lighting_bin())
		tex_list.append(get_gameplay_lighting_texture(tile_id, tier, bin))
	while tex_list.size() < 4:
		tex_list.append(null)
	return _gameplay_blend_dict_from_textures(tex_list, weights)


func _gameplay_blend_dict_pack_rotation(
	tile_id: StringName,
	tier: int,
	blend_entries: Array,
	atlas: Texture2DArray,
) -> Dictionary:
	var empty := {
		"atlas": null,
		"layer_index": Vector4.ZERO,
		"weights": Vector4.ZERO,
	}
	if blend_entries.is_empty():
		return empty
	var layer_index := Vector4.ZERO
	var weights := Vector4.ZERO
	var slot := 0
	for entry in blend_entries:
		if slot >= 4:
			break
		var wt := clampf(float(entry.get("weight", 0.0)), 0.0, 1.0)
		var layer_f := float(int(entry.get("rotation_bin", 0)))
		match slot:
			0:
				layer_index.x = layer_f
				weights.x = wt
			1:
				layer_index.y = layer_f
				weights.y = wt
			2:
				layer_index.z = layer_f
				weights.z = wt
			3:
				layer_index.w = layer_f
				weights.w = wt
		slot += 1
	if atlas != null:
		return {"atlas": atlas, "layer_index": layer_index, "weights": weights}
	var tex_list: Array = []
	for entry in blend_entries:
		if tex_list.size() >= 4:
			break
		var rb: int = int(entry.get("rotation_bin", 0))
		tex_list.append(get_gameplay_rotation_texture(tile_id, tier, rb))
	while tex_list.size() < 4:
		tex_list.append(null)
	return _gameplay_blend_dict_from_textures(tex_list, weights)


func get_gameplay_lighting_blend_set(
	tile_id: StringName,
	tier: int,
	normalized_position: Vector2,
) -> Dictionary:
	var empty := {
		"atlas": null,
		"layer_index": Vector4.ZERO,
		"weights": Vector4.ZERO,
	}
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return empty
	var blend_entries := compute_gameplay_lighting_blend(normalized_position)
	if blend_entries.is_empty():
		var rot_atlas: Texture2DArray = _gameplay_rotation_atlas_by_key.get(base_key, null)
		if rot_atlas != null:
			return {
				"atlas": rot_atlas,
				"layer_index": Vector4.ZERO,
				"weights": Vector4(1.0, 0.0, 0.0, 0.0),
			}
		var fallback_rotation := get_gameplay_rotation_texture(tile_id, tier, 0)
		if fallback_rotation != null:
			return _gameplay_blend_dict_from_textures(
				[fallback_rotation, null, null, null],
				Vector4(1.0, 0.0, 0.0, 0.0)
			)
		return empty
	var settings := get_gameplay_variant_settings()
	var baked_grid: Vector2i = settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	var atlas: Texture2DArray = _gameplay_lighting_atlas_by_key.get(base_key, null)
	return _gameplay_blend_dict_pack_lighting(
		tile_id,
		tier,
		blend_entries,
		baked_grid,
		atlas
	)


func get_gameplay_rotation_blend_set(
	tile_id: StringName,
	tier: int,
	rotation_progress: float,
) -> Dictionary:
	var empty := {
		"atlas": null,
		"layer_index": Vector4.ZERO,
		"weights": Vector4.ZERO,
	}
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return empty
	var blend_entries := compute_gameplay_rotation_blend(rotation_progress)
	var atlas: Texture2DArray = _gameplay_rotation_atlas_by_key.get(base_key, null)
	return _gameplay_blend_dict_pack_rotation(tile_id, tier, blend_entries, atlas)


func get_gameplay_rotation_axis_blend_set(
	tile_id: StringName,
	tier: int,
	axis: StringName,
	rotation_progress: float,
) -> Dictionary:
	var empty := {
		"atlas": null,
		"layer_index": Vector4.ZERO,
		"weights": Vector4.ZERO,
	}
	var base_key := _resolve_gameplay_texture_base_key(tile_id, tier)
	if base_key == &"":
		return empty
	var blend_entries := compute_gameplay_rotation_axis_blend(axis, rotation_progress)
	var atlas: Texture2DArray = _gameplay_rotation_atlas_by_key.get(base_key, null)
	return _gameplay_blend_dict_pack_rotation(tile_id, tier, blend_entries, atlas)


func compute_gameplay_lighting_blend(normalized_position: Vector2) -> Array[Dictionary]:
	var settings := get_gameplay_variant_settings()
	var baked_grid: Vector2i = settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	if baked_grid.x <= 0 or baked_grid.y <= 0:
		return []
	var runtime_grid := _get_runtime_lighting_grid_for_settings(settings)
	var clamped := Vector2(clampf(normalized_position.x, 0.0, 1.0), clampf(normalized_position.y, 0.0, 1.0))
	if runtime_grid.x <= 1 or runtime_grid.y <= 1:
		return [{
			"lighting_bin": _get_default_lighting_bin_for_settings(settings),
			"weight": 1.0,
		}]
	var scaled_x := clamped.x * float(runtime_grid.x - 1)
	var scaled_y := clamped.y * float(runtime_grid.y - 1)
	var x0 := clampi(int(floor(scaled_x)), 0, runtime_grid.x - 1)
	var y0 := clampi(int(floor(scaled_y)), 0, runtime_grid.y - 1)
	var x1 := mini(x0 + 1, runtime_grid.x - 1)
	var y1 := mini(y0 + 1, runtime_grid.y - 1)
	var tx := scaled_x - float(x0)
	var ty := scaled_y - float(y0)
	var raw_entries := [
		{
			"lighting_bin": _map_runtime_lighting_bin_to_baked(Vector2i(x0, y0), runtime_grid, baked_grid),
			"weight": (1.0 - tx) * (1.0 - ty),
		},
		{
			"lighting_bin": _map_runtime_lighting_bin_to_baked(Vector2i(x1, y0), runtime_grid, baked_grid),
			"weight": tx * (1.0 - ty),
		},
		{
			"lighting_bin": _map_runtime_lighting_bin_to_baked(Vector2i(x0, y1), runtime_grid, baked_grid),
			"weight": (1.0 - tx) * ty,
		},
		{
			"lighting_bin": _map_runtime_lighting_bin_to_baked(Vector2i(x1, y1), runtime_grid, baked_grid),
			"weight": tx * ty,
		},
	]
	return _merge_variant_weight_entries(raw_entries, "lighting_bin")


func compute_gameplay_rotation_blend(rotation_progress: float) -> Array[Dictionary]:
	var rotation_view_count := _get_rotation_view_count()
	if rotation_view_count <= 0:
		return []
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
	var settings := GemTracedBakeContractScript.normalize_variant_settings(_gameplay_variant_settings)
	settings["rotation_bin_count"] = _get_rotation_view_count(settings)
	settings["rotation_views"] = get_gameplay_rotation_view_descriptors(settings)
	settings["rotation_view_signature"] = _build_rotation_view_signature(settings)
	settings["default_lighting_bin"] = _get_default_lighting_bin_for_settings(settings)
	return settings


func set_gameplay_variant_settings(settings: Dictionary, invalidate_cache: bool = true) -> void:
	var normalized := _resolve_variant_settings(settings)
	if _gameplay_variant_settings == normalized:
		return
	_gameplay_variant_settings = normalized
	if invalidate_cache:
		_invalidate_gameplay_texture_cache_state()


func get_gameplay_lighting_grid_presets() -> Dictionary:
	return GemTracedBakeContractScript.get_lighting_grid_presets()


func set_gameplay_lighting_grid_preset(preset: StringName, invalidate_cache: bool = true) -> void:
	var updated := _gameplay_variant_settings.duplicate(true)
	updated["lighting_grid_preset"] = preset
	updated["lighting_grid_size"] = GemTracedBakeContractScript.resolve_lighting_grid_preset(preset)
	set_gameplay_variant_settings(updated, invalidate_cache)


func set_gameplay_virtual_lighting_grid_size(grid_size: Vector2i, refresh_views: bool = true) -> void:
	var updated := _gameplay_variant_settings.duplicate(true)
	updated["lighting_runtime_grid_size"] = grid_size
	set_gameplay_variant_settings(updated, false)
	if refresh_views and not _bake_in_progress:
		refresh_gameplay_texture_views()


func refresh_gameplay_texture_views() -> void:
	gameplay_texture_cache_rebuilt.emit(get_gameplay_texture_profile())


func reload_offline_traced_manifest(rebuild_current_cache: bool = true) -> void:
	var profile := get_gameplay_texture_profile()
	_sync_gameplay_variant_settings_from_offline_manifest(false)
	_invalidate_gameplay_texture_cache_state()
	if not rebuild_current_cache:
		return
	var cell_size: Vector2i = profile.get("cell_size", Vector2i.ZERO)
	if cell_size == Vector2i.ZERO:
		return
	ensure_gameplay_texture_cache(cell_size, profile.get("tile_scope", []))


func get_offline_traced_manifest_summary() -> Dictionary:
	var backend = _gameplay_bake_backends.get(GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED, null)
	if backend == null or not backend.has_method("get_manifest_summary"):
		return {
			"manifest_path": "",
			"cell_size": Vector2i.ZERO,
			"draw_size": Vector2i.ZERO,
			"variant_settings": get_gameplay_variant_settings(),
		}
	return backend.get_manifest_summary()


## Replace showroom lookup data for one tile (e.g. gem designer session bake).
func set_showroom_bake_session(tile_id: StringName, entries: Array) -> void:
	_showroom_cache[tile_id] = _pack_showroom_entries_for_tile(tile_id, entries)


func find_nearest_showroom_frames(
	tile_id: StringName,
	current_orientation: Quaternion,
	count: int = 4,
	frame_type_filter: StringName = &"",
) -> Array[Dictionary]:
	var pack: Dictionary = _showroom_cache.get(tile_id, {})
	var orientations: Array = pack.get("orientations", [])
	var textures: Array = pack.get("textures", [])
	var dir_idx: Array = pack.get("direction_indices", [])
	var roll_idx: Array = pack.get("roll_indices", [])
	var ftypes: Array = pack.get("frame_types", [])
	var sigma := float(pack.get("sigma", 0.35))
	if orientations.is_empty():
		return []
	var q_cur := current_orientation.normalized()
	count = clampi(count, 1, 4)
	var scored: Array[Dictionary] = []
	var n := orientations.size()
	for i in n:
		if frame_type_filter != &"" and i < ftypes.size():
			if ftypes[i] != frame_type_filter:
				continue
		var qi: Quaternion = orientations[i]
		var dot := absf(q_cur.dot(qi.normalized()))
		scored.append({"i": i, "dot": dot})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("dot", 0.0)) > float(b.get("dot", 0.0))
	)
	var take := mini(count, scored.size())
	var raw_weights: Array[float] = []
	for k in take:
		var it: Dictionary = scored[k]
		var dot: float = float(it.get("dot", 0.0))
		var ang := 2.0 * acos(clampf(dot, 0.0, 1.0))
		raw_weights.append(exp(-ang * ang / (2.0 * sigma * sigma)))
	var sum_w := 0.0
	for w in raw_weights:
		sum_w += w
	var out: Array[Dictionary] = []
	var uniform := 1.0 / float(maxi(take, 1))
	for k in take:
		var it: Dictionary = scored[k]
		var i: int = int(it.get("i", 0))
		var w := (raw_weights[k] / sum_w) if sum_w > 1e-10 else uniform
		var tex: Texture2D = null
		if i < textures.size():
			tex = textures[i]
		var d_i := int(dir_idx[i]) if i < dir_idx.size() else -1
		var r_i := int(roll_idx[i]) if i < roll_idx.size() else -1
		var ori: Quaternion = orientations[i] if i < orientations.size() else Quaternion.IDENTITY
		out.append({
			"texture": tex,
			"weight": w,
			"direction_index": d_i,
			"roll_index": r_i,
			"orientation": ori,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("weight", 0.0)) > float(b.get("weight", 0.0))
	)
	return out


func _refresh_showroom_cache_from_backend() -> void:
	var backend = _gameplay_bake_backends.get(GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED, null)
	if backend == null or not backend.has_method("get_manifest_entries_flat"):
		return
	var flat: Array = backend.get_manifest_entries_flat()
	_ingest_showroom_entries_from_manifest(flat)


func _ingest_showroom_entries_from_manifest(entries: Array) -> void:
	var by_tile: Dictionary = {}
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = raw
		if StringName(e.get("variant_type", &"")) != GAMEPLAY_VARIANT_TYPE_SHOWROOM:
			continue
		var tid: StringName = e.get("tile_id", &"")
		if tid == &"":
			continue
		if not by_tile.has(tid):
			by_tile[tid] = []
		(by_tile[tid] as Array).append(e)
	for tid in by_tile.keys():
		_showroom_cache[tid] = _pack_showroom_entries_for_tile(tid, by_tile[tid] as Array)


func _pack_showroom_entries_for_tile(_tile_id: StringName, entries: Array) -> Dictionary:
	var sorted: Array = entries.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
			return false
		var ad := int(a.get("showroom_direction_index", 0))
		var bd := int(b.get("showroom_direction_index", 0))
		if ad != bd:
			return ad < bd
		return int(a.get("showroom_roll_index", 0)) < int(b.get("showroom_roll_index", 0))
	)
	var orientations: Array[Quaternion] = []
	var textures: Array = []
	var direction_indices: Array[int] = []
	var roll_indices: Array[int] = []
	var frame_types: Array[StringName] = []
	for e in sorted:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = e
		var oa = ed.get("showroom_orientation", null)
		if oa is Array:
			var arr: Array = oa
			if arr.size() < 4:
				continue
			var qw := float(arr[0])
			var qx := float(arr[1])
			var qy := float(arr[2])
			var qz := float(arr[3])
			orientations.append(Quaternion(qx, qy, qz, qw))
		else:
			continue
		direction_indices.append(int(ed.get("showroom_direction_index", 0)))
		roll_indices.append(int(ed.get("showroom_roll_index", 0)))
		frame_types.append(StringName(ed.get("showroom_frame_type", &"orbit")))
		textures.append(_load_showroom_texture_from_path(String(ed.get("texture_path", ""))))
	var sigma := _compute_showroom_sigma(orientations)
	return {
		"orientations": orientations,
		"textures": textures,
		"direction_indices": direction_indices,
		"roll_indices": roll_indices,
		"frame_types": frame_types,
		"sigma": sigma,
	}


func _load_showroom_texture_from_path(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var gpath := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(gpath):
		return null
	var img := Image.load_from_file(gpath)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _compute_showroom_sigma(orientations: Array[Quaternion]) -> float:
	var n := orientations.size()
	if n <= 1:
		return 0.35
	var sum_nn := 0.0
	for i in n:
		var best_dot := -1.0
		var qi := orientations[i]
		for j in n:
			if i == j:
				continue
			var d := absf(qi.dot(orientations[j]))
			best_dot = maxf(best_dot, d)
		var ang := 2.0 * acos(clampf(best_dot, 0.0, 1.0))
		sum_nn += ang
	var mean_angle := sum_nn / float(n)
	return mean_angle * 1.5


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


func get_gameplay_rotation_view_descriptors_for_axis(
	axis: StringName,
	options: Dictionary = {}
) -> Array[Dictionary]:
	var axis_descriptors: Array[Dictionary] = []
	for descriptor in get_gameplay_rotation_view_descriptors(options):
		if descriptor.get("axis", &"") == axis:
			axis_descriptors.append(descriptor)
	return axis_descriptors


func compute_gameplay_rotation_axis_blend(
	axis: StringName,
	rotation_progress: float,
	options: Dictionary = {}
) -> Array[Dictionary]:
	var descriptors := get_gameplay_rotation_view_descriptors_for_axis(axis, options)
	if descriptors.is_empty():
		return []
	if descriptors.size() == 1:
		return [{
			"rotation_bin": descriptors[0].get("rotation_bin", 0),
			"weight": 1.0,
		}]
	var wrapped := fposmod(rotation_progress, 1.0)
	var scaled := wrapped * float(descriptors.size())
	var low_index := int(floor(scaled)) % descriptors.size()
	var frac: float = scaled - floor(scaled)
	var high_index := (low_index + 1) % descriptors.size()
	if is_zero_approx(frac):
		return [{
			"rotation_bin": descriptors[low_index].get("rotation_bin", 0),
			"weight": 1.0,
		}]
	return [
		{
			"rotation_bin": descriptors[low_index].get("rotation_bin", 0),
			"weight": 1.0 - frac,
		},
		{
			"rotation_bin": descriptors[high_index].get("rotation_bin", 0),
			"weight": frac,
		},
	]


func compute_gameplay_light_dir(lighting_bin: Vector2i) -> Vector3:
	return _compute_variant_light_dir(lighting_bin)


func build_gameplay_bake_requests_for_tile(
	tile_id: StringName,
	draw_size: Vector2i,
	target_size: Vector2i = Vector2i.ZERO,
	variant_options: Dictionary = {},
) -> Array[Dictionary]:
	var visual = get_visual(tile_id)
	if visual == null:
		return []
	var cut = get_visual_cut(visual)
	var cut_model = get_visual_cut_model(visual)
	if cut == null:
		return []
	if cut_model == null:
		return []
	if target_size == Vector2i.ZERO:
		target_size = draw_size
	return _build_gameplay_bake_requests(tile_id, visual, cut_model, cut, draw_size, target_size, variant_options)


## Build bake requests from an explicit visual + geometry (designer / tooling; no registry tile required).
func build_explicit_bake_requests(
	tile_id: StringName,
	visual: GemVisualResource,
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
	options: Dictionary = {},
) -> Array[Dictionary]:
	if visual == null or cut_model == null or cut == null:
		return []
	if target_size == Vector2i.ZERO:
		target_size = draw_size
	var view_scale := _compute_trace_view_scale(visual, cut_model)
	var variant_settings := _resolve_variant_settings(options.get("variant_settings", {}))
	var out: Array[Dictionary] = []
	if bool(options.get("include_lighting", true)):
		out.append_array(_collect_lighting_bake_requests(
			tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale
		))
	if bool(options.get("include_rotation_suite", true)):
		out.append_array(_collect_rotation_bake_requests(
			tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale
		))
	var showroom_axis_steps := int(options.get("showroom_axis_steps", 0))
	if showroom_axis_steps > 0:
		out.append_array(_collect_showroom_axis_requests(
			tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale, showroom_axis_steps
		))
	var showroom_dirs := int(options.get("showroom_direction_count", 0))
	if bool(options.get("include_showroom", false)) and showroom_dirs <= 0:
		showroom_dirs = 200
	if showroom_dirs > 0:
		out.append_array(_collect_showroom_bake_requests(
			tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale, options, showroom_dirs
		))
	return out


## Single crown (top-down) traced frame for live designer preview.
func build_designer_preview_crown_request(
	tile_id: StringName,
	visual: GemVisualResource,
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
) -> Dictionary:
	if visual == null or cut_model == null or cut == null:
		return {}
	if target_size == Vector2i.ZERO:
		target_size = draw_size
	var view_scale := _compute_trace_view_scale(visual, cut_model)
	var variant_settings := _resolve_variant_settings({
		"lighting_grid_size": GemTracedBakeContractScript.DEFAULT_LIGHTING_GRID_SIZE,
	})
	var lighting_bin := _get_default_lighting_bin_for_settings(variant_settings)
	var lighting_uv := _lighting_bin_to_centered(lighting_bin, variant_settings)
	var cut_key := get_visual_cut_key(visual)
	var rotation_view: Dictionary = _make_rotation_view("crown", 0.0, 0.0, 0.0)
	var view_pitch := float(rotation_view.get("view_pitch_degrees", 0.0))
	var view_yaw := float(rotation_view.get("view_yaw_degrees", 0.0))
	var view_roll := float(rotation_view.get("view_roll_degrees", 0.0))
	var rotation_label := StringName(rotation_view.get("label", "crown"))
	match rotation_label:
		&"crown", &"pavilion":
			view_roll += cut_model.orthographic_top_roll_degrees
		_:
			view_yaw += cut_model.orthographic_side_yaw_degrees
	return {
		"tile_id": tile_id,
		"visual_id": visual.visual_id,
		"spec_id": cut.spec_id,
		"geometry_signature": cut.geometry_signature,
		"cut_id": cut.cut_id,
		"visual": visual,
		"cut_model": cut_model,
		"cut": cut,
		"draw_size": draw_size,
		"target_size": target_size,
		"geometry_source": &"canonical_3d",
		"variant_type": GAMEPLAY_VARIANT_TYPE_ROTATION,
		"variant_key": _make_gameplay_variant_cache_key(
			tile_id,
			GAMEPLAY_VARIANT_TYPE_ROTATION,
			Vector2i(-1, -1),
			0
		),
		"cut_key_override": cut_key,
		"rotation_bin": 0,
		"rotation_label": rotation_label,
		"rotation_axis": rotation_view.get("axis", &""),
		"rotation_degrees": 0.0,
		"view_pitch_degrees": view_pitch,
		"view_yaw_degrees": view_yaw,
		"view_roll_degrees": view_roll,
		"light_dir": _compute_variant_light_dir(lighting_bin, variant_settings),
		"lighting_uv": lighting_uv,
		"lighting_bin": lighting_bin,
		"view_scale": view_scale,
	}


func _resolve_gameplay_texture_base_key(tile_id: StringName, tier: int = -1) -> StringName:
	if _gameplay_texture_cache.has(_make_gameplay_variant_cache_key(
		tile_id,
		GAMEPLAY_VARIANT_TYPE_LIGHTING,
		_get_default_lighting_bin()
	)) or _gameplay_texture_cache.has(_make_gameplay_variant_cache_key(
		tile_id,
		GAMEPLAY_VARIANT_TYPE_ROTATION,
		Vector2i(-1, -1),
		0
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
		)) or _gameplay_texture_cache.has(_make_gameplay_variant_cache_key(
			tier_key,
			GAMEPLAY_VARIANT_TYPE_ROTATION,
			Vector2i(-1, -1),
			0
		)):
			return tier_key
	return &""


func get_gameplay_texture_profile() -> Dictionary:
	return _gameplay_texture_profile.duplicate(true)


func get_last_gameplay_bake_report() -> Dictionary:
	return _last_gameplay_bake_report.duplicate(true)


func is_gameplay_texture_cache_current(
	draw_size: Vector2i,
	tile_scope = [],
) -> bool:
	var norm := _normalize_tile_scope(tile_scope)
	if norm.is_empty() and not _gameplay_run_tile_scope.is_empty():
		norm = _gameplay_run_tile_scope
	return _is_gameplay_profile_current(draw_size, norm) and not _bake_in_progress


## Restricts gameplay texture loading to the given tile IDs for the active run.
## When the set changes, cached traced variants and atlases are invalidated; callers
## should then warm the cache via [method ensure_gameplay_texture_cache] (e.g. from [BoardScene]).
func load_run_gems(tile_ids: Array, _cell_size: Vector2i = Vector2i.ZERO) -> void:
	var norm := _normalize_tile_scope(tile_ids)
	if norm.is_empty():
		return
	_gem_atlas_run_cache.set_active_tile_ids(norm)
	if norm == _gameplay_run_tile_scope_previous:
		_gameplay_run_tile_scope = norm
		return
	_gameplay_run_tile_scope_previous = norm
	_gameplay_run_tile_scope = norm
	_invalidate_gameplay_texture_cache_state()


## Clears run scoping and drops all gameplay traced texture caches (return to menu / teardown).
func unload_run_gameplay_textures() -> void:
	_gameplay_run_tile_scope = PackedStringArray()
	_gameplay_run_tile_scope_previous = PackedStringArray()
	_gem_atlas_run_cache.clear()
	_invalidate_gameplay_texture_cache_state()


func get_gameplay_run_tile_scope() -> PackedStringArray:
	return _gameplay_run_tile_scope


## Best-effort BC7-sized estimate from built atlases for gems in the active run scope.
func estimate_gameplay_run_vram_bytes() -> int:
	var total := 0
	for tid in _gameplay_run_tile_scope:
		var lat: Texture2DArray = _gameplay_lighting_atlas_by_key.get(tid, null)
		var rat: Texture2DArray = _gameplay_rotation_atlas_by_key.get(tid, null)
		if lat != null:
			total += GemAtlasCacheScript.estimate_bc7_atlas_bytes(
				lat.get_layers(),
				lat.get_width(),
				lat.get_height()
			)
		if rat != null:
			total += GemAtlasCacheScript.estimate_bc7_atlas_bytes(
				rat.get_layers(),
				rat.get_width(),
				rat.get_height()
			)
	return total


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
	_sync_gameplay_variant_settings_from_offline_manifest(false)
	var normalized_scope := _normalize_tile_scope(tile_scope)
	if normalized_scope.is_empty() and not _gameplay_run_tile_scope.is_empty():
		normalized_scope = _gameplay_run_tile_scope
	if _is_gameplay_profile_current(draw_size, normalized_scope):
		return
	if _bake_in_progress:
		_pending_bake_draw_size = draw_size
		_pending_bake_tile_scope = normalized_scope
		return

	var bake_render_size := _make_bake_render_size(draw_size)
	_bake_started_usec = Time.get_ticks_usec()
	_bake_warmup_elapsed_ms = 0.0
	_bake_queue_build_elapsed_ms = 0.0
	if _should_preload_procedural_runtime_assets():
		var warmup_start_usec := Time.get_ticks_usec()
		preload_runtime_assets([draw_size, bake_render_size])
		_bake_warmup_elapsed_ms = (Time.get_ticks_usec() - warmup_start_usec) / 1000.0
	var can_extend_scope := _can_extend_gameplay_texture_profile(draw_size, normalized_scope)
	var cached_scope_before_update := _normalize_tile_scope(_gameplay_texture_profile.get("tile_scope", []))
	var queue_scope := normalized_scope
	if can_extend_scope:
		queue_scope = _compute_missing_tile_scope(normalized_scope, cached_scope_before_update)
	if not can_extend_scope:
		_gameplay_texture_cache.clear()
		_gameplay_texture_metadata_cache.clear()
		_gameplay_lighting_atlas_by_key.clear()
		_gameplay_rotation_atlas_by_key.clear()
		_gameplay_texture_profile = {
			"cell_size": draw_size,
			"backend_id": GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED,
			"lighting_grid_size": get_gameplay_variant_settings().get(
				"lighting_grid_size",
				DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
			),
			"rotation_bin_count": _get_rotation_view_count(),
			"rotation_view_signature": _build_rotation_view_signature(),
			"tile_scope": normalized_scope,
		}
	else:
		_gameplay_texture_profile["tile_scope"] = _merge_tile_scopes(
			_gameplay_texture_profile.get("tile_scope", PackedStringArray()),
			normalized_scope
		)
	_bake_draw_size = bake_render_size
	_bake_queue = []
	if queue_scope.is_empty() and not normalized_scope.is_empty():
		_bake_started_usec = 0
		return
	var queue_build_start_usec := Time.get_ticks_usec()
	if queue_scope.is_empty():
		for tile_id in _visuals:
			var visual: GemVisualResource = _visuals[tile_id]
			var cut = get_visual_cut(visual)
			var cut_model = get_visual_cut_model(visual)
			if cut == null or cut_model == null:
				continue
			_bake_queue.append_array(_build_gameplay_bake_requests(
				tile_id,
				visual,
				cut_model,
				cut,
				_bake_draw_size,
				draw_size,
				{}
			))
	else:
		for tile_id in queue_scope:
			var scoped_tile_id := StringName(tile_id)
			if not _visuals.has(scoped_tile_id):
				continue
			var visual: GemVisualResource = _visuals[scoped_tile_id]
			var cut = get_visual_cut(visual)
			var cut_model = get_visual_cut_model(visual)
			if cut == null or cut_model == null:
				continue
			_bake_queue.append_array(_build_gameplay_bake_requests(
				scoped_tile_id,
				visual,
				cut_model,
				cut,
				_bake_draw_size,
				draw_size,
				{}
			))
	_bake_queue_build_elapsed_ms = (Time.get_ticks_usec() - queue_build_start_usec) / 1000.0
	_bake_in_progress = true
	_bake_current_tile_id = &""
	_current_bake_request = {}
	_bake_total_requests = _bake_queue.size()
	_bake_completed_requests = 0
	_begin_bake_report(draw_size, bake_render_size)
	_prefetch_bake_requests(_bake_queue)
	_emit_bake_progress("queued")
	_queue_next_bake_step()


## Returns cached [facet_colors, pavilion_colors] for the given cache key.
## Computes and caches on first call; subsequent calls return the cached arrays.
## cache_key should be tile_id for normal gems, or a synthetic key for fallback paths.
func get_cached_colors(
	cache_key: StringName,
	cut,
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
	cut,
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
func get_cached_scaled_geometry(cut, cut_key: String, draw_size: Vector2i) -> Dictionary:
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
func preload_runtime_assets(
	draw_sizes: Array[Vector2i] = [],
	include_tier_aliases: bool = false,
) -> void:
	_pre_warm_colors(include_tier_aliases)
	for draw_size in draw_sizes:
		if draw_size.x <= 0 or draw_size.y <= 0:
			continue
		for tile_id in _visuals:
			var visual: GemVisualResource = _visuals[tile_id]
			var cut = get_visual_cut(visual)
			if cut != null:
				get_cached_render_data(tile_id, cut, visual, draw_size)
				var tier := _resolve_visual_tier(tile_id)
				if include_tier_aliases and tier > 0:
					get_cached_render_data(StringName("_tier_%d" % tier), cut, visual, draw_size)


## Clears the color cache. Call if visual parameters change at runtime
## (for example when previewing alternate traced bake manifests in tooling).
func invalidate_color_cache() -> void:
	_color_cache.clear()
	_render_cache.clear()
	_scaled_geometry_cache.clear()
	_cut_model_variants.clear()
	_cut_variants.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_lighting_atlas_by_key.clear()
	_gameplay_rotation_atlas_by_key.clear()
	_gameplay_texture_profile.clear()
	_last_gameplay_bake_report.clear()


## Clears the scaled-geometry and render bundle caches.
func invalidate_render_cache() -> void:
	_scaled_geometry_cache.clear()
	_render_cache.clear()
	_cut_model_variants.clear()
	_cut_variants.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_lighting_atlas_by_key.clear()
	_gameplay_rotation_atlas_by_key.clear()
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
	for visual_id in _visuals:
		var vis: GemVisualResource = _visuals[visual_id]
		_ensure_visual_geometry_cached(vis)

	if not _cuts.is_empty():
		print("GemVisualRegistry: Generated %d canonical cut models" % _cuts.size())


func _initialize_bake_backends() -> void:
	_shutdown_bake_backends()
	var offline_traced := GameplayBakeBackendOfflineTracedScript.new()
	offline_traced.vram_compress_on_load = GemTracedBakeContract.VRAM_COMPRESS_ON_LOAD
	offline_traced.vram_compress_min_size = GemTracedBakeContract.VRAM_COMPRESS_MIN_SIZE
	offline_traced.vram_compress_desktop_format = GemTracedBakeContract.VRAM_COMPRESS_FORMAT
	_register_bake_backend(offline_traced)


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
			"backend_id": GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED,
			"tile_scope": _gameplay_texture_profile.get("tile_scope", PackedStringArray()),
		},
		"tile_metrics": [],
		"backend_counts": {},
		"total_elapsed_ms": 0.0,
		"warmup_elapsed_ms": _bake_warmup_elapsed_ms,
		"queue_build_elapsed_ms": _bake_queue_build_elapsed_ms,
		"texture_load_elapsed_ms": 0.0,
		"prefetch_elapsed_ms": 0.0,
		"prefetched_texture_count": 0,
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
	_last_gameplay_bake_report["texture_load_elapsed_ms"] = float(
		_last_gameplay_bake_report.get("texture_load_elapsed_ms", 0.0)
	) + float(metric.get("texture_load_elapsed_ms", 0.0))


func _get_default_lighting_bin() -> Vector2i:
	return _get_default_lighting_bin_for_settings(get_gameplay_variant_settings())


func _get_default_lighting_bin_for_settings(settings: Dictionary) -> Vector2i:
	var lighting_grid: Vector2i = settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	if lighting_grid.x <= 0 or lighting_grid.y <= 0:
		return Vector2i.ZERO
	return Vector2i(
		int(floor(float(lighting_grid.x - 1) * 0.5)),
		int(floor(float(lighting_grid.y - 1) * 0.5))
	)


func _get_runtime_lighting_grid_for_settings(settings: Dictionary) -> Vector2i:
	var lighting_grid: Vector2i = settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	if lighting_grid == Vector2i.ZERO:
		return Vector2i.ZERO
	var runtime_grid := GemTracedBakeContractScript.normalize_size(
		settings.get("lighting_runtime_grid_size", lighting_grid),
		lighting_grid
	)
	runtime_grid.x = clampi(runtime_grid.x, 1, lighting_grid.x)
	runtime_grid.y = clampi(runtime_grid.y, 1, lighting_grid.y)
	return runtime_grid


func _map_runtime_lighting_bin_to_baked(
	runtime_bin: Vector2i,
	runtime_grid: Vector2i,
	baked_grid: Vector2i,
) -> Vector2i:
	return Vector2i(
		_map_lighting_bin_axis(runtime_bin.x, runtime_grid.x, baked_grid.x),
		_map_lighting_bin_axis(runtime_bin.y, runtime_grid.y, baked_grid.y)
	)


func _map_lighting_bin_axis(index: int, source_count: int, target_count: int) -> int:
	if target_count <= 1:
		return 0
	if source_count <= 1:
		@warning_ignore("INTEGER_DIVISION")
		return clampi((target_count - 1) / 2, 0, target_count - 1)
	var normalized := float(clampi(index, 0, source_count - 1)) / float(source_count - 1)
	return clampi(int(round(normalized * float(target_count - 1))), 0, target_count - 1)


func _make_gameplay_variant_cache_key(
	base_key: StringName,
	variant_type: StringName,
	lighting_bin: Vector2i = Vector2i(-1, -1),
	rotation_bin: int = -1,
) -> StringName:
	match variant_type:
		GAMEPLAY_VARIANT_TYPE_ROTATION:
			return StringName("%s@rot_%02d" % [String(base_key), maxi(rotation_bin, 0)])
		GAMEPLAY_VARIANT_TYPE_SHOWROOM:
			return StringName("%s@showroom_d%03d_r%02d" % [
				String(base_key),
				maxi(lighting_bin.x, 0),
				maxi(lighting_bin.y, 0),
			])
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
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
	variant_options: Dictionary = {},
) -> Array[Dictionary]:
	var view_scale := _compute_trace_view_scale(visual, cut_model)
	var variant_settings := _resolve_variant_settings(variant_options)
	var requests: Array[Dictionary] = []
	requests.append_array(_collect_lighting_bake_requests(
		tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale
	))
	requests.append_array(_collect_rotation_bake_requests(
		tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale
	))
	var showroom_n := int(variant_settings.get("showroom_direction_count", 0))
	if showroom_n > 0:
		requests.append_array(_collect_showroom_bake_requests(
			tile_id, visual, cut_model, cut, draw_size, target_size, variant_settings, view_scale, {}, showroom_n
		))
	return requests


func _collect_lighting_bake_requests(
	tile_id: StringName,
	visual: GemVisualResource,
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
	variant_settings: Dictionary,
	view_scale: float,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var lighting_grid: Vector2i = variant_settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	var rig_config: Dictionary = variant_settings.get("lighting_rig", {})
	if lighting_grid.x > 0 and lighting_grid.y > 0:
		for y in lighting_grid.y:
			for x in lighting_grid.x:
				var lighting_bin := Vector2i(x, y)
				var lighting_uv := _lighting_bin_to_centered(lighting_bin, variant_settings)
				var request := {
					"tile_id": tile_id,
					"visual_id": visual.visual_id,
					"spec_id": cut.spec_id,
					"geometry_signature": cut.geometry_signature,
					"cut_id": cut.cut_id,
					"visual": visual,
					"cut_model": cut_model,
					"cut": cut,
					"draw_size": draw_size,
					"target_size": target_size,
					"geometry_source": &"canonical_3d",
					"variant_type": GAMEPLAY_VARIANT_TYPE_LIGHTING,
					"variant_key": _make_gameplay_variant_cache_key(
						tile_id,
						GAMEPLAY_VARIANT_TYPE_LIGHTING,
						lighting_bin
					),
					"cut_key_override": get_visual_cut_key(visual),
					"lighting_bin": lighting_bin,
					"lighting_grid_size": lighting_grid,
					"lighting_uv": lighting_uv,
					"light_dir": _compute_variant_light_dir(lighting_bin, variant_settings),
					"view_scale": view_scale,
				}
				if not rig_config.is_empty():
					var perturbed := _build_perturbed_environment_profile(
						visual, lighting_bin, lighting_grid, rig_config
					)
					if not perturbed.is_empty():
						request["environment_profile"] = perturbed
				requests.append(request)
	return requests


func _collect_rotation_bake_requests(
	tile_id: StringName,
	visual: GemVisualResource,
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
	variant_settings: Dictionary,
	view_scale: float,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var rotation_views := _build_rotation_view_suite(variant_settings)
	var cut_key := get_visual_cut_key(visual)
	for rotation_bin in rotation_views.size():
		var rotation_view: Dictionary = rotation_views[rotation_bin]
		var view_pitch := float(rotation_view.get("view_pitch_degrees", 0.0))
		var view_yaw := float(rotation_view.get("view_yaw_degrees", 0.0))
		var view_roll := float(rotation_view.get("view_roll_degrees", 0.0))
		var rotation_label := StringName(rotation_view.get("label", "rot_%02d" % rotation_bin))
		match rotation_label:
			&"crown", &"pavilion":
				view_roll += cut_model.orthographic_top_roll_degrees
			_:
				view_yaw += cut_model.orthographic_side_yaw_degrees
		requests.append({
			"tile_id": tile_id,
			"visual_id": visual.visual_id,
			"spec_id": cut.spec_id,
			"geometry_signature": cut.geometry_signature,
			"cut_id": cut.cut_id,
			"visual": visual,
			"cut_model": cut_model,
			"cut": cut,
			"draw_size": draw_size,
			"target_size": target_size,
			"geometry_source": &"canonical_3d",
			"variant_type": GAMEPLAY_VARIANT_TYPE_ROTATION,
			"variant_key": _make_gameplay_variant_cache_key(
				tile_id,
				GAMEPLAY_VARIANT_TYPE_ROTATION,
				Vector2i(-1, -1),
				rotation_bin
			),
			"cut_key_override": cut_key,
			"rotation_bin": rotation_bin,
			"rotation_label": rotation_label,
			"rotation_axis": rotation_view.get("axis", &""),
			"rotation_degrees": 0.0,
			"view_pitch_degrees": view_pitch,
			"view_yaw_degrees": view_yaw,
			"view_roll_degrees": view_roll,
			"light_dir": _compute_variant_light_dir(_get_default_lighting_bin_for_settings(variant_settings), variant_settings),
			"view_scale": view_scale,
			"uniform_projection": true,
		})
	return requests


func _collect_showroom_axis_requests(
	tile_id: StringName,
	visual: GemVisualResource,
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
	variant_settings: Dictionary,
	view_scale: float,
	axis_steps: int,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	axis_steps = clampi(axis_steps, 1, 360)
	var cut_key := get_visual_cut_key(visual)
	var default_light := _get_default_lighting_bin_for_settings(variant_settings)
	var light_dir := _compute_variant_light_dir(default_light, variant_settings)
	# Two axes: pitch (X) and yaw (Y). Each gets axis_steps evenly spaced frames.
	var axes: Array[Dictionary] = [
		{"axis": Vector3.RIGHT, "frame_type": "pitch", "label_prefix": "pitch"},
		{"axis": Vector3.UP, "frame_type": "yaw", "label_prefix": "yaw"},
	]
	for ax_def in axes:
		var axis: Vector3 = ax_def["axis"]
		var frame_type: String = ax_def["frame_type"]
		var label_prefix: String = ax_def["label_prefix"]
		for i in axis_steps:
			var angle := TAU * float(i) / float(axis_steps)
			var q := Quaternion(axis, angle)
			var basis := Basis(q)
			var variant_key := StringName("%s@showroom_%s_%03d" % [
				String(tile_id), label_prefix, i
			])
			requests.append({
				"tile_id": tile_id,
				"visual_id": visual.visual_id,
				"spec_id": cut.spec_id,
				"geometry_signature": cut.geometry_signature,
				"cut_id": cut.cut_id,
				"visual": visual,
				"cut_model": cut_model,
				"cut": cut,
				"draw_size": draw_size,
				"target_size": target_size,
				"geometry_source": &"canonical_3d",
				"variant_type": GAMEPLAY_VARIANT_TYPE_SHOWROOM,
				"variant_key": variant_key,
				"cut_key_override": cut_key,
				"rotation_bin": axes.find(ax_def) * 1000 + i,
				"rotation_label": StringName("%s_%03d" % [label_prefix, i]),
				"rotation_axis": &"",
				"rotation_degrees": 0.0,
				"view_pitch_degrees": 0.0,
				"view_yaw_degrees": 0.0,
				"view_roll_degrees": 0.0,
				"light_dir": light_dir,
				"view_scale": view_scale,
				"view_basis_override": basis,
				"uniform_projection": true,
				"showroom_frame_type": frame_type,
				"showroom_direction_index": axes.find(ax_def) * 1000 + i,
				"showroom_roll_index": 0,
				"showroom_direction_count": axis_steps,
				"showroom_roll_steps": 1,
				"showroom_orientation": [q.w, q.x, q.y, q.z],
			})
	return requests


func _collect_showroom_bake_requests(
	tile_id: StringName,
	visual: GemVisualResource,
	cut_model,
	cut,
	draw_size: Vector2i,
	target_size: Vector2i,
	variant_settings: Dictionary,
	view_scale: float,
	options: Dictionary,
	direction_count: int,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var roll_steps := int(options.get("showroom_roll_steps", variant_settings.get("showroom_roll_steps", 6)))
	roll_steps = clampi(roll_steps, 1, 64)
	var n := clampi(
		direction_count,
		GemViewSphereSamplingScript.MIN_FIBONACCI_POINTS,
		GemViewSphereSamplingScript.MAX_FIBONACCI_POINTS
	)
	var dirs := GemViewSphereSamplingScript.build_fibonacci_unit_vectors(n)
	var cut_key := get_visual_cut_key(visual)
	var default_light := _get_default_lighting_bin_for_settings(variant_settings)
	var light_dir := _compute_variant_light_dir(default_light, variant_settings)
	for i in dirs.size():
		for j in roll_steps:
			var roll_r := TAU * float(j) / float(roll_steps)
			var basis := GemViewSphereSamplingScript.build_showroom_orientation(dirs[i], roll_r)
			var q := Quaternion(basis)
			requests.append({
				"tile_id": tile_id,
				"visual_id": visual.visual_id,
				"spec_id": cut.spec_id,
				"geometry_signature": cut.geometry_signature,
				"cut_id": cut.cut_id,
				"visual": visual,
				"cut_model": cut_model,
				"cut": cut,
				"draw_size": draw_size,
				"target_size": target_size,
				"geometry_source": &"canonical_3d",
				"variant_type": GAMEPLAY_VARIANT_TYPE_SHOWROOM,
				"variant_key": _make_gameplay_variant_cache_key(
					tile_id,
					GAMEPLAY_VARIANT_TYPE_SHOWROOM,
					Vector2i(i, j),
					0
				),
				"cut_key_override": cut_key,
				"rotation_bin": i * roll_steps + j,
				"rotation_label": StringName("showroom_d%03d_r%02d" % [i, j]),
				"rotation_axis": &"",
				"rotation_degrees": 0.0,
				"view_pitch_degrees": 0.0,
				"view_yaw_degrees": 0.0,
				"view_roll_degrees": 0.0,
				"light_dir": light_dir,
				"view_scale": view_scale,
				"view_basis_override": basis,
				"uniform_projection": true,
				"showroom_frame_type": "orbit",
				"showroom_direction_index": i,
				"showroom_roll_index": j,
				"showroom_direction_count": n,
				"showroom_roll_steps": roll_steps,
				"showroom_orientation": [q.w, q.x, q.y, q.z],
			})
	return requests


func _get_rotation_view_count(settings: Dictionary = {}) -> int:
	return _build_rotation_view_suite(settings).size()


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
	var normalized := _resolve_variant_settings(options)
	var base_view_count := int(normalized.get(
		"rotation_base_view_count",
		DEFAULT_GAMEPLAY_BASE_ROTATION_VIEW_COUNT
	))
	var suite: Array[Dictionary] = [
		_make_rotation_view("crown", 0.0, 0.0, 0.0),
		_make_rotation_view("front", 90.0, 0.0, 0.0),
		_make_rotation_view("right", 0.0, 90.0, 0.0),
		_make_rotation_view("pavilion", 180.0, 0.0, 0.0),
		_make_rotation_view("left", 0.0, -90.0, 0.0),
		_make_rotation_view("back", -90.0, 0.0, 0.0),
	]
	if base_view_count <= 0:
		suite.clear()
	else:
		suite.resize(clampi(base_view_count, 0, suite.size()))
	var axis_steps := int(normalized.get("rotation_axis_steps", 0))
	if axis_steps <= 0:
		return suite
	var step_degrees := float(normalized.get("rotation_step_degrees", GAMEPLAY_ROTATION_DEFAULT_STEP_DEGREES))
	var axes: Array = normalized.get("rotation_axes", [])
	for raw_axis in axes:
		suite.append_array(_build_rotation_axis_sweep(StringName(raw_axis), axis_steps, step_degrees))
	return suite


func _resolve_variant_settings(options: Dictionary = {}) -> Dictionary:
	var merged := _gameplay_variant_settings.duplicate(true)
	for key in options.keys():
		merged[key] = options[key]
	if options.has("lighting_grid_preset") and not options.has("lighting_grid_size"):
		merged["lighting_grid_size"] = GemTracedBakeContractScript.resolve_lighting_grid_preset(
			options.get("lighting_grid_preset", GemTracedBakeContract.DEFAULT_LIGHTING_GRID_PRESET)
		)
	return GemTracedBakeContractScript.normalize_variant_settings(merged)


func _build_rotation_axis_sweep(axis: StringName, axis_steps: int, step_degrees: float) -> Array[Dictionary]:
	# Build views sorted by angle ascending: all negative angles first (most
	# negative to least), then all positive angles (least to most).  This
	# produces a monotonic sequence that plays smoothly as a sequential strip
	# instead of alternating negative/positive on every other frame.
	var views: Array[Dictionary] = []
	for step_index in range(axis_steps, 0, -1):
		var angle := step_degrees * float(step_index)
		views.append(_make_rotation_axis_view(axis, -angle, step_index, -1))
	for step_index in range(1, axis_steps + 1):
		var angle := step_degrees * float(step_index)
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


## Computes the light direction for a given lighting bin.
##
## The lighting grid maps each bin (x, y) to a centered UV in [-1, +1] via
## _lighting_bin_to_centered().  This UV drives TWO offsets that stack:
## 1. The global light direction is rotated by ±46° horizontally and ±30°
##    vertically relative to the base light dir (applied here).
## 2. GemTraceKernel.compute_surface_lighting() further offsets the
##    effective point-light origin by the same lighting_uv, creating a
##    position-dependent parallax shift on each facet.
## Both offsets use the same centered UV, so corner bins (e.g. 0,0 or 4,4
## in a 5x5 grid) have the most exaggerated combined variation.  The centre
## bin (2,2) is the neutral position where both offsets are zero.
func _compute_variant_light_dir(lighting_bin: Vector2i, settings: Dictionary = {}) -> Vector3:
	var rig_config: Dictionary = settings.get("lighting_rig", {})
	var base_dir: Vector3
	if rig_config.has("base_azimuth_degrees") or rig_config.has("base_elevation_degrees"):
		var azimuth := deg_to_rad(float(rig_config.get("base_azimuth_degrees", -28.0)))
		var elevation := deg_to_rad(float(rig_config.get("base_elevation_degrees", -30.0)))
		# Spherical to cartesian: azimuth=0 faces +Z, elevation=0 is horizontal
		base_dir = Vector3(
			sin(azimuth) * cos(elevation),
			sin(elevation),
			cos(azimuth) * cos(elevation)
		).normalized()
	else:
		base_dir = GemRenderer.DEFAULT_LIGHT_DIR.normalized()
	var sweep_x := float(rig_config.get("sweep_x_degrees", GAMEPLAY_LIGHTING_SWEEP_X_DEGREES))
	var sweep_y := float(rig_config.get("sweep_y_degrees", GAMEPLAY_LIGHTING_SWEEP_Y_DEGREES))
	var centered := _lighting_bin_to_centered(lighting_bin, settings)
	var yaw := Basis(Vector3.UP, deg_to_rad(centered.x * sweep_x))
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(-centered.y * sweep_y))
	return (yaw * pitch * base_dir).normalized()


func _lighting_bin_to_centered(lighting_bin: Vector2i, settings: Dictionary = {}) -> Vector2:
	var centered := Vector2.ZERO
	var resolved_settings := get_gameplay_variant_settings() if settings.is_empty() else settings
	var lighting_grid: Vector2i = resolved_settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	if lighting_grid.x > 1:
		centered.x = (float(lighting_bin.x) / float(lighting_grid.x - 1)) * 2.0 - 1.0
	if lighting_grid.y > 1:
		centered.y = (float(lighting_bin.y) / float(lighting_grid.y - 1)) * 2.0 - 1.0
	return centered


## Builds a per-bin perturbed environment profile for the multi-light rig system.
## Each lighting bin gets a deterministically different lighting setup by jittering
## card directions, strengths, and temperatures using a seed derived from the bin
## index.  Extra fill lights are generated at evenly distributed azimuth angles
## with per-bin positional jitter so that different bins see meaningfully different
## lighting rigs rather than a uniform directional sweep.
func _build_perturbed_environment_profile(
	visual: GemVisualResource,
	lighting_bin: Vector2i,
	lighting_grid: Vector2i,
	rig_config: Dictionary,
) -> Dictionary:
	var base_profile := GemEnvironmentPresets.resolve_preset(
		visual.optics_environment_preset if visual != null else 0
	)
	if rig_config.is_empty():
		return base_profile

	# Deterministic RNG per bin
	var rig_seed := int(rig_config.get("rig_seed", 42))
	var bin_index := lighting_bin.y * lighting_grid.x + lighting_bin.x
	var rng := RandomNumberGenerator.new()
	rng.seed = rig_seed * 100003 + bin_index * 7919

	var dir_jitter_deg := float(rig_config.get("direction_jitter_degrees", 8.0))
	var intensity_jitter := float(rig_config.get("intensity_jitter", 0.15))
	var temp_jitter_k := float(rig_config.get("temperature_jitter_kelvin", 200.0))
	var extra_fill_count := int(rig_config.get("extra_fill_count", 2))
	var fill_intensity := float(rig_config.get("fill_intensity", 0.35))
	var fill_jitter := float(rig_config.get("fill_jitter", 0.3))

	# Deep-copy the profile
	var profile := base_profile.duplicate(true)

	# Perturb existing cards
	var cards: Array = profile.get("cards", [])
	for card_index in cards.size():
		var card: Dictionary = cards[card_index]
		cards[card_index] = _perturb_card(card, rng, dir_jitter_deg, intensity_jitter, temp_jitter_k)

	# Generate extra fill lights distributed around the gem
	if extra_fill_count > 0 and fill_intensity > 0.0:
		var generated_fills := _generate_fill_cards(
			extra_fill_count, fill_intensity, fill_jitter, rng, temp_jitter_k
		)
		cards.append_array(generated_fills)

	profile["cards"] = cards
	return profile


## Perturbs a single light card's direction, strength, and temperature using the
## provided RNG.  The jitter is symmetric (centered on zero) so the average across
## many bins remains close to the original card values.
func _perturb_card(
	card: Dictionary,
	rng: RandomNumberGenerator,
	dir_jitter_deg: float,
	intensity_jitter: float,
	temp_jitter_k: float,
) -> Dictionary:
	var perturbed := card.duplicate(true)

	# Direction jitter: rotate the card direction by a random small angle
	if dir_jitter_deg > 0.0:
		var dir: Vector3 = perturbed.get("dir", Vector3(0, 0.3, 0.95))
		var jitter_yaw := deg_to_rad(rng.randf_range(-dir_jitter_deg, dir_jitter_deg))
		var jitter_pitch := deg_to_rad(rng.randf_range(-dir_jitter_deg * 0.7, dir_jitter_deg * 0.7))
		var yaw_basis := Basis(Vector3.UP, jitter_yaw)
		var pitch_basis := Basis(Vector3.RIGHT, jitter_pitch)
		perturbed["dir"] = (yaw_basis * pitch_basis * dir).normalized()

	# Intensity jitter: scale sharp/broad strength
	if intensity_jitter > 0.0:
		var scale_factor := 1.0 + rng.randf_range(-intensity_jitter, intensity_jitter)
		scale_factor = maxf(scale_factor, 0.05)
		if perturbed.has("sharp_strength"):
			perturbed["sharp_strength"] = float(perturbed["sharp_strength"]) * scale_factor
		if perturbed.has("broad_strength"):
			perturbed["broad_strength"] = float(perturbed["broad_strength"]) * scale_factor

	# Temperature jitter
	if temp_jitter_k > 0.0 and perturbed.has("temperature_kelvin"):
		var base_temp := float(perturbed["temperature_kelvin"])
		if base_temp > 0.0:
			var jittered := base_temp + rng.randf_range(-temp_jitter_k, temp_jitter_k)
			perturbed["temperature_kelvin"] = maxf(jittered, 2000.0)

	return perturbed


## Generates extra fill light cards distributed evenly in azimuth around the gem,
## with per-bin jitter applied to direction, intensity, and temperature.  Each
## fill sits at a different base azimuth angle so the combined rig provides
## multi-directional illumination that varies between bins.
func _generate_fill_cards(
	count: int,
	base_intensity: float,
	jitter_amount: float,
	rng: RandomNumberGenerator,
	temp_jitter_k: float,
) -> Array[Dictionary]:
	var fills: Array[Dictionary] = []
	var golden_angle := 2.399963  # radians, for even angular distribution
	for i in count:
		# Distribute fills around the upper hemisphere using golden angle
		var azimuth := golden_angle * float(i)
		var elevation := 0.15 + 0.25 * float(i) / maxf(float(count), 1.0)
		# Per-bin jitter on direction
		if jitter_amount > 0.0:
			azimuth += rng.randf_range(-jitter_amount * 1.2, jitter_amount * 1.2)
			elevation += rng.randf_range(-jitter_amount * 0.3, jitter_amount * 0.3)
		elevation = clampf(elevation, -0.2, 0.8)
		var dir := Vector3(sin(azimuth) * cos(elevation), elevation, cos(azimuth) * cos(elevation)).normalized()
		# Per-bin intensity jitter
		var sharp := base_intensity * (1.0 + rng.randf_range(-jitter_amount, jitter_amount))
		sharp = maxf(sharp, 0.02)
		var broad := sharp * 0.7
		# Temperature: warm-to-cool spread across fills with jitter
		var base_temp := 5200.0 + 400.0 * float(i)
		if temp_jitter_k > 0.0:
			base_temp += rng.randf_range(-temp_jitter_k * 0.5, temp_jitter_k * 0.5)
		base_temp = maxf(base_temp, 2500.0)
		fills.append({
			"dir": dir,
			"color": Color(0.96, 0.94, 0.98, 1.0),
			"sharp_power": 80.0 + rng.randf_range(-20.0, 20.0),
			"broad_power": 10.0 + rng.randf_range(-3.0, 3.0),
			"sharp_strength": sharp,
			"broad_strength": broad,
			"temperature_kelvin": base_temp,
			"edge_color": Color(0.92, 0.94, 1.0, 1.0),
			"gradient_power": 0.8,
		})
	return fills


## Computes a view scale factor for the traced bake camera.  Gems pre-rotated
## 45 degrees (diamond orientation) are slightly enlarged while axis-aligned
## square cuts are slightly reduced so that both occupy approximately the same
## visual area on the game board.  The per-visual optics_trace_view_scale is
## always respected as a base multiplier for area normalization across all
## cut families (triangles, ovals, pears, etc.).
func _compute_trace_view_scale(visual: GemVisualResource, cut_model) -> float:
	if visual == null or cut_model == null:
		return 1.0
	var base_scale := visual.optics_trace_view_scale
	var is_square_family = (
		cut_model.shape_category == &"square"
		or cut_model.orthographic_axis_fit_scale < 0.999
	)
	if not is_square_family:
		return base_scale
	var rotation := absf(fmod(visual.rotation_degrees, 90.0))
	var is_rotated_diamond := rotation > 30.0 and rotation < 60.0
	if is_rotated_diamond:
		return 1.08 * base_scale
	return cut_model.orthographic_axis_fit_scale * base_scale


## Eagerly computes and caches facet colors for all loaded gem types.
func _pre_warm_colors(include_tier_aliases: bool = false) -> void:
	if not _color_cache.is_empty():
		return
	for tile_id in _visuals:
		var visual: GemVisualResource = _visuals[tile_id]
		var cut = get_visual_cut(visual)
		if cut != null:
			get_cached_colors(tile_id, cut, visual)
			var tier := _resolve_visual_tier(tile_id)
			if include_tier_aliases and tier > 0:
				get_cached_colors(StringName("_tier_%d" % tier), cut, visual)
	if not _color_cache.is_empty():
		print("GemVisualRegistry: Pre-warmed %d color caches" % _color_cache.size())


func get_visual_cut_key(visual: GemVisualResource) -> String:
	if visual == null:
		return ""
	var geometry_key := _build_visual_geometry_key(visual)
	if geometry_key.is_empty():
		return ""
	return _make_cut_variant_key(geometry_key, visual.rotation_degrees)


func _build_visual_geometry_key(visual: GemVisualResource) -> String:
	if visual == null:
		return ""
	var spec = visual.resolve_cut_spec()
	if spec == null:
		return ""
	return spec.build_geometry_signature()


func _ensure_visual_geometry_cached(visual: GemVisualResource) -> String:
	var geometry_key := _build_visual_geometry_key(visual)
	if geometry_key.is_empty():
		return ""
	if _cut_models.has(geometry_key) and _cuts.has(geometry_key):
		return geometry_key
	var spec = visual.resolve_cut_spec()
	if spec == null:
		return ""
	var cut_model = GemCutCompiler3D.compile_spec(spec)
	if cut_model == null:
		return ""
	_cut_models[geometry_key] = cut_model
	_cuts[geometry_key] = GemCutProjectorScript.project(cut_model)
	return geometry_key


func _make_cut_variant_key(geometry_key: String, rotation_degrees: float) -> String:
	return "%s@rot_%s" % [geometry_key, String.num(snappedf(rotation_degrees, 0.001))]


func _make_scaled_geometry_key(cut_key: String, draw_size: Vector2i) -> String:
	return "%s@%dx%d" % [cut_key, draw_size.x, draw_size.y]


func _make_render_cache_key(cache_key: StringName, draw_size: Vector2i) -> String:
	return "%s@%dx%d" % [String(cache_key), draw_size.x, draw_size.y]


func _build_scaled_geometry(cut, draw_size: Vector2i) -> Dictionary:
	var size_v = Vector2(draw_size)
	var s = minf(size_v.x, size_v.y)
	var offset = (size_v - Vector2(s, s)) * 0.5

	var scaled_facets: Array[PackedVector2Array] = []
	scaled_facets.resize(cut.facet_count())
	for i in cut.facet_count():
		var verts = cut.facet_vertices[i]
		var scaled = PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		scaled_facets[i] = scaled

	var scaled_pavilion: Array[PackedVector2Array] = []
	scaled_pavilion.resize(cut.pavilion_count())
	for i in cut.pavilion_count():
		var verts = cut.pavilion_vertices[i]
		var scaled = PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		scaled_pavilion[i] = scaled

	var scaled_silhouette = PackedVector2Array()
	if cut.silhouette.size() >= 3:
		scaled_silhouette.resize(cut.silhouette.size() + 1)
		for j in cut.silhouette.size():
			scaled_silhouette[j] = cut.silhouette[j] * s + offset
		scaled_silhouette[cut.silhouette.size()] = scaled_silhouette[0]

	var scaled_edges = PackedVector2Array()
	for seg in cut.edge_segments:
		if seg.size() >= 2:
			scaled_edges.append(seg[0] * s + offset)
			scaled_edges.append(seg[1] * s + offset)

	var edge_aa_a = PackedVector2Array()
	var edge_aa_b = PackedVector2Array()
	var edge_aa_pairs = PackedInt32Array()
	if cut.edge_facet_a.size() == cut.edge_segments.size():
		for i in cut.edge_segments.size():
			var fa = cut.edge_facet_a[i]
			var fb = cut.edge_facet_b[i]
			if fa < 0 or fb < 0:
				continue
			var seg = cut.edge_segments[i]
			if seg.size() < 2:
				continue
			var a = seg[0] * s + offset
			var b = seg[1] * s + offset
			var dir = b - a
			var length = dir.length()
			if length < 4.0:
				continue
			var t = 1.5 / length
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
	var edge_aa_colors = PackedColorArray()
	var edge_aa_pairs: PackedInt32Array = geometry.get("edge_aa_pairs", PackedInt32Array())
	var pair_count = int(edge_aa_pairs.size() / 2.0)
	edge_aa_colors.resize(pair_count)
	for i in pair_count:
		var fa = edge_aa_pairs[i * 2]
		var fb = edge_aa_pairs[i * 2 + 1]
		if fa < 0 or fb < 0 or fa >= facet_colors.size() or fb >= facet_colors.size():
			edge_aa_colors[i] = Color(0, 0, 0, 0)
			continue
		var ca: Color = facet_colors[fa]
		var cb: Color = facet_colors[fb]
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


func _merge_tile_scopes(a, b) -> PackedStringArray:
	return _normalize_tile_scope(Array(a) + Array(b))


func _scope_covers_request(cached_scope: PackedStringArray, requested_scope: PackedStringArray) -> bool:
	if requested_scope.is_empty():
		return cached_scope.is_empty()
	if cached_scope.is_empty():
		return true
	var cached_lookup: Dictionary = {}
	for tile_id in cached_scope:
		cached_lookup[StringName(tile_id)] = true
	for tile_id in requested_scope:
		if not cached_lookup.has(StringName(tile_id)):
			return false
	return true


func _compute_missing_tile_scope(
	requested_scope: PackedStringArray,
	cached_scope_input = null
) -> PackedStringArray:
	var cached_scope := _normalize_tile_scope(
		_gameplay_texture_profile.get("tile_scope", []) if cached_scope_input == null else cached_scope_input
	)
	if requested_scope.is_empty():
		return requested_scope
	if cached_scope.is_empty():
		return requested_scope
	var missing: Array[String] = []
	var cached_lookup: Dictionary = {}
	for tile_id in cached_scope:
		cached_lookup[StringName(tile_id)] = true
	for tile_id in requested_scope:
		var scoped_tile_id := StringName(tile_id)
		if cached_lookup.has(scoped_tile_id):
			continue
		missing.append(String(scoped_tile_id))
	return PackedStringArray(missing)


func _can_extend_gameplay_texture_profile(draw_size: Vector2i, requested_scope: PackedStringArray) -> bool:
	if requested_scope.is_empty():
		return false
	if _gameplay_texture_cache.is_empty():
		return false
	var cached_scope := _normalize_tile_scope(_gameplay_texture_profile.get("tile_scope", []))
	if cached_scope.is_empty():
		return false
	var current_settings := get_gameplay_variant_settings()
	return _gameplay_texture_profile.get("cell_size", Vector2i.ZERO) == draw_size \
		and _gameplay_texture_profile.get("lighting_grid_size", Vector2i.ZERO) == current_settings.get("lighting_grid_size", Vector2i.ZERO) \
		and _gameplay_texture_profile.get("rotation_bin_count", -1) == current_settings.get("rotation_bin_count", -1) \
		and _gameplay_texture_profile.get("rotation_view_signature", "") == current_settings.get("rotation_view_signature", "")


func _should_preload_procedural_runtime_assets() -> bool:
	return false


func _invalidate_gameplay_texture_cache_state() -> void:
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_lighting_atlas_by_key.clear()
	_gameplay_rotation_atlas_by_key.clear()
	_gameplay_texture_profile.clear()
	_last_gameplay_bake_report.clear()


func _sync_gameplay_variant_settings_from_offline_manifest(
	invalidate_cache: bool = false
) -> Dictionary:
	var backend = _gameplay_bake_backends.get(GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED, null)
	if backend == null or not backend.has_method("get_manifest_variant_settings"):
		return get_gameplay_variant_settings()
	backend.reload_manifest()
	var manifest_settings: Dictionary = backend.get_manifest_variant_settings()
	set_gameplay_variant_settings(manifest_settings, invalidate_cache)
	_refresh_showroom_cache_from_backend()
	return get_gameplay_variant_settings()


func _is_gameplay_profile_current(
	draw_size: Vector2i,
	tile_scope = [],
) -> bool:
	if _gameplay_texture_cache.is_empty():
		return false
	var normalized_scope := _normalize_tile_scope(tile_scope)
	var cached_scope := _normalize_tile_scope(_gameplay_texture_profile.get("tile_scope", []))
	var current_settings := get_gameplay_variant_settings()
	return _gameplay_texture_profile.get("cell_size", Vector2i.ZERO) == draw_size \
		and _gameplay_texture_profile.get("lighting_grid_size", Vector2i.ZERO) == current_settings.get("lighting_grid_size", Vector2i.ZERO) \
		and _gameplay_texture_profile.get("rotation_bin_count", -1) == current_settings.get("rotation_bin_count", -1) \
		and _gameplay_texture_profile.get("rotation_view_signature", "") == current_settings.get("rotation_view_signature", "") \
		and _scope_covers_request(cached_scope, normalized_scope)


func _prefetch_bake_requests(requests: Array) -> void:
	if requests.is_empty():
		return
	var requests_by_backend: Dictionary = {}
	for request in requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		var backend = _select_bake_backend(request)
		if backend == null or not backend.has_method("prefetch_requests"):
			continue
		if not requests_by_backend.has(backend):
			requests_by_backend[backend] = []
		requests_by_backend[backend].append(request)
	for backend in requests_by_backend.keys():
		var prefetch_start_usec := Time.get_ticks_usec()
		var summary: Dictionary = backend.prefetch_requests(requests_by_backend[backend])
		var prefetch_elapsed_ms := (Time.get_ticks_usec() - prefetch_start_usec) / 1000.0
		if _last_gameplay_bake_report.is_empty():
			continue
		_last_gameplay_bake_report["prefetch_elapsed_ms"] = float(
			_last_gameplay_bake_report.get("prefetch_elapsed_ms", 0.0)
		) + float(summary.get("elapsed_ms", prefetch_elapsed_ms))
		_last_gameplay_bake_report["prefetched_texture_count"] = int(
			_last_gameplay_bake_report.get("prefetched_texture_count", 0)
		) + int(summary.get("texture_count", 0))


func _begin_next_bake_step() -> void:
	if _shutting_down:
		return
	while not _bake_queue.is_empty():
		var request: Dictionary = _bake_queue.pop_front()
		var tile_id: StringName = request.get("tile_id", &"")
		var visual: GemVisualResource = request.get("visual", null)
		if visual == null:
			continue
		var cut = request.get("cut", null)
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


func _collect_gameplay_atlas_base_keys() -> Array[StringName]:
	var seen: Dictionary = {}
	var out: Array[StringName] = []
	for cache_key_variant in _gameplay_texture_cache.keys():
		var ks := String(cache_key_variant)
		var at := ks.find("@")
		if at <= 0:
			continue
		var base := StringName(ks.substr(0, at))
		if seen.has(base):
			continue
		seen[base] = true
		out.append(base)
	return out


func _try_build_lighting_atlas_for_base_key(base_key: StringName) -> Texture2DArray:
	var settings := get_gameplay_variant_settings()
	var grid: Vector2i = settings.get(
		"lighting_grid_size",
		DEFAULT_GAMEPLAY_LIGHTING_GRID_SIZE
	)
	if grid.x <= 0 or grid.y <= 0:
		return null
	var w := 0
	var h := 0
	for y in grid.y:
		for x in grid.x:
			var bin := Vector2i(x, y)
			var tex: Texture2D = _gameplay_texture_cache.get(
				_make_gameplay_variant_cache_key(base_key, GAMEPLAY_VARIANT_TYPE_LIGHTING, bin),
				null
			)
			if tex != null:
				var sz: Vector2 = tex.get_size()
				w = maxi(w, int(round(sz.x)))
				h = maxi(h, int(round(sz.y)))
	if w <= 0 or h <= 0:
		return null
	var imgs: Array[Image] = []
	for y in grid.y:
		for x in grid.x:
			var bin2 := Vector2i(x, y)
			var tex2: Texture2D = _gameplay_texture_cache.get(
				_make_gameplay_variant_cache_key(base_key, GAMEPLAY_VARIANT_TYPE_LIGHTING, bin2),
				null
			)
			var im: Image = null
			if tex2 != null:
				im = tex2.get_image()
			if im == null:
				var blank := Image.create(w, h, false, Image.FORMAT_RGBA8)
				blank.fill(Color(0, 0, 0, 0))
				imgs.append(blank)
			else:
				if im.get_width() != w or im.get_height() != h:
					var dup := im.duplicate()
					dup.resize(w, h, Image.INTERPOLATE_BILINEAR)
					imgs.append(dup)
				else:
					imgs.append(im.duplicate())
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func _try_build_rotation_atlas_for_base_key(base_key: StringName) -> Texture2DArray:
	var bin_count := _get_rotation_view_count()
	if bin_count <= 0:
		return null
	var w := 0
	var h := 0
	for rotation_bin in bin_count:
		var tex: Texture2D = _gameplay_texture_cache.get(
			_make_gameplay_variant_cache_key(
				base_key,
				GAMEPLAY_VARIANT_TYPE_ROTATION,
				Vector2i(-1, -1),
				rotation_bin
			),
			null
		)
		if tex != null:
			var sz: Vector2 = tex.get_size()
			w = maxi(w, int(round(sz.x)))
			h = maxi(h, int(round(sz.y)))
	if w <= 0 or h <= 0:
		return null
	var imgs: Array[Image] = []
	for rotation_bin2 in bin_count:
		var tex_r: Texture2D = _gameplay_texture_cache.get(
			_make_gameplay_variant_cache_key(
				base_key,
				GAMEPLAY_VARIANT_TYPE_ROTATION,
				Vector2i(-1, -1),
				rotation_bin2
			),
			null
		)
		var im: Image = null
		if tex_r != null:
			im = tex_r.get_image()
		if im == null:
			var blank := Image.create(w, h, false, Image.FORMAT_RGBA8)
			blank.fill(Color(0, 0, 0, 0))
			imgs.append(blank)
		else:
			if im.get_width() != w or im.get_height() != h:
				var dup := im.duplicate()
				dup.resize(w, h, Image.INTERPOLATE_BILINEAR)
				imgs.append(dup)
			else:
				imgs.append(im.duplicate())
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func _rebuild_gameplay_texture_atlases() -> void:
	_gameplay_lighting_atlas_by_key.clear()
	_gameplay_rotation_atlas_by_key.clear()
	for base_key in _collect_gameplay_atlas_base_keys():
		var lat := _try_build_lighting_atlas_for_base_key(base_key)
		if lat != null:
			_gameplay_lighting_atlas_by_key[base_key] = lat
		var rat := _try_build_rotation_atlas_for_base_key(base_key)
		if rat != null:
			_gameplay_rotation_atlas_by_key[base_key] = rat


func _finish_bake_queue() -> void:
	_bake_in_progress = false
	_bake_current_tile_id = &""
	_current_bake_request = {}
	_bake_completed_requests = _bake_total_requests
	_rebuild_gameplay_texture_atlases()
	_last_gameplay_bake_report["profile"] = get_gameplay_texture_profile()
	_last_gameplay_bake_report["variant_texture_count"] = _gameplay_texture_cache.size()
	_last_gameplay_bake_report["total_wall_elapsed_ms"] = (
		(Time.get_ticks_usec() - _bake_started_usec) / 1000.0
		if _bake_started_usec > 0
		else 0.0
	)
	if not _last_gameplay_bake_report.is_empty():
		print(
			"GemVisualRegistry: Gameplay bake report  |  wall %.1fms  warmup %.1fms  queue %.1fms  prefetch %.1fms  load %.1fms  backend %.1fms  variants %d" % [
				float(_last_gameplay_bake_report.get("total_wall_elapsed_ms", 0.0)),
				float(_last_gameplay_bake_report.get("warmup_elapsed_ms", 0.0)),
				float(_last_gameplay_bake_report.get("queue_build_elapsed_ms", 0.0)),
				float(_last_gameplay_bake_report.get("prefetch_elapsed_ms", 0.0)),
				float(_last_gameplay_bake_report.get("texture_load_elapsed_ms", 0.0)),
				float(_last_gameplay_bake_report.get("total_elapsed_ms", 0.0)),
				int(_last_gameplay_bake_report.get("variant_texture_count", 0)),
			]
		)
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
	_bake_started_usec = 0
	_bake_warmup_elapsed_ms = 0.0
	_bake_queue_build_elapsed_ms = 0.0
	_bake_queue.clear()
	_bake_current_tile_id = &""
	_current_bake_request = {}
	_bake_in_progress = false
	_bake_total_requests = 0
	_bake_completed_requests = 0
	_gameplay_texture_profile.clear()
	_gameplay_texture_cache.clear()
	_gameplay_texture_metadata_cache.clear()
	_gameplay_lighting_atlas_by_key.clear()
	_gameplay_rotation_atlas_by_key.clear()
	_last_gameplay_bake_report.clear()
	_gameplay_run_tile_scope = PackedStringArray()
	_gameplay_run_tile_scope_previous = PackedStringArray()
	_gem_atlas_run_cache.clear()
	_render_cache.clear()
	_scaled_geometry_cache.clear()
	_color_cache.clear()
	_tier_to_visual.clear()
	_cut_model_variants.clear()
	_cut_variants.clear()
	_cut_models.clear()
	_cuts.clear()
	_visuals.clear()
	_loaded = false
	_showroom_cache.clear()


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
