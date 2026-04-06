class_name GemTracedBakeContract
extends RefCounted

const DEFAULT_OUTPUT_ROOT := "user://traced_bakes"
const DEFAULT_MANIFEST_NAME := "gameplay_manifest.json"
const GENERATED_OUTPUT_ROOT := "res://generated/traced_bakes"
const BAKED_LOOK_VERSION := 3
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
	return {
		"lighting_grid_preset": detect_lighting_grid_preset(lighting_grid),
		"lighting_grid_size": lighting_grid,
		"lighting_runtime_grid_size": runtime_lighting_grid,
		"rotation_base_view_count": base_view_count,
		"rotation_axis_steps": axis_steps,
		"rotation_step_degrees": step_degrees,
		"rotation_axes": PackedStringArray(normalized_axes),
	}


static func sanitize_variant_key(value: String) -> String:
	return value.replace("@", "__").replace("/", "_").replace("\\", "_").replace(":", "_")


static func build_texture_path(output_root: String, tile_id: String, variant_key: String) -> String:
	return _join_path(output_root, "%s/%s.png" % [tile_id, sanitize_variant_key(variant_key)])


static func build_manifest_entry(
	visual: GemVisualResource,
	request: Dictionary,
	texture_path: String,
	cell_size: Vector2i,
	draw_size: Vector2i,
	sample_count: int,
) -> Dictionary:
	return {
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
		"texture_path": texture_path,
		"target_size": cell_size,
		"draw_size": draw_size,
		"sample_count": sample_count,
		"stylize_version": BAKED_LOOK_VERSION,
	}


static func build_manifest_variant_settings(raw_value: Dictionary = {}) -> Dictionary:
	return normalize_variant_settings(raw_value)


static func get_manifest_variant_settings(manifest: Dictionary) -> Dictionary:
	if manifest.is_empty():
		return default_variant_settings()
	return normalize_variant_settings(manifest.get("variant_settings", {}))


static func manifest_matches_current(manifest: Dictionary) -> bool:
	if manifest.is_empty():
		return false
	if StringName(manifest.get("backend_id", &"")) != &"offline_traced":
		return false
	return int(manifest.get("stylize_version", 0)) == BAKED_LOOK_VERSION


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
