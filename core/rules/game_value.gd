class_name GameValue
extends RefCounted

static var _id_pattern := RegEx.create_from_string("\\A[A-Za-z0-9._/-]{1,128}\\z")

static func freeze(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = freeze(value[key])
		result.make_read_only()
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(freeze(item))
		result.make_read_only()
		return result
	return value

static func valid_id(value: Variant) -> bool:
	if not (value is String or value is StringName): return false
	return _id_pattern.search(str(value)) != null
