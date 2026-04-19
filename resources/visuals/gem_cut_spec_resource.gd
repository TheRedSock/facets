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
## Default facet edge rounding for this cut shape (0 = sharp, 1 = maximum smoothing).
## Controls how much the polished bevel at zone transitions is smoothed.
## Per-gem overrides via GemVisualResource.facet_edge_rounding_override.
@export_range(0.0, 1.0) var facet_edge_rounding: float = 0.0


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


## Return a contract dict with all Godot-native types (PackedVector2Array,
## Vector2, StringName, etc.) replaced by JSON-safe equivalents so that
## JSON.stringify → JSON.parse_string round-trips cleanly.
func build_json_safe_contract_dict() -> Dictionary:
	return _to_json_safe(build_contract_dict())


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


func get_pavilion_auto_depth() -> bool:
	return _get_bool_from(pavilion, "auto_depth", true)


func get_pavilion_auto_crown_height() -> bool:
	return _get_bool_from(pavilion, "auto_crown_height", true)


func get_pavilion_target_angle_degrees() -> float:
	return float(pavilion.get("target_angle_degrees", -1.0))


func get_total_depth_ratio() -> float:
	return float(pavilion.get("total_depth_ratio", 0.62))


func get_crown_pavilion_split() -> Array:
	return pavilion.get("crown_pavilion_split", [1, 2])


func get_culet_style() -> String:
	return String(culet.get("style", "point"))


func get_culet_flat_size() -> float:
	return float(culet.get("flat_size", 0.25))


func get_culet_flat_sides() -> int:
	## -1 = match pavilion sector count (default).
	return int(culet.get("flat_sides", -1))


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
	var raw = crown.get("center_point", Vector2(0.5, 0.5))
	if raw is Vector2:
		return raw
	if typeof(raw) == TYPE_STRING:
		var parsed := _parse_vector2_array_string("[%s]" % raw)
		if parsed.size() >= 1:
			return parsed[0]
	if typeof(raw) == TYPE_ARRAY and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2(0.5, 0.5)


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
	var raw = girdle.get("silhouette", PackedVector2Array())
	if raw is PackedVector2Array:
		return raw
	var arr := _packed_or_array_to_vector2_array(raw)
	var result := PackedVector2Array()
	for v in arr:
		result.append(v)
	return result


## Apply solver-resolved pavilion parameters into this spec's pavilion/culet
## dicts and crown height. Used by the registry before geometry signature
## computation and compilation.
func apply_pavilion_resolution(params: Dictionary) -> void:
	if params.has("pavilion_depth"):
		pavilion["depth"] = params["pavilion_depth"]
	if params.has("crown_height"):
		crown["height"] = params["crown_height"]
	if params.has("upper_depth_ratio"):
		pavilion["upper_depth_ratio"] = params["upper_depth_ratio"]
	if params.has("lower_depth_ratio"):
		pavilion["lower_depth_ratio"] = params["lower_depth_ratio"]
	if params.has("upper_scale"):
		pavilion["upper_scale"] = params["upper_scale"]
	if params.has("lower_scale"):
		pavilion["lower_scale"] = params["lower_scale"]
	if params.has("rotation_fraction"):
		pavilion["rotation_fraction"] = params["rotation_fraction"]
	if params.has("sector_count") and int(params["sector_count"]) > 0:
		pavilion["sector_count"] = params["sector_count"]
	if params.has("culet_style"):
		culet["style"] = params["culet_style"]
	if params.has("culet_flat_size"):
		culet["flat_size"] = params["culet_flat_size"]
	if params.has("culet_flat_sides"):
		culet["flat_sides"] = params["culet_flat_sides"]
	# Mark as explicitly resolved so the solver won't re-derive.
	pavilion["auto_depth"] = false
	pavilion["auto_crown_height"] = false


func _get_bool_from(dict: Dictionary, key: String, default_value: bool) -> bool:
	if not dict.has(key):
		return default_value
	var value = dict[key]
	if value is bool:
		return value
	return bool(value)


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


## Minimal override dict such that `_deep_merge_dict(base, result)` matches `current` for designer save.
static func compute_contract_overrides(base_contract: Dictionary, current_contract: Dictionary) -> Dictionary:
	var diff = _diff_contract_values(base_contract, current_contract)
	return diff if typeof(diff) == TYPE_DICTIONARY else {}


## Returns null when values are equivalent (no override needed).
static func _diff_contract_values(base_val, current_val) -> Variant:
	if typeof(base_val) != typeof(current_val):
		return _duplicate_variant(current_val)
	match typeof(current_val):
		TYPE_DICTIONARY:
			var base_d: Dictionary = base_val
			var cur_d: Dictionary = current_val
			var out := {}
			for k in cur_d.keys():
				var cv = cur_d[k]
				if not base_d.has(k):
					out[k] = _duplicate_variant(cv)
					continue
				var bv = base_d[k]
				var sub = _diff_contract_values(bv, cv)
				if sub != null:
					out[k] = sub
			return out if not out.is_empty() else null
		TYPE_ARRAY:
			var ba: Array = base_val
			var ca: Array = current_val
			if _contract_arrays_equal(ba, ca):
				return null
			return _duplicate_variant(ca)
		_:
			if _contract_leaf_equal(base_val, current_val):
				return null
			return _duplicate_variant(current_val)


static func _contract_arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var av = a[i]
		var bv = b[i]
		if typeof(av) == TYPE_DICTIONARY and typeof(bv) == TYPE_DICTIONARY:
			if not _contract_dicts_equal(av, bv):
				return false
		elif typeof(av) == TYPE_ARRAY and typeof(bv) == TYPE_ARRAY:
			if not _contract_arrays_equal(av, bv):
				return false
		elif not _contract_leaf_equal(av, bv):
			return false
	return true


static func _contract_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
		if typeof(a[k]) == TYPE_DICTIONARY and typeof(b[k]) == TYPE_DICTIONARY:
			if not _contract_dicts_equal(a[k], b[k]):
				return false
		elif typeof(a[k]) == TYPE_ARRAY and typeof(b[k]) == TYPE_ARRAY:
			if not _contract_arrays_equal(a[k], b[k]):
				return false
		elif not _contract_leaf_equal(a[k], b[k]):
			return false
	return true


static func _contract_leaf_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(float(a), float(b))
		TYPE_VECTOR2:
			var va := a as Vector2
			var vb := b as Vector2
			return va.is_equal_approx(vb)
		TYPE_VECTOR3:
			var v3a := a as Vector3
			var v3b := b as Vector3
			return v3a.is_equal_approx(v3b)
		TYPE_COLOR:
			var ca := a as Color
			var cb := b as Color
			return ca.is_equal_approx(cb)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(a) == String(b)
		TYPE_BOOL, TYPE_INT:
			return a == b
		TYPE_PACKED_FLOAT32_ARRAY:
			var pa: PackedFloat32Array = a
			var pb: PackedFloat32Array = b
			if pa.size() != pb.size():
				return false
			for i in pa.size():
				if not is_equal_approx(pa[i], pb[i]):
					return false
			return true
		TYPE_PACKED_VECTOR2_ARRAY:
			var p2a: PackedVector2Array = a
			var p2b: PackedVector2Array = b
			if p2a.size() != p2b.size():
				return false
			for i in p2a.size():
				if not p2a[i].is_equal_approx(p2b[i]):
					return false
			return true
		_:
			return a == b


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


## Recursively convert Godot-native types to JSON-safe equivalents.
## PackedVector2Array → [[x,y], ...], Vector2 → [x,y], StringName → String, etc.
static func _to_json_safe(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var result := {}
			for key in value.keys():
				result[String(key) if key is StringName else key] = _to_json_safe(value[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			result.resize(value.size())
			for i in value.size():
				result[i] = _to_json_safe(value[i])
			return result
		TYPE_PACKED_VECTOR2_ARRAY:
			var result: Array = []
			for v in value:
				result.append([v.x, v.y])
			return result
		TYPE_PACKED_VECTOR3_ARRAY:
			var result: Array = []
			for v in value:
				result.append([v.x, v.y, v.z])
			return result
		TYPE_PACKED_COLOR_ARRAY:
			var result: Array = []
			for c in value:
				result.append([c.r, c.g, c.b, c.a])
			return result
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_STRING_NAME:
			return String(value)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			var result: Array = []
			for v in value:
				result.append(v)
			return result
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var result: Array = []
			for v in value:
				result.append(v)
			return result
		TYPE_PACKED_STRING_ARRAY:
			var result: Array = []
			for v in value:
				result.append(String(v))
			return result
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
	if typeof(value) == TYPE_STRING:
		return _parse_vector2_array_string(value)
	if typeof(value) == TYPE_ARRAY:
		for element in value:
			var v: Variant = _coerce_to_vector2(element)
			if v != null:
				result.append(v)
	return result


## Coerce a single JSON-parsed element to Vector2.
## Handles: Vector2 (pass-through), [x, y] Array, {"x": x, "y": y} Dictionary.
static func _coerce_to_vector2(element) -> Variant:
	if element is Vector2:
		return element
	if typeof(element) == TYPE_ARRAY and element.size() >= 2:
		return Vector2(float(element[0]), float(element[1]))
	if typeof(element) == TYPE_DICTIONARY:
		if element.has("x") and element.has("y"):
			return Vector2(float(element["x"]), float(element["y"]))
	return null


## Parse a GDScript-style vector2 array string, e.g. "[(0.5, 0.05), (0.78, 0.22)]".
static func _parse_vector2_array_string(text: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var s := text.strip_edges()
	if s == "" or s == "[]":
		return result
	# Strip outer brackets
	if s.begins_with("[") and s.ends_with("]"):
		s = s.substr(1, s.length() - 2).strip_edges()
	if s == "":
		return result
	# Find all (x, y) pairs via parentheses
	var start := 0
	while start < s.length():
		var open := s.find("(", start)
		if open < 0:
			break
		var close := s.find(")", open)
		if close < 0:
			break
		var inner := s.substr(open + 1, close - open - 1)
		var parts := inner.split(",")
		if parts.size() >= 2:
			result.append(Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges())))
		start = close + 1
	return result


static func _polygon_array_from_variant(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for polygon in value:
		result.append(_packed_or_array_to_vector2_array(polygon))
	return result
