class_name GemStoreTransfer
extends RefCounted
## Consolidate completed, stopped farm shards. Inputs are constrained by an
## explicit job manifest. No source script/resource is loaded or executed.
var last_error := ""
var last_report: Dictionary = {}

func merge(destination: String, sources: PackedStringArray, manifest: Dictionary, apply := false, conflict_policy := "error") -> Dictionary:
	last_error = ""
	last_report = {}
	if conflict_policy not in ["error", "keep_existing"]:
		return _fail("Unknown conflict policy")
	var expected := _expected(manifest)
	if expected.is_empty():
		return _fail("Manifest has no valid render jobs")
	var target := _absolute(destination)
	var roots: Array[String] = [target]
	var inputs: Array[String] = []
	for source in sources:
		var path := _absolute(source)
		if path == target or path.begins_with(target + "/") or target.begins_with(path + "/"):
			return _fail("Source and destination stores must be disjoint")
		if not roots.has(path):
			roots.append(path)
			inputs.append(path)
	if inputs.is_empty():
		return _fail("No source stores")
	for root in roots:
		if not GemStorePath.owned_root(root):
			return _fail("Every transfer path must be an unlinked, marked artifact store: " + root)
	# Stop cooperative mutation of BOTH sides, including GC and checkpoint writes.
	# Nonblocking acquisition in canonical order: no wait cycle or timed lock stealing.
	roots.sort()
	var guards: Array[GemStoreGuard] = []
	for root in roots:
		var guard := GemStoreGuard.exclusive(root)
		if guard == null:
			for held in guards:
				held.release()
			return _fail("Store is active or locked; stop the shard before transfer: " + root)
		guards.append(guard)
	var result := _merge_locked(target, inputs, expected, str(manifest.engine), apply, conflict_policy)
	for guard in guards:
		guard.release()
	return result

func _merge_locked(target: String, sources: Array[String], expected: Dictionary, engine: String, apply: bool, policy: String) -> Dictionary:
	var selected := {}
	var conflicts: Array[Dictionary] = []
	var duplicates := 0
	var output := GemArtifactStore.new(target)
	var keys := expected.keys()
	keys.sort()
	# Destination has priority only under the explicit keep_existing policy.
	for root in [target] + sources:
		var store := GemArtifactStore.new(root)
		for key: String in keys:
			var relative := "recipes/" + key + ".json"
			if not FileAccess.file_exists(root.path_join(relative)):
				continue
			if not GemStorePath.regular_path(root, relative):
				return _fail("Linked recipe in transfer store")
			var file := FileAccess.open(root.path_join(relative), FileAccess.READ)
			if file == null or file.get_length() > 1024 * 1024:
				return _fail("Unreadable or oversized recipe")
			var header: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if not header is Dictionary or not GemArtifactStore.valid_key(str(header.get("sha256", ""))):
				return _fail("Invalid payload checksum descriptor")
			var digest := str(header.sha256)
			var object_path := "objects/%s/%s.blob" % [digest.left(2), digest]
			if header.get("object") != object_path or not GemStorePath.regular_path(root, object_path):
				return _fail("Invalid or linked payload path")
			var record := store.read(key)
			if record.is_empty():
				return _fail("Corrupt recipe or payload: " + key)
			var metadata: Dictionary = record.metadata
			var error := _validate_payload(record, expected[key], engine)
			if not error.is_empty():
				return _fail("Invalid result %s: %s" % [key, error])
			if selected.has(key):
				if selected[key].metadata.sha256 == metadata.sha256:
					duplicates += 1
				else:
					conflicts.append({"recipe": key, "kept_source": selected[key].root, "other_source": root,
						"kept_sha256": selected[key].metadata.sha256, "other_sha256": metadata.sha256})
				continue
			selected[key] = {"root": root, "metadata": metadata}
	if not conflicts.is_empty() and policy == "error":
		last_report = {"applied": false, "conflicts": conflicts}
		return _fail("Conflicting payloads for %d recipe(s); nothing imported. Use keep_existing only after reviewing source precedence." % conflicts.size())
	var written := 0
	var bytes := 0
	var missing := PackedStringArray()
	for key: String in keys:
		if not selected.has(key):
			missing.append(key)
			continue
		var entry: Dictionary = selected[key]
		if entry.root == target:
			continue
		bytes += int(entry.metadata.bytes)
		if apply:
			# Sources remain exclusively locked. Stream one payload, not the full farm.
			var record := GemArtifactStore.new(entry.root).read(key)
			if record.is_empty() or not output._publish_active(key, record.payload, record.metadata):
				return _fail("I/O failure after %d imports; retry safely: %s" % [written, key])
		written += 1
	return {"applied": apply, "recipes_to_import": written, "payload_bytes": bytes,
		"duplicates": duplicates, "conflicts": conflicts, "missing": Array(missing),
		"available_recipes": selected.size(), "required_recipes": expected.size()}

static func _expected(manifest: Dictionary) -> Dictionary:
	if manifest.get("schema") != 1 or not manifest.get("jobs") is Dictionary or not GemArtifactStore.valid_key(str(manifest.get("engine", ""))):
		return {}
	var expected := {}
	for key: Variant in manifest.jobs:
		if not key is String or not GemArtifactStore.valid_key(key) or not manifest.jobs[key] is Dictionary:
			return {}
		var master := str(manifest.jobs[key].get("master", ""))
		if not GemArtifactStore.valid_key(master) or key == master:
			return {}
		if expected.has(key) and expected[key].kind != "display":
			return {}
		if expected.has(master) and expected[master].kind != "linear_master":
			return {}
		expected[key] = {"kind": "display", "master": master}
		expected[master] = {"kind": "linear_master"}
	return expected

static func _validate_payload(record: Dictionary, expected: Dictionary, engine: String) -> String:
	var metadata: Dictionary = record.metadata
	if metadata.get("kind") != expected.kind:
		return "unexpected artifact kind"
	var width := int(metadata.get("width", 0))
	var height := int(metadata.get("height", 0))
	if width < 1 or height < 1 or width > 8192 or height > 8192:
		return "invalid frame dimensions"
	var image: Image
	if expected.kind == "linear_master":
		if metadata.get("engine") != engine or metadata.get("space") != "associated_XYZ_CIE1931_2deg":
			return "optical engine or linear color space mismatch"
		image = GemArtifactStore.decode_linear(record.payload)
	else:
		if metadata.get("master") != expected.master or metadata.get("status") != "complete" or metadata.get("codec") != "webp_lossless" or metadata.get("space") != "srgb_straight_alpha":
			return "display dependency, codec, or completion mismatch"
		image = Image.new()
		if image.load_webp_from_buffer(record.payload) != OK:
			return "invalid WebP payload"
	if image == null or image.get_size() != Vector2i(width, height):
		return "decoded dimensions differ from recipe"
	return ""

static func _absolute(path: String) -> String:
	var result := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().trim_suffix("/")
	return result.to_lower() if OS.get_name() == "Windows" else result

func _fail(message: String) -> Dictionary:
	last_error = message
	last_report["error"] = message
	return {}
