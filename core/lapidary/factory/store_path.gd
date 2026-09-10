class_name GemStorePath
extends RefCounted
## Local filesystem ownership checks shared by cache maintenance and transfer.
static func regular_path(base: String, relative: String) -> bool:
	var path := base
	for component in relative.split("/"):
		if component in ["", ".", ".."]:
			return false
		var parent := DirAccess.open(path)
		if parent == null or parent.is_link(component):
			return false
		path = path.path_join(component)
	return path.simplify_path().begins_with(base + "/")

static func unlinked_root(base: String) -> bool:
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
	return true

static func owned_root(base: String) -> bool:
	if not unlinked_root(base) or not regular_path(base, "store.json"):
		return false
	if not FileAccess.file_exists(base.path_join("store.json")):
		return false
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("store.json")))
	return marker is Dictionary and marker.get("kind") == "lapidary_artifact_store" and marker.get("schema") == 1
