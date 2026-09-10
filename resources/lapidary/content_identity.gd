class_name GemContentIdentity
extends RefCounted
## Canonical content identity for authored resource graphs. Resource paths and
## editor metadata are not identity; stored values and schema code are.
## No float quantization. Shared subresources and copied resources hash alike.

static func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(_canonical(value, [])))
	return context.finish().hex_encode()


static func _canonical(value: Variant, ancestors: Array) -> Variant:
	if value is Resource:
		assert(not ancestors.has(value), "Cyclic resource graphs are not render recipes")
		var stack := ancestors.duplicate()
		stack.append(value)
		var entries: Array = []
		var script: Script = value.get_script()
		entries.append(["class", value.get_class(), script.source_code if script else ""])
		for property: Dictionary in value.get_property_list():
			var name := String(property["name"])
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE == 0:
				continue
			if name in ["script", "resource_path", "resource_name", "resource_local_to_scene"] or name.begins_with("metadata/"):
				continue
			entries.append([name, _canonical(value.get(name), stack)])
		entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		return ["resource", entries]
	if value is Dictionary:
		var entries: Array = []
		for key: Variant in value:
			entries.append([_canonical(key, ancestors), _canonical(value[key], ancestors)])
		entries.sort_custom(func(a: Array, b: Array) -> bool: return var_to_bytes(a[0]).hex_encode() < var_to_bytes(b[0]).hex_encode())
		return ["dictionary", entries]
	if value is Array:
		var entries: Array = []
		for item: Variant in value:
			entries.append(_canonical(item, ancestors))
		return ["array", entries]
	assert(not value is Object, "Only resource objects may occur in a render recipe")
	return value
