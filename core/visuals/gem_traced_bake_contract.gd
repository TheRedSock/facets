class_name GemTracedBakeContract
extends RefCounted

const DEFAULT_OUTPUT_ROOT := "user://traced_bakes"
const DEFAULT_MANIFEST_NAME := "gameplay_manifest.json"
const GENERATED_OUTPUT_ROOT := "res://generated/traced_bakes"
const BAKED_LOOK_VERSION := 6

## Image output format constants.
const IMAGE_FORMAT_PNG := &"png"
const IMAGE_FORMAT_WEBP := &"webp"
const DEFAULT_IMAGE_FORMAT := IMAGE_FORMAT_WEBP
const SUPPORTED_IMAGE_FORMATS := [IMAGE_FORMAT_PNG, IMAGE_FORMAT_WEBP]

## WebP quality defaults.  Quality 92 provides near-imperceptible loss for
## stylized gem textures while achieving ~10-20x compression over PNG.
const DEFAULT_WEBP_QUALITY: float = 0.92
const MIN_WEBP_QUALITY: float = 0.50
const MAX_WEBP_QUALITY: float = 1.0

## GPU block compression after decode (~4x VRAM vs RGBA8). Desktop: BC7 (BPTC); mobile: ASTC in loader.
const VRAM_COMPRESS_ON_LOAD := true
const VRAM_COMPRESS_FORMAT := Image.COMPRESS_BPTC
## Minimum shorter image edge (px) to compress; small board cells stay uncompressed to avoid block artifacts.
const VRAM_COMPRESS_MIN_SIZE := 256

const DEFAULT_LIGHTING_GRID_SIZE := Vector2i(5, 5)
const LIGHTING_GRID_PRESET_CUSTOM := &"custom"
const DEFAULT_LIGHTING_GRID_PRESET := &"quality"
const LIGHTING_GRID_PRESETS := {
	&"performance": Vector2i(3, 3),
	&"balanced": Vector2i(4, 4),
	&"quality": DEFAULT_LIGHTING_GRID_SIZE,
	&"ultra": Vector2i(6, 6),
}
const DEFAULT_ROTATION_BASE_VIEW_COUNT := 6
const DEFAULT_ROTATION_AXIS_STEPS := 0
const DEFAULT_ROTATION_STEP_DEGREES := 18.0
const DEFAULT_SHOWROOM_DIRECTION_COUNT := 0
const DEFAULT_SHOWROOM_ROLL_STEPS := 6
const GAMEPLAY_VARIANT_TYPE_SHOWROOM := &"showroom"
const DEFAULT_SAMPLES_PER_PIXEL := 64
const SUPPORTED_ROTATION_AXES := [&"pitch", &"yaw", &"roll"]


static func default_variant_settings() -> Dictionary:
	return {
		"lighting_grid_preset": DEFAULT_LIGHTING_GRID_PRESET,
		"lighting_grid_size": DEFAULT_LIGHTING_GRID_SIZE,
		"lighting_runtime_grid_size": DEFAULT_LIGHTING_GRID_SIZE,
		"rotation_base_view_count": DEFAULT_ROTATION_BASE_VIEW_COUNT,
		"rotation_axis_steps": DEFAULT_ROTATION_AXIS_STEPS,
		"rotation_step_degrees": DEFAULT_ROTATION_STEP_DEGREES,
		"rotation_axes": PackedStringArray(),
		"showroom_direction_count": DEFAULT_SHOWROOM_DIRECTION_COUNT,
		"showroom_roll_steps": DEFAULT_SHOWROOM_ROLL_STEPS,
		"lighting_atlas_layers": 0,
		"lighting_atlas_layer_order": "",
		"rotation_atlas_layers": 0,
	}


static func normalize_variant_settings(raw_value: Dictionary = {}) -> Dictionary:
	var defaults := default_variant_settings()
	var lighting_preset := _normalize_lighting_grid_preset_name(
		raw_value.get("lighting_grid_preset", defaults["lighting_grid_preset"])
	)
	var lighting_grid := resolve_lighting_grid_preset(lighting_preset)
	if raw_value.has("lighting_grid_size"):
		lighting_grid = normalize_size(
			raw_value.get("lighting_grid_size", defaults["lighting_grid_size"]),
			lighting_grid
		)
	lighting_grid.x = maxi(lighting_grid.x, 0)
	lighting_grid.y = maxi(lighting_grid.y, 0)
	var runtime_lighting_grid := lighting_grid
	if raw_value.has("lighting_runtime_grid_size"):
		runtime_lighting_grid = normalize_size(
			raw_value.get("lighting_runtime_grid_size", lighting_grid),
			lighting_grid
		)
	if lighting_grid == Vector2i.ZERO:
		runtime_lighting_grid = Vector2i.ZERO
	else:
		runtime_lighting_grid.x = clampi(runtime_lighting_grid.x, 1, lighting_grid.x)
		runtime_lighting_grid.y = clampi(runtime_lighting_grid.y, 1, lighting_grid.y)
	var base_view_count := maxi(
		int(raw_value.get("rotation_base_view_count", defaults["rotation_base_view_count"])),
		0
	)
	var axis_steps := maxi(
		int(raw_value.get("rotation_axis_steps", defaults["rotation_axis_steps"])),
		0
	)
	var step_degrees := maxf(
		float(raw_value.get("rotation_step_degrees", defaults["rotation_step_degrees"])),
		1.0
	)
	var raw_axes = raw_value.get("rotation_axes", defaults["rotation_axes"])
	if raw_axes is String:
		raw_axes = String(raw_axes).replace(";", ",").split(",", false)
	var normalized_axes: Array[StringName] = []
	var seen_axes: Dictionary = {}
	for raw_axis in raw_axes:
		var axis := StringName(String(raw_axis).strip_edges().to_lower())
		if axis == &"" or seen_axes.has(axis):
			continue
		if not SUPPORTED_ROTATION_AXES.has(axis):
			continue
		seen_axes[axis] = true
		normalized_axes.append(axis)
	var showroom_dir_count := maxi(
		int(raw_value.get("showroom_direction_count", defaults["showroom_direction_count"])),
		0
	)
	var showroom_roll_steps := clampi(
		int(raw_value.get("showroom_roll_steps", defaults["showroom_roll_steps"])),
		1,
		64
	)
	var showroom_axis_steps := clampi(
		int(raw_value.get("showroom_axis_steps", 0)),
		0,
		360
	)
	var raw_showroom_axes = raw_value.get("showroom_axes", [])
	if raw_showroom_axes is String:
		raw_showroom_axes = String(raw_showroom_axes).replace(";", ",").split(",", false)
	var normalized_showroom_axes: Array[StringName] = []
	var seen_showroom_axes: Dictionary = {}
	for raw_axis in raw_showroom_axes:
		var sa := StringName(String(raw_axis).strip_edges().to_lower())
		if sa == &"" or seen_showroom_axes.has(sa):
			continue
		if not [&"pitch", &"yaw"].has(sa):
			continue
		seen_showroom_axes[sa] = true
		normalized_showroom_axes.append(sa)
	var result := {
		"lighting_grid_preset": detect_lighting_grid_preset(lighting_grid),
		"lighting_grid_size": lighting_grid,
		"lighting_runtime_grid_size": runtime_lighting_grid,
		"rotation_base_view_count": base_view_count,
		"rotation_axis_steps": axis_steps,
		"rotation_step_degrees": step_degrees,
		"rotation_axes": PackedStringArray(normalized_axes),
		"showroom_direction_count": showroom_dir_count,
		"showroom_roll_steps": showroom_roll_steps,
		"showroom_axis_steps": showroom_axis_steps,
		"showroom_axes": PackedStringArray(normalized_showroom_axes),
		"lighting_atlas_layers": maxi(
			0,
			int(raw_value.get("lighting_atlas_layers", maxi(0, lighting_grid.x * lighting_grid.y)))
		),
		"lighting_atlas_layer_order": String(
			raw_value.get("lighting_atlas_layer_order", defaults["lighting_atlas_layer_order"])
		),
		"rotation_atlas_layers": maxi(0, int(raw_value.get("rotation_atlas_layers", 0))),
	}
	# Pass through lighting rig config if present (not a variant grid setting itself,
	# but consumed by the registry when building per-bin environment profiles).
	if raw_value.has("lighting_rig") and typeof(raw_value.get("lighting_rig")) == TYPE_DICTIONARY:
		result["lighting_rig"] = raw_value.get("lighting_rig")
	return result


static func sanitize_variant_key(value: String) -> String:
	return value.replace("@", "__").replace("/", "_").replace("\\", "_").replace(":", "_")


static func build_texture_path(output_root: String, tile_id: String, variant_key: String, image_format: StringName = DEFAULT_IMAGE_FORMAT) -> String:
	var ext := "webp" if image_format == IMAGE_FORMAT_WEBP else "png"
	return _join_path(output_root, "%s/%s.%s" % [tile_id, sanitize_variant_key(variant_key), ext])


static func normalize_image_format(raw_value) -> StringName:
	var normalized := StringName(String(raw_value).strip_edges().to_lower())
	if SUPPORTED_IMAGE_FORMATS.has(normalized):
		return normalized
	return DEFAULT_IMAGE_FORMAT


## Compute WebP quality for a given visual.
## Gems with high dispersion need higher quality to preserve fine spectral detail.
## If the visual has a non-negative bake_quality_override it takes precedence.
static func compute_adaptive_webp_quality(visual: Resource, base_quality: float = DEFAULT_WEBP_QUALITY) -> float:
	if visual == null:
		return clampf(base_quality, MIN_WEBP_QUALITY, MAX_WEBP_QUALITY)
	# Honour explicit per-gem override.
	var override_quality := _get_visual_float(visual, &"bake_quality_override", -1.0)
	if override_quality >= 0.0:
		return clampf(override_quality, MIN_WEBP_QUALITY, MAX_WEBP_QUALITY)
	var quality := base_quality
	# High-dispersion minerals (computed from Sellmeier spread) compress poorly.
	var template: Resource = visual.get(&"mineral_template")
	if template != null:
		var ior_spread := _compute_dispersion_spread(template)
		if ior_spread > 0.03:
			quality += 0.06
		elif ior_spread > 0.015:
			quality += 0.03
	return clampf(quality, MIN_WEBP_QUALITY, MAX_WEBP_QUALITY)


## Compute adaptive samples_per_pixel for a visual based on dispersion and scattering.
static func compute_adaptive_samples(visual: Resource) -> int:
	if visual == null:
		return DEFAULT_SAMPLES_PER_PIXEL
	var base := DEFAULT_SAMPLES_PER_PIXEL
	var template: Resource = visual.get(&"mineral_template")
	if template == null:
		return base
	var dispersion_spread := _compute_dispersion_spread(template)
	if dispersion_spread > 0.03:
		base = int(base * 2.5)
	elif dispersion_spread > 0.015:
		base = int(base * 1.5)
	var sigma_s: float = float(template.get(&"scattering_coefficient"))
	var override_s := _get_visual_float(visual, &"scattering_coefficient_override", -1.0)
	if override_s >= 0.0:
		sigma_s = override_s
	if sigma_s > 5.0:
		base = int(base * 1.3)
	return clampi(base, 32, 512)


static func _compute_dispersion_spread(template: Resource) -> float:
	if template == null:
		return 0.0
	var b: Vector3 = template.get(&"sellmeier_b")
	var c: Vector3 = template.get(&"sellmeier_c")
	if b == null or c == null:
		return 0.0
	var ior_blue := _sellmeier_ior_at(b, c, 380.0)
	var ior_red := _sellmeier_ior_at(b, c, 780.0)
	return ior_blue - ior_red


static func _sellmeier_ior_at(b: Vector3, c: Vector3, lambda_nm: float) -> float:
	var l := lambda_nm * 0.001
	var l2 := l * l
	var n2 := 1.0 + b.x * l2 / (l2 - c.x) + b.y * l2 / (l2 - c.y) + b.z * l2 / (l2 - c.z)
	return sqrt(max(n2, 1.0))


## File extension (without dot) for the given image format.
static func image_format_extension(image_format: StringName) -> String:
	return "webp" if image_format == IMAGE_FORMAT_WEBP else "png"


static func build_manifest_entry(
	visual: GemVisualResource,
	request: Dictionary,
	texture_path: String,
	cell_size: Vector2i,
	draw_size: Vector2i,
	sample_count: int,
) -> Dictionary:
	var entry := {
		"tile_id": request.get("tile_id", &""),
		"visual_id": visual.visual_id if visual != null else request.get("visual_id", &""),
		"spec_id": request.get("spec_id", visual.get_cut_spec_id() if visual != null else &""),
		"geometry_signature": request.get("geometry_signature", request.get("cut_key_override", "")),
		"cut_id": request.get("cut_id", &""),
		"cut_signature": request.get(
			"cut_key_override",
			request.get("geometry_signature", request.get("cut_id", &""))
		),
		"geometry_source": request.get("geometry_source", &"canonical_3d"),
		"variant_type": request.get("variant_type", &""),
		"variant_key": request.get("variant_key", &""),
		"lighting_bin": request.get("lighting_bin", Vector2i(-1, -1)),
		"rotation_bin": request.get("rotation_bin", -1),
		"rotation_label": request.get("rotation_label", &""),
		"rotation_axis": request.get("rotation_axis", &""),
		"view_pitch_degrees": request.get("view_pitch_degrees", null),
		"view_yaw_degrees": request.get("view_yaw_degrees", null),
		"view_roll_degrees": request.get("view_roll_degrees", null),
		"view_dir_model": request.get("view_dir_model", null),
		"showroom_direction_index": request.get("showroom_direction_index", null),
		"showroom_roll_index": request.get("showroom_roll_index", null),
		"showroom_direction_count": request.get("showroom_direction_count", null),
		"showroom_roll_steps": request.get("showroom_roll_steps", null),
		"showroom_orientation": request.get("showroom_orientation", null),
		"showroom_frame_type": request.get("showroom_frame_type", null),
		"texture_path": texture_path,
		"target_size": cell_size,
		"draw_size": draw_size,
		"sample_count": sample_count,
		"samples_per_pixel": int(request.get("samples_per_pixel", DEFAULT_SAMPLES_PER_PIXEL)),
		"stylize_version": BAKED_LOOK_VERSION,
		"image_format": String(request.get("image_format", DEFAULT_IMAGE_FORMAT)),
		"image_quality": float(request.get("image_quality", DEFAULT_WEBP_QUALITY)),
	}
	var vtype: StringName = entry.get("variant_type", &"")
	var tid := String(entry.get("tile_id", &""))
	if vtype == &"lighting":
		var lg := normalize_size(request.get("lighting_grid_size", Vector2i.ZERO), Vector2i.ZERO)
		if lg != Vector2i.ZERO:
			var bin: Vector2i = normalize_size(request.get("lighting_bin", Vector2i.ZERO), Vector2i.ZERO)
			entry["atlas_group"] = "%s_lighting" % tid
			entry["atlas_layer"] = bin.y * lg.x + bin.x
	elif vtype == &"rotation":
		entry["atlas_group"] = "%s_rotation" % tid
		entry["atlas_layer"] = int(entry.get("rotation_bin", 0))
	return entry


static func build_manifest_variant_settings(raw_value: Dictionary = {}) -> Dictionary:
	var normalized := normalize_variant_settings(raw_value)
	if raw_value.has("image_format"):
		normalized["image_format"] = normalize_image_format(raw_value.get("image_format"))
	return normalized


## Runtime Texture2DArray layout metadata (also written into gameplay manifests).
static func merge_atlas_metadata_into_variant_settings(
	settings: Dictionary,
	rotation_layer_count: int,
) -> Dictionary:
	var merged := settings.duplicate(true)
	var lg: Vector2i = normalize_size(merged.get("lighting_grid_size", DEFAULT_LIGHTING_GRID_SIZE), DEFAULT_LIGHTING_GRID_SIZE)
	merged["lighting_atlas_layers"] = maxi(0, lg.x * lg.y)
	merged["lighting_atlas_layer_order"] = "row_major"
	merged["rotation_atlas_layers"] = maxi(0, rotation_layer_count)
	return merged


static func infer_rotation_layer_count_from_requests(requests: Array) -> int:
	var max_bin := -1
	for raw in requests:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = raw
		if StringName(r.get("variant_type", &"")) != &"rotation":
			continue
		max_bin = maxi(max_bin, int(r.get("rotation_bin", -1)))
	return maxi(0, max_bin + 1)


static func get_manifest_variant_settings(manifest: Dictionary) -> Dictionary:
	if manifest.is_empty():
		return default_variant_settings()
	return normalize_variant_settings(manifest.get("variant_settings", {}))


static func manifest_matches_current(manifest: Dictionary, expected: Dictionary = {}) -> bool:
	if manifest.is_empty():
		return false
	if StringName(manifest.get("backend_id", &"")) != &"offline_traced":
		return false
	if int(manifest.get("stylize_version", 0)) != BAKED_LOOK_VERSION:
		return false
	return true


static func entry_matches_request(entry: Dictionary, request: Dictionary) -> bool:
	if entry.is_empty():
		return false
	if int(entry.get("stylize_version", 0)) != BAKED_LOOK_VERSION:
		return false
	if String(entry.get("cut_signature", "")) != String(
		request.get("cut_key_override", request.get("geometry_signature", request.get("cut_id", &"")))
	):
		return false
	var requested_target_size := normalize_size(
		request.get("target_size", request.get("draw_size", Vector2i.ZERO)),
		Vector2i.ZERO
	)
	var entry_target_size := normalize_size(entry.get("target_size", requested_target_size), requested_target_size)
	if requested_target_size != Vector2i.ZERO and entry_target_size != requested_target_size:
		return false
	return true


static func normalize_size(raw_value, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if raw_value is Vector2i:
		return raw_value
	if raw_value is Vector2:
		return Vector2i(int(round(raw_value.x)), int(round(raw_value.y)))
	if raw_value is String:
		var text := String(raw_value).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		text = text.replace("x", ",")
		var parts := text.split(",", false)
		if parts.size() >= 2:
			return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))
	if typeof(raw_value) == TYPE_ARRAY:
		var values: Array = raw_value
		if values.size() >= 2:
			return Vector2i(int(values[0]), int(values[1]))
	if typeof(raw_value) == TYPE_DICTIONARY:
		var values: Dictionary = raw_value
		if values.has("x") and values.has("y"):
			return Vector2i(int(values.get("x", fallback.x)), int(values.get("y", fallback.y)))
	return fallback


static func get_lighting_grid_presets() -> Dictionary:
	return LIGHTING_GRID_PRESETS.duplicate(true)


static func resolve_lighting_grid_preset(preset) -> Vector2i:
	var normalized := _normalize_lighting_grid_preset_name(preset)
	if LIGHTING_GRID_PRESETS.has(normalized):
		return LIGHTING_GRID_PRESETS.get(normalized, DEFAULT_LIGHTING_GRID_SIZE)
	return DEFAULT_LIGHTING_GRID_SIZE


static func detect_lighting_grid_preset(grid_size: Vector2i) -> StringName:
	for preset_name in LIGHTING_GRID_PRESETS.keys():
		if LIGHTING_GRID_PRESETS.get(preset_name, Vector2i.ZERO) == grid_size:
			return StringName(preset_name)
	return LIGHTING_GRID_PRESET_CUSTOM


static func _normalize_lighting_grid_preset_name(raw_value) -> StringName:
	var preset := StringName(String(raw_value).strip_edges().to_lower())
	if preset == &"":
		return DEFAULT_LIGHTING_GRID_PRESET
	if LIGHTING_GRID_PRESETS.has(preset):
		return preset
	return LIGHTING_GRID_PRESET_CUSTOM


static func _join_path(base: String, tail: String) -> String:
	if base.ends_with("/"):
		return "%s%s" % [base, tail]
	return "%s/%s" % [base, tail]


## Safe float property accessor for visual resources. Returns fallback when the
## property does not exist or is null (e.g. when called with a non-GemVisualResource).
static func _get_visual_float(visual: Resource, property: StringName, fallback: float = 0.0) -> float:
	var value = visual.get(property)
	if value == null:
		return fallback
	return float(value)
