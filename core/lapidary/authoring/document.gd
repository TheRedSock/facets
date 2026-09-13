class_name GemAuthoringDocument
extends RefCounted
## Detached transactional editing. Invalid drafts can be corrected/undone;
## only admitted current values can be saved or frozen for rendering.
const HISTORY_LIMIT := 64
var path := ""
var _history: Array[Resource] = []
var _cursor := -1
var _saved_digest := ""
var _saved_resource: Resource
var _disk_sha256 := ""

func create(resource: Resource) -> String:
	var why := GemContentIdentity.graph_error(resource)
	if resource == null or not why.is_empty(): return "Invalid document graph: " + why
	_history = [GemResourceBundle.detached(resource)]; _cursor = 0
	path = ""; _saved_digest = ""; _saved_resource = GemResourceBundle.detached(resource); _disk_sha256 = ""
	return ""

func open(source: String) -> String:
	if not ResourceLoader.exists(source): return "Resource does not exist: " + source
	var resource := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var why := GemAuthoringAdmission.error(resource)
	if not why.is_empty(): return why
	create(resource); path = source; _saved_digest = GemContentIdentity.digest(_current())
	_saved_resource = snapshot(); _disk_sha256 = FileAccess.get_sha256(source)
	return ""

func snapshot() -> Resource:
	return GemResourceBundle.detached(_current()) if _cursor >= 0 else null

func validation_error() -> String:
	return GemAuthoringAdmission.error(_current())

func dirty() -> bool:
	return _cursor >= 0 and GemContentIdentity.digest(_current()) != _saved_digest

func can_undo() -> bool: return _cursor > 0
func can_redo() -> bool: return _cursor >= 0 and _cursor < _history.size() - 1
func undo() -> bool:
	if not can_undo(): return false
	_cursor -= 1; return true
func redo() -> bool:
	if not can_redo(): return false
	_cursor += 1; return true

func edit(property_path: Array, value: Variant) -> String:
	if _cursor < 0 or property_path.is_empty(): return "Open a document and select a property"
	var value_error := GemContentIdentity.graph_error(value)
	if not value_error.is_empty(): return value_error
	var draft := snapshot()
	var owner: Variant = draft
	for i in property_path.size() - 1:
		if not _has(owner, property_path[i]): return "Unknown property path: " + str(property_path)
		owner = owner[property_path[i]]
	var key: Variant = property_path.back()
	if not _has(owner, key): return "Unknown property: " + str(key)
	var old: Variant = owner[key]
	if owner is Resource and value is Resource:
		for property: Dictionary in owner.get_property_list():
			if property.name != key: continue
			var expected: String = property.get("class_name", "")
			if expected.is_empty() or expected == "Resource": break
			var matches: bool = value.is_class(expected)
			for entry: Dictionary in ProjectSettings.get_global_class_list():
				if entry.class == expected: matches = is_instance_of(value, load(entry.path)); break
			if not matches: return "Resource type mismatch: expected " + expected
	if old is Array and value is Array and old.is_typed():
		for element in value:
			if old.get_typed_builtin() == TYPE_OBJECT:
				if element != null and (not element is Object or (old.get_typed_script() != null and not is_instance_of(element, old.get_typed_script()))): return "Array element resource type mismatch"
			elif typeof(element) != old.get_typed_builtin(): return "Array element type mismatch"
	if typeof(old) != typeof(value) and not (old is Resource and value == null) and not (old == null and value is Resource):
		return "Property type mismatch: " + str(key)
	if old is Resource and value is Resource and old.get_script() != value.get_script(): return "Resource schema mismatch"
	if GemContentIdentity.digest(old) == GemContentIdentity.digest(value): return ""
	owner[key] = GemResourceBundle.copy_value(value)
	var graph := GemContentIdentity.graph_error(draft)
	if not graph.is_empty(): return graph
	_derive_evidence(owner, str(key))
	_history.resize(_cursor + 1); _history.append(draft)
	if _history.size() > HISTORY_LIMIT: _history.pop_front()
	_cursor = _history.size() - 1
	return ""

func changes() -> Array:
	if _cursor < 0: return []
	var result := []
	_diff(GemResourceBundle.detached(_saved_resource if _saved_resource != null else _history[0]), snapshot(), [], result)
	return result

func save(destination := "", replace := false) -> String:
	if destination.is_empty(): destination = path
	var why := validation_error()
	if not why.is_empty(): return why
	if destination.get_extension() not in ["res", "tres"]: return "Save needs a .res or .tres path"
	if FileAccess.file_exists(destination) and destination != path and not replace: return "Destination exists; explicit replace is required"
	if destination == path and not replace and FileAccess.get_sha256(destination) != _disk_sha256: return "Destination changed externally; reopen or explicitly replace"
	var temporary := destination.get_basename() + ".saving-" + str(Time.get_ticks_usec()) + "." + destination.get_extension()
	var error := GemResourceBundle.save(_current(), temporary)
	if error != OK: return "Cannot save temporary resource: " + error_string(error)
	var reloaded := ResourceLoader.load(temporary, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	why = GemAuthoringAdmission.error(reloaded)
	if why.is_empty():
		error = DirAccess.rename_absolute(temporary, destination)
		if error != OK: why = "Cannot replace destination: " + error_string(error)
	if not why.is_empty():
		DirAccess.remove_absolute(temporary); return why
	# Text resources may round numbers. The document and subsequent previews
	# adopt the values read from disk, never the unsaved higher precision draft.
	_history[_cursor] = GemResourceBundle.detached(reloaded)
	path = destination; _saved_digest = GemContentIdentity.digest(_current())
	_saved_resource = snapshot(); _disk_sha256 = FileAccess.get_sha256(destination)
	return ""

func freeze(destination: String, replace := false) -> String:
	if destination.get_extension() != "res": return "Frozen inputs require binary .res"
	var why := validation_error()
	if not why.is_empty(): return why
	var frozen := GemAuthoringDocument.new()
	frozen.create(_current())
	why = frozen.save(destination, replace)
	if why.is_empty() and GemContentIdentity.digest(frozen.snapshot()) != GemContentIdentity.digest(_current()): return "Binary freeze failed exact-value roundtrip"
	return why

func _current() -> Resource:
	return _history[_cursor] if _cursor >= 0 else null

static func _has(owner: Variant, key: Variant) -> bool:
	if owner is Resource and (key is String or key is StringName):
		for property: Dictionary in owner.get_property_list():
			if property.name == key and GemContentIdentity._content_property(property): return true
	if owner is Array: return key is int and key >= 0 and key < owner.size()
	if owner is Dictionary: return owner.has(key)
	return false

static func _derive_evidence(owner: Variant, key: String) -> void:
	var target: Resource
	var field := ""
	if owner is GemIndexCurve and key in ["b", "c_um2", "index_offset"]: target = owner; field = "evidence"
	elif owner is GemChromophore and key in ["wavelength_start_nm", "wavelength_step_nm", "absorption_mm", "absorption_eray_mm", "cross_section_cm2", "cross_section_parallel_cm2", "basis", "host_species_id"]: target = owner; field = "absorption_evidence"
	elif owner is GemMaterial and key in ["scatter_per_mm", "scatter_g"]: target = owner; field = "scattering_evidence"
	elif owner is GemAbsorber and key in ["amount", "unit"]: target = owner; field = "amount_evidence"
	if target != null: target.set(field, GemOpticalEvidence.derived(target.get(field), "Authoring edit: " + key))
	if owner is GemMaterial and key == "atom_density_per_cm3":
		for term in owner.absorbers:
			if term.unit == GemAbsorber.Unit.PPMA_TOTAL_ATOMS: term.amount_evidence = GemOpticalEvidence.derived(term.amount_evidence, "Authoring edit: host atom density")

static func _diff(before: Variant, after: Variant, prefix: Array, result: Array) -> void:
	if GemContentIdentity.digest(before) == GemContentIdentity.digest(after): return
	if before is Resource and after is Resource and before.get_script() == after.get_script():
		for property: Dictionary in before.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE != 0 and property.name not in ["script", "resource_path"]:
				_diff(before.get(property.name), after.get(property.name), prefix + [property.name], result)
	else: result.append({"path": prefix, "before": before, "after": after})
