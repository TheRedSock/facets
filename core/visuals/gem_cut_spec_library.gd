class_name GemCutSpecLibrary
extends RefCounted

## Loads authored GemCutSpecResource assets from data/visuals/cut_specs.

const CUT_SPEC_DATA_PATH := "res://data/visuals/cut_specs/"

static var _loaded := false
static var _specs: Dictionary = {}


func get_spec(spec_id: StringName):
	_ensure_loaded()
	var spec = _specs.get(spec_id, null)
	if spec == null:
		return null
	return spec.duplicate_spec()


func get_spec_ids() -> Array[StringName]:
	_ensure_loaded()
	var ids: Array[StringName] = []
	for spec_id in _specs.keys():
		ids.append(spec_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return ids


func has_spec(spec_id: StringName) -> bool:
	_ensure_loaded()
	return _specs.has(spec_id)


func reload() -> void:
	_loaded = false
	_specs.clear()
	_ensure_loaded()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_specs.clear()
	var dir := DirAccess.open(CUT_SPEC_DATA_PATH)
	if dir == null:
		push_warning("GemCutSpecLibrary: Could not open %s" % CUT_SPEC_DATA_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := CUT_SPEC_DATA_PATH + file_name
			var resource = load(path)
			if resource != null and resource.has_method("duplicate_spec") and resource.has_method("get_label_id"):
				var spec = resource
				var key: StringName = spec.get_label_id()
				if key == &"":
					key = StringName(file_name.get_basename())
				_specs[key] = spec
		file_name = dir.get_next()
	dir.list_dir_end()
