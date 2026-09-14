class_name GameValue
extends RefCounted

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
	if not (value is String or value is StringName) or str(value).is_empty() or str(value).length() > 128: return false
	for c in str(value):
		if c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-": return false
	return true
