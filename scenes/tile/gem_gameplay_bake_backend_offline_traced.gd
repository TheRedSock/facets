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
var _texture_cache: Dictionary = {}


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
	var manifest_lookup_elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	var variant_key := String(request.get("variant_key", &""))
	var entry := _get_entry_for_request(request)
	if entry.is_empty():
		texture_baked.emit(request.get("tile_id", &""), null, {
			"backend_id": backend_id,
			"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
			"manifest_lookup_elapsed_ms": manifest_lookup_elapsed_ms,
			"status": "missing_variant" if not _entries_by_key.has(variant_key) else "variant_size_mismatch",
			"variant_key": request.get("variant_key", &""),
			"manifest_path": _manifest_path,
		})
		return

	var texture_start_usec := Time.get_ticks_usec()
	var texture_result := _load_texture_cached(entry.get("texture_path", ""))
	var texture: Texture2D = texture_result.get("texture", null)
	var texture_load_elapsed_ms := (Time.get_ticks_usec() - texture_start_usec) / 1000.0
	texture_baked.emit(request.get("tile_id", &""), texture, {
		"backend_id": backend_id,
		"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
		"manifest_lookup_elapsed_ms": manifest_lookup_elapsed_ms,
		"texture_load_elapsed_ms": texture_load_elapsed_ms,
		"texture_cache_hit": bool(texture_result.get("cache_hit", false)),
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
	_texture_cache.clear()


func reload_manifest() -> void:
	_manifest_modified_time = -1
	_ensure_manifest_loaded()


func prefetch_requests(requests: Array) -> Dictionary:
	_ensure_manifest_loaded()
	if requests.is_empty():
		return {
			"texture_count": 0,
			"elapsed_ms": 0.0,
		}
	var start_usec := Time.get_ticks_usec()
	var texture_count := 0
	var seen_paths: Dictionary = {}
	for raw_request in requests:
		if typeof(raw_request) != TYPE_DICTIONARY:
			continue
		var request: Dictionary = raw_request
		var entry := _get_entry_for_request(request)
		if entry.is_empty():
			continue
		var source_path := String(entry.get("texture_path", ""))
		if source_path.is_empty() or seen_paths.has(source_path):
			continue
		seen_paths[source_path] = true
		var texture_result := _load_texture_cached(source_path)
		if texture_result.get("texture", null) != null:
			texture_count += 1
	return {
		"texture_count": texture_count,
		"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
	}


func get_manifest_variant_settings() -> Dictionary:
	_ensure_manifest_loaded()
	if _manifest.is_empty():
		return GemTracedBakeContractScript.default_variant_settings()
	return GemTracedBakeContractScript.get_manifest_variant_settings(_manifest)


func get_manifest_path() -> String:
	_ensure_manifest_loaded()
	return _manifest_path


func get_manifest_summary() -> Dictionary:
	_ensure_manifest_loaded()
	return {
		"manifest_path": _manifest_path,
		"cell_size": GemTracedBakeContractScript.normalize_size(
			_manifest.get("cell_size", Vector2i.ZERO),
			Vector2i.ZERO
		),
		"draw_size": GemTracedBakeContractScript.normalize_size(
			_manifest.get("draw_size", Vector2i.ZERO),
			Vector2i.ZERO
		),
		"variant_settings": get_manifest_variant_settings(),
	}


func _ensure_manifest_loaded() -> void:
	var manifest_path := _resolve_manifest_path()
	if manifest_path.is_empty():
		_manifest.clear()
		_entries_by_key.clear()
		_texture_cache.clear()
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
	_texture_cache.clear()
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


func _load_texture_cached(resource_path: String) -> Dictionary:
	if resource_path.is_empty():
		return {
			"texture": null,
			"cache_hit": false,
		}
	if _texture_cache.has(resource_path):
		return {
			"texture": _texture_cache[resource_path],
			"cache_hit": true,
		}
	var normalized_path := resource_path
	if normalized_path.begins_with("res://"):
		var resource = load(normalized_path)
		if resource is Texture2D:
			_texture_cache[resource_path] = resource
			return {
				"texture": resource,
				"cache_hit": false,
			}
	var image := Image.new()
	var load_path := normalized_path
	if normalized_path.begins_with("res://") or normalized_path.begins_with("user://"):
		load_path = ProjectSettings.globalize_path(normalized_path)
	var err := image.load(load_path)
	if err != OK:
		return {
			"texture": null,
			"cache_hit": false,
		}
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[resource_path] = texture
	return {
		"texture": texture,
		"cache_hit": false,
	}
