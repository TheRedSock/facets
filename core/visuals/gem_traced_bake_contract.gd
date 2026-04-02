class_name GemTracedBakeContract
extends RefCounted

const DEFAULT_OUTPUT_ROOT := "user://traced_bakes"
const DEFAULT_MANIFEST_NAME := "gameplay_manifest.json"
const GENERATED_OUTPUT_ROOT := "res://generated/traced_bakes"
const BAKED_LOOK_VERSION := 1


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
		"cut_id": request.get("cut_id", &""),
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
	var requested_draw_size := normalize_size(
		request.get("draw_size", request.get("target_size", Vector2i.ZERO)),
		Vector2i.ZERO
	)
	var requested_target_size := normalize_size(
		request.get("target_size", request.get("draw_size", Vector2i.ZERO)),
		Vector2i.ZERO
	)
	var entry_draw_size := normalize_size(entry.get("draw_size", requested_draw_size), requested_draw_size)
	var entry_target_size := normalize_size(entry.get("target_size", requested_target_size), requested_target_size)
	if requested_draw_size != Vector2i.ZERO and entry_draw_size != requested_draw_size:
		return false
	if requested_target_size != Vector2i.ZERO and entry_target_size != requested_target_size:
		return false
	return true


static func normalize_size(raw_value, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if raw_value is Vector2i:
		return raw_value
	if raw_value is Vector2:
		return Vector2i(int(round(raw_value.x)), int(round(raw_value.y)))
	if typeof(raw_value) == TYPE_ARRAY:
		var values: Array = raw_value
		if values.size() >= 2:
			return Vector2i(int(values[0]), int(values[1]))
	if typeof(raw_value) == TYPE_DICTIONARY:
		var values: Dictionary = raw_value
		if values.has("x") and values.has("y"):
			return Vector2i(int(values.get("x", fallback.x)), int(values.get("y", fallback.y)))
	return fallback


static func _join_path(base: String, tail: String) -> String:
	if base.ends_with("/"):
		return "%s%s" % [base, tail]
	return "%s/%s" % [base, tail]
