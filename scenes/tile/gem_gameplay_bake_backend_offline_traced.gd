class_name GemGameplayBakeBackendOfflineTraced
extends "res://scenes/tile/gem_gameplay_bake_backend.gd"

## Loads precomputed traced bake textures from a manifest produced by the
## offline bake job. This keeps the runtime texture contract identical while
## allowing high-fidelity optics to be generated ahead of time.

const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")

var _manifest: Dictionary = {}
var _entries_by_key: Dictionary = {}
var _manifest_path := ""
var _manifest_modified_time := -1
var _default_manifest_paths: Array[String] = []


func _init() -> void:
	backend_id = &"offline_traced"
	_default_manifest_paths = [
		"%s/%s" % [
			GemTracedBakeContractScript.DEFAULT_OUTPUT_ROOT,
			GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME,
		],
		"%s/%s" % [
			GemTracedBakeContractScript.GENERATED_OUTPUT_ROOT,
			GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME,
		],
	]


func supports_request(request: Dictionary) -> bool:
	_ensure_manifest_loaded()
	var entry := _get_entry_for_request(request)
	return not entry.is_empty()


func request_bake(request: Dictionary) -> void:
	var start_usec := Time.get_ticks_usec()
	_ensure_manifest_loaded()
	var variant_key := String(request.get("variant_key", &""))
	var entry := _get_entry_for_request(request)
	if entry.is_empty():
		texture_baked.emit(request.get("tile_id", &""), null, {
			"backend_id": backend_id,
			"elapsed_ms": 0.0,
			"status": "missing_variant" if not _entries_by_key.has(variant_key) else "variant_size_mismatch",
			"variant_key": request.get("variant_key", &""),
			"manifest_path": _manifest_path,
		})
		return

	var texture: Texture2D = _load_texture(entry.get("texture_path", ""))
	texture_baked.emit(request.get("tile_id", &""), texture, {
		"backend_id": backend_id,
		"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
		"status": "ok" if texture != null else "load_failed",
		"manifest_path": _manifest_path,
		"source_path": entry.get("texture_path", ""),
		"variant_type": request.get("variant_type", &""),
		"variant_key": request.get("variant_key", &""),
		"lighting_bin": request.get("lighting_bin", Vector2i(-1, -1)),
		"rotation_bin": request.get("rotation_bin", -1),
	})


func shutdown() -> void:
	_manifest.clear()
	_entries_by_key.clear()
	_manifest_path = ""
	_manifest_modified_time = -1


func _ensure_manifest_loaded() -> void:
	var manifest_path := _resolve_manifest_path()
	if manifest_path.is_empty():
		_manifest.clear()
		_entries_by_key.clear()
		_manifest_path = ""
		_manifest_modified_time = -1
		return
	var modified_time := int(FileAccess.get_modified_time(manifest_path))
	if manifest_path == _manifest_path and modified_time == _manifest_modified_time and not _entries_by_key.is_empty():
		return
	_load_manifest(manifest_path, modified_time)


func _resolve_manifest_path() -> String:
	for candidate in _default_manifest_paths:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _load_manifest(manifest_path: String, modified_time: int) -> void:
	_manifest.clear()
	_entries_by_key.clear()
	_manifest_path = manifest_path
	_manifest_modified_time = modified_time
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if not GemTracedBakeContractScript.manifest_matches_current(parsed):
		return
	_manifest = parsed
	var entries: Array = _manifest.get("entries", [])
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var variant_key := String(entry.get("variant_key", ""))
		if variant_key.is_empty():
			continue
		_entries_by_key[variant_key] = entry


func _get_entry_for_request(request: Dictionary) -> Dictionary:
	var variant_key := String(request.get("variant_key", &""))
	if variant_key.is_empty():
		return {}
	var entry: Dictionary = _entries_by_key.get(variant_key, {})
	if entry.is_empty():
		return {}
	if not GemTracedBakeContractScript.entry_matches_request(entry, request):
		return {}
	return entry


func _load_texture(resource_path: String):
	if resource_path.is_empty():
		return null
	var normalized_path := resource_path
	if normalized_path.begins_with("res://"):
		var resource = load(normalized_path)
		if resource is Texture2D:
			return resource
	var image := Image.new()
	var load_path := normalized_path
	if normalized_path.begins_with("res://") or normalized_path.begins_with("user://"):
		load_path = ProjectSettings.globalize_path(normalized_path)
	var err := image.load(load_path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)
