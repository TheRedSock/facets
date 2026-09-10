class_name GemStoreMaintenance
extends RefCounted
## Required manifests pin optical masters, displays and incomplete checkpoints.
## Spare budget retains newest unpinned optical masters. Other old prints and
## completed checkpoints are reproducible and do not consume retention budget.
var last_error := ""

func collect(root: String, manifests: Array, budget_bytes: int, apply := false) -> Dictionary:
	last_error = ""
	var base := ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/")
	if not _owned_root(base):
		return _fail("Not a marked gemstone artifact store, or store path is linked")
	var guard := GemStoreGuard.exclusive(base)
	if guard == null:
		return _fail("Store has active workers/readers or another maintenance operation")
	var result := _collect_locked(base, manifests, maxi(0, budget_bytes), apply)
	guard.release()
	return result

func _collect_locked(base: String, manifests: Array, budget: int, apply: bool) -> Dictionary:
	var records := {}
	var objects := {}
	var temporaries := {}
	for name in DirAccess.get_files_at(base.path_join("recipes")):
		if _owned_temporary(name, "json"):
			_inventory_temporary(base, "recipes/" + name, temporaries)
			continue
		if name.get_extension() != "json" or not GemArtifactStore.valid_key(name.get_basename()):
			continue
		var relative := "recipes/" + name
		if not _regular_path(base, relative):
			continue
		var file := FileAccess.open(base.path_join(relative), FileAccess.READ)
		if file == null or file.get_length() > 1024 * 1024:
			return _fail("Unreadable/oversized recipe: " + relative)
		var record: Variant = JSON.parse_string(file.get_as_text())
		if not record is Dictionary or record.get("schema") != 1 or record.get("recipe") != name.get_basename() or not GemArtifactStore.valid_key(str(record.get("sha256", ""))):
			return _fail("Malformed recipe; repair it before collection: " + relative)
		var digest: String = record["sha256"]
		if record.get("object") != "objects/%s/%s.blob" % [digest.left(2), digest]:
			return _fail("Recipe object path is invalid: " + relative)
		record["record_bytes"] = file.get_length()
		file.close()
		record["mtime"] = FileAccess.get_modified_time(base.path_join(relative))
		records[name.get_basename()] = record
	for directory in DirAccess.get_directories_at(base.path_join("objects")):
		if directory.length() != 2 or not directory.is_valid_hex_number() or not _regular_path(base, "objects/" + directory):
			continue
		for name in DirAccess.get_files_at(base.path_join("objects/" + directory)):
			if _owned_temporary(name, "blob") and name.left(2) == directory:
				_inventory_temporary(base, "objects/" + directory + "/" + name, temporaries)
				continue
			var digest := name.get_basename()
			if name.get_extension() != "blob" or not GemArtifactStore.valid_key(digest) or digest.left(2) != directory:
				continue
			var relative := "objects/" + directory + "/" + name
			if not _regular_path(base, relative):
				continue
			var file := FileAccess.open(base.path_join(relative), FileAccess.READ)
			if file != null:
				objects[digest] = {"path": relative, "bytes": file.get_length(), "valid": FileAccess.get_sha256(base.path_join(relative)) == digest}
				file.close()
	var required := {}
	for manifest: Variant in manifests:
		if not manifest is Dictionary or manifest.get("schema") != 1 or not manifest.get("jobs") is Dictionary:
			return _fail("Invalid retention manifest")
		for key: String in manifest["jobs"]:
			var job: Variant = manifest["jobs"][key]
			if not job is Dictionary or not GemArtifactStore.valid_key(key) or not GemArtifactStore.valid_key(str(job.get("master", ""))):
				return _fail("Invalid retained job identity")
			var master: String = job["master"]
			required[key] = true
			required[master] = true
			if not _available(master, records, objects):
				required[GemContentIdentity.digest(["checkpoint-v1", master])] = true
	# Keep dependencies even if a retained display was produced by an older manifest.
	for key: String in required.keys():
		if records.has(key) and records[key].get("kind") == "display":
			var master := str(records[key].get("master", ""))
			if not GemArtifactStore.valid_key(master):
				return _fail("Display has an invalid optical master")
			required[master] = true
	var keep := {}
	var marked := {}
	var kept_bytes := 0
	for key: String in required:
		if records.has(key):
			kept_bytes += _retain(key, records, objects, keep, marked)
	var pinned_bytes := kept_bytes
	var candidates := []
	for key: String in records:
		if not keep.has(key) and records[key].get("kind") == "linear_master" and _available(key, records, objects):
			candidates.append(key)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		return records[a]["mtime"] > records[b]["mtime"] if records[a]["mtime"] != records[b]["mtime"] else a < b)
	for key: String in candidates:
		var record: Dictionary = records[key]
		var cost: int = record["record_bytes"]
		if not marked.has(record["sha256"]):
			cost += int(objects[record["sha256"]]["bytes"])
		if kept_bytes + cost <= budget:
			kept_bytes += _retain(key, records, objects, keep, marked)
	var remove: Array[String] = []
	var removed_bytes := 0
	for key: String in records:
		if not keep.has(key):
			remove.append("recipes/" + key + ".json")
			removed_bytes += int(records[key]["record_bytes"])
	for digest: String in objects:
		if not marked.has(digest):
			remove.append(objects[digest]["path"])
			removed_bytes += int(objects[digest]["bytes"])
	for relative: String in temporaries:
		remove.append(relative)
		removed_bytes += int(temporaries[relative])
	# Fixed inventory only, no recursive deletion or paths taken from a manifest.
	# Remove unretained recipes before their objects; a crash can leave orphans,
	# but cannot strand a retained recipe by deleting its dependency.
	if apply:
		for relative in remove:
			if not _regular_path(base, relative) or DirAccess.remove_absolute(base.path_join(relative)) != OK:
				return _fail("Cannot remove cache entry: " + relative)
	return {"applied": apply, "files_to_remove": remove.size(), "removed_bytes": removed_bytes,
		"retained_bytes": kept_bytes, "pinned_bytes": pinned_bytes, "budget_bytes": budget,
		"over_budget_bytes": maxi(0, pinned_bytes - budget), "kept_recipes": keep.size(),
		"kept_objects": marked.size(), "paths": remove}

static func _owned_temporary(name: String, extension: String) -> bool:
	var parts := name.split(".")
	return parts.size() == 5 and GemArtifactStore.valid_key(parts[0]) and parts[1] == extension and parts[2].is_valid_int() and parts[3].is_valid_int() and parts[4] == "tmp"

static func _inventory_temporary(base: String, relative: String, inventory: Dictionary) -> void:
	if _regular_path(base, relative):
		var file := FileAccess.open(base.path_join(relative), FileAccess.READ)
		if file != null:
			inventory[relative] = file.get_length()
			file.close()

static func _available(key: String, records: Dictionary, objects: Dictionary) -> bool:
	return records.has(key) and objects.has(records[key]["sha256"]) and objects[records[key]["sha256"]]["valid"] and int(records[key].get("bytes", -1)) == int(objects[records[key]["sha256"]]["bytes"])

static func _retain(key: String, records: Dictionary, objects: Dictionary, keep: Dictionary, marked: Dictionary) -> int:
	if keep.has(key):
		return 0
	keep[key] = true
	var record: Dictionary = records[key]
	var cost: int = record["record_bytes"]
	var digest: String = record["sha256"]
	if objects.has(digest) and not marked.has(digest):
		marked[digest] = true
		cost += int(objects[digest]["bytes"])
	return cost

static func _regular_path(base: String, relative: String) -> bool:
	var path := base
	for component in relative.split("/"):
		if component in ["", ".", ".."]:
			return false
		var parent := DirAccess.open(path)
		if parent == null or parent.is_link(component):
			return false
		path = path.path_join(component)
	return path.simplify_path().begins_with(base + "/")

static func _owned_root(base: String) -> bool:
	if base == base.get_base_dir() or base.get_file().is_empty():
		return false
	var cursor := base
	while not cursor.get_file().is_empty():
		var parent_path := cursor.get_base_dir()
		if parent_path == cursor or parent_path.is_empty():
			break
		if parent_path.ends_with(":"):
			parent_path += "/"
		var parent := DirAccess.open(parent_path)
		if parent == null or parent.is_link(cursor.get_file()):
			return false
		cursor = parent_path
	if not FileAccess.file_exists(base.path_join("store.json")):
		return false
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("store.json")))
	return marker is Dictionary and marker.get("kind") == "lapidary_artifact_store" and marker.get("schema") == 1

func _fail(message: String) -> Dictionary:
	last_error = message
	return {}
