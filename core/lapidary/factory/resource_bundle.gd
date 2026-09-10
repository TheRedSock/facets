class_name GemResourceBundle
extends RefCounted
## Bundle authored data while keeping executable schemas as external scripts.
## Godot's FLAG_BUNDLE_RESOURCES also embeds class_name scripts, which collide
## with the worker's registered global classes when the job is loaded.
static func save(resource: Resource, path: String) -> Error:
	return ResourceSaver.save(_copy(resource, {}) as Resource, path)

static func _copy(value: Variant, copies: Dictionary) -> Variant:
	if value is Script:
		return value
	if value is Resource:
		var id: int = value.get_instance_id()
		if copies.has(id):
			return copies[id]
		var script: Script = value.get_script()
		var result: Resource = script.new() if script != null else ClassDB.instantiate(value.get_class())
		copies[id] = result
		for property: Dictionary in value.get_property_list():
			var name: String = property["name"]
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE == 0 or name in ["script", "resource_path"]:
				continue
			result.set(name, _copy(value.get(name), copies))
		return result
	if value is Array:
		var result: Array = value.duplicate()
		for i in result.size():
			result[i] = _copy(value[i], copies)
		return result
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		for key: Variant in value:
			result[key] = _copy(value[key], copies)
		return result
	return value
