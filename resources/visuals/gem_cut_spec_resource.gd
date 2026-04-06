class_name GemCutSpecResource
extends Resource

## Canonical authored geometry definition for a gemstone cut.
## This is the public geometry contract resolved by GemVisualResource.

@export var spec_id: StringName = &""
@export var display_name: String = ""
@export var compatibility_cut_id: StringName = &""
@export var shape_category: StringName = &""
@export var family: StringName = &""

@export var symmetry: Dictionary = {}
@export var rings: Array = []
@export var crown: Dictionary = {}
@export var pavilion: Dictionary = {}
@export var girdle: Dictionary = {}
@export var culet: Dictionary = {}
@export var patches: Array = []
@export var constraints: Dictionary = {}
@export var orthographic_metadata: Dictionary = {}


func duplicate_spec():
	var copy = get_script().new()
	copy.spec_id = spec_id
	copy.display_name = display_name
	copy.compatibility_cut_id = compatibility_cut_id
	copy.shape_category = shape_category
	copy.family = family
	copy.symmetry = _duplicate_variant(symmetry)
	copy.rings = _duplicate_variant(rings)
	copy.crown = _duplicate_variant(crown)
	copy.pavilion = _duplicate_variant(pavilion)
	copy.girdle = _duplicate_variant(girdle)
	copy.culet = _duplicate_variant(culet)
	copy.patches = _duplicate_variant(patches)
	copy.constraints = _duplicate_variant(constraints)
	copy.orthographic_metadata = _duplicate_variant(orthographic_metadata)
	return copy


func apply_overrides(overrides: Dictionary):
	var copy = duplicate_spec()
	copy.apply_overrides_in_place(overrides)
	return copy


func apply_overrides_in_place(overrides: Dictionary) -> void:
	if overrides.is_empty():
		return
	var merged := _deep_merge_dict(build_contract_dict(), overrides)
	_apply_contract_dict(merged)


## Replace spec content from a full contract dict (e.g. designer tree merge).
func apply_full_contract(contract: Dictionary) -> void:
	_apply_contract_dict(_duplicate_variant(contract))


func build_contract_dict() -> Dictionary:
	return {
		"spec_id": spec_id,
		"display_name": display_name,
		"compatibility_cut_id": compatibility_cut_id,
		"shape_category": shape_category,
		"family": family,
		"symmetry": _duplicate_variant(symmetry),
		"rings": _duplicate_variant(rings),
		"crown": _duplicate_variant(crown),
		"pavilion": _duplicate_variant(pavilion),
		"girdle": _duplicate_variant(girdle),
		"culet": _duplicate_variant(culet),
		"patches": _duplicate_variant(patches),
		"constraints": _duplicate_variant(constraints),
		"orthographic_metadata": _duplicate_variant(orthographic_metadata),
	}


func build_geometry_signature() -> String:
	var base_id := spec_id
	if base_id == &"":
		base_id = compatibility_cut_id
	if base_id == &"":
		base_id = StringName("anonymous_spec")
	return "%s@%s" % [String(base_id), _stable_variant_string(build_contract_dict())]


func get_label_id() -> StringName:
	if spec_id != &"":
		return spec_id
	return compatibility_cut_id


func get_crown_height() -> float:
	return float(crown.get("height", 0.18))


func get_star_height_ratio() -> float:
	return float(crown.get("star_height_ratio", 0.62))


func get_inner_star_height_ratio() -> float:
	return float(crown.get("inner_star_height_ratio", 0.78))


func get_center_height_ratio() -> float:
	return float(crown.get("center_height_ratio", 1.0))


func get_girdle_thickness() -> float:
	return float(girdle.get("thickness", 0.012))


func get_pavilion_depth() -> float:
	return float(pavilion.get("depth", maxf(get_crown_height() * 1.85 + 0.07, 0.30)))


func get_pavilion_upper_depth_ratio() -> float:
	return float(pavilion.get("upper_depth_ratio", 0.48))


func get_pavilion_lower_depth_ratio() -> float:
	return float(pavilion.get("lower_depth_ratio", 0.82))


func get_pavilion_upper_scale() -> float:
	return float(pavilion.get("upper_scale", 0.52))


func get_pavilion_lower_scale() -> float:
	return float(pavilion.get("lower_scale", 0.20))


func get_pavilion_rotation_fraction() -> float:
	return float(pavilion.get("rotation_fraction", 0.0))


func get_pavilion_sector_count() -> int:
	return int(pavilion.get("sector_count", symmetry.get("pavilion_sector_count", 0)))


func get_crown_ring_height_ratios() -> PackedFloat32Array:
	var ratios := PackedFloat32Array()
	for ring in rings:
		ratios.append(float(ring.get("height_ratio", 0.0)))
	return ratios


func get_rose_band_height_ratios() -> PackedFloat32Array:
	var ratios := PackedFloat32Array()
	for ring in rings:
		ratios.append(float(ring.get("rose_height_ratio", 0.0)))
	return ratios


func get_symmetry_sector_count() -> int:
	return int(symmetry.get("sector_count", 0))


func get_symmetry_rotation() -> float:
	return float(symmetry.get("rotation", -PI * 0.5))


func get_main_angles() -> Array:
	return _duplicate_variant(symmetry.get("main_angles", []))


func get_half_angles() -> Array:
	return _duplicate_variant(symmetry.get("half_angles", []))


func get_ring_point_loops() -> Array:
	var loops: Array = []
	for ring in rings:
		loops.append(_packed_or_array_to_vector2_array(ring.get("points", PackedVector2Array())))
	return loops


func get_ring_zones() -> Array:
	var ring_zones: Array = []
	for ring in rings:
		ring_zones.append(ring.get("zone", &""))
	return ring_zones


func get_table_ratio() -> float:
	return float(crown.get("table_ratio", 0.5))


func get_star_length() -> float:
	return float(crown.get("star_length", 0.55))


func get_break_ratio() -> float:
	return float(crown.get("break_ratio", 0.5))


func get_edge_trim() -> float:
	return float(crown.get("edge_trim", 0.2))


func get_outer_shoulder_scale() -> float:
	return float(crown.get("outer_shoulder_scale", 1.0))


func get_outer_shoulder_height_ratio() -> float:
	return float(crown.get("outer_shoulder_height_ratio", 0.0))


func get_table_points() -> Array[Vector2]:
	return _packed_or_array_to_vector2_array(crown.get("table", PackedVector2Array()))


func get_center_point() -> Vector2:
	return crown.get("center_point", Vector2(0.5, 0.5))


func get_inner_star_facets() -> Array:
	return _polygon_array_from_variant(crown.get("inner_star_facets", []))


func get_star_facets() -> Array:
	return _polygon_array_from_variant(crown.get("star_facets", []))


func get_bezel_facets() -> Array:
	return _polygon_array_from_variant(crown.get("bezel_facets", []))


func get_fans() -> Array:
	return _duplicate_variant(crown.get("fans", []))


func get_boundary_mode() -> StringName:
	return StringName(girdle.get("boundary_mode", &"circle"))


func get_boundary_params() -> Dictionary:
	return _duplicate_variant(girdle.get("boundary_params", {}))


func get_half_radius_scale() -> float:
	return float(girdle.get("half_radius_scale", 1.0))


func get_outer_points() -> Array[Vector2]:
	return _packed_or_array_to_vector2_array(girdle.get("outer_points", PackedVector2Array()))


func get_silhouette_points() -> PackedVector2Array:
	return PackedVector2Array(girdle.get("silhouette", PackedVector2Array()))


func get_orthographic_top_roll_degrees() -> float:
	return float(orthographic_metadata.get("top_roll_degrees", 0.0))


func get_orthographic_side_yaw_degrees() -> float:
	return float(orthographic_metadata.get("side_yaw_degrees", 0.0))


func get_orthographic_axis_fit_scale() -> float:
	return float(orthographic_metadata.get("axis_fit_scale", 1.0))


func _apply_contract_dict(contract: Dictionary) -> void:
	spec_id = StringName(contract.get("spec_id", spec_id))
	display_name = String(contract.get("display_name", display_name))
	compatibility_cut_id = StringName(contract.get("compatibility_cut_id", compatibility_cut_id))
	shape_category = StringName(contract.get("shape_category", shape_category))
	family = StringName(contract.get("family", family))
	symmetry = _duplicate_variant(contract.get("symmetry", {}))
	rings = _duplicate_variant(contract.get("rings", []))
	crown = _duplicate_variant(contract.get("crown", {}))
	pavilion = _duplicate_variant(contract.get("pavilion", {}))
	girdle = _duplicate_variant(contract.get("girdle", {}))
	culet = _duplicate_variant(contract.get("culet", {}))
	patches = _duplicate_variant(contract.get("patches", []))
	constraints = _duplicate_variant(contract.get("constraints", {}))
	orthographic_metadata = _duplicate_variant(contract.get("orthographic_metadata", {}))


static func _deep_merge_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged: Dictionary = _duplicate_variant(base)
	for key in overrides.keys():
		var override_value = overrides[key]
		if merged.has(key) and typeof(merged[key]) == TYPE_DICTIONARY and typeof(override_value) == TYPE_DICTIONARY:
			merged[key] = _deep_merge_dict(merged[key], override_value)
		else:
			merged[key] = _duplicate_variant(override_value)
	return merged


static func _duplicate_variant(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var result := {}
			for key in value.keys():
				result[key] = _duplicate_variant(value[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			result.resize(value.size())
			for i in value.size():
				result[i] = _duplicate_variant(value[i])
			return result
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return value.duplicate()
		_:
			return value


static func _stable_variant_string(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			var keys: Array = value.keys()
			keys.sort_custom(func(a, b) -> bool:
				return String(a) < String(b)
			)
			for key in keys:
				parts.append("%s:%s" % [String(key), _stable_variant_string(value[key])])
			return "{%s}" % ",".join(parts)
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(_stable_variant_string(item))
			return "[%s]" % ",".join(parts)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(String.num(float(item), 6))
			return "[%s]" % ",".join(parts)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(str(item))
			return "[%s]" % ",".join(parts)
		TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append("\"%s\"" % String(item))
			return "[%s]" % ",".join(parts)
		TYPE_PACKED_VECTOR2_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append("(%.6f,%.6f)" % [item.x, item.y])
			return "[%s]" % ",".join(parts)
		TYPE_PACKED_VECTOR3_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append("(%.6f,%.6f,%.6f)" % [item.x, item.y, item.z])
			return "[%s]" % ",".join(parts)
		TYPE_PACKED_COLOR_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append("(%.6f,%.6f,%.6f,%.6f)" % [item.r, item.g, item.b, item.a])
			return "[%s]" % ",".join(parts)
		TYPE_VECTOR2:
			return "(%.6f,%.6f)" % [value.x, value.y]
		TYPE_VECTOR2I:
			return "(%d,%d)" % [value.x, value.y]
		TYPE_VECTOR3:
			return "(%.6f,%.6f,%.6f)" % [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return "(%d,%d,%d)" % [value.x, value.y, value.z]
		TYPE_COLOR:
			return "(%.6f,%.6f,%.6f,%.6f)" % [value.r, value.g, value.b, value.a]
		TYPE_STRING_NAME:
			return "&\"%s\"" % String(value)
		TYPE_STRING:
			return "\"%s\"" % value
		TYPE_FLOAT:
			return String.num(float(value), 6)
		TYPE_NIL:
			return "null"
		_:
			return str(value)


static func _packed_or_array_to_vector2_array(value) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if value is PackedVector2Array:
		for point in value:
			result.append(point)
		return result
	if typeof(value) == TYPE_ARRAY:
		for point in value:
			result.append(point)
	return result


static func _polygon_array_from_variant(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for polygon in value:
		result.append(_packed_or_array_to_vector2_array(polygon))
	return result
