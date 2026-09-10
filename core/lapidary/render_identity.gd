class_name GemRenderIdentity
extends RefCounted
## Recipe identity is independent of worker/GPU identity. A packaged result
## may be served on any device; its producer and validation live in metadata.

static var _engine_digest := ""

static func engine_digest() -> String:
	if _engine_digest.is_empty():
		var files: Array[String] = []
		for root in ["res://core/lapidary", "res://resources/lapidary"]:
			_collect(root, files)
		files.sort()
		var sources: Array = []
		for path in files:
			sources.append([path, FileAccess.get_sha256(path)])
		_engine_digest = GemContentIdentity.digest(sources)
	return _engine_digest


static func context(rung: int, overrides: Dictionary = {}) -> Dictionary:
	var result := {
		"engine": engine_digest(),
		"policy": GemRung.policy(rung),
		"rig": load("res://data/lapidary/rigs/gameplay_studio.tres"),
		"print": GemPrint.load_house(),
		"framing": 1.25,
		"output": "srgb-straight-alpha",
	}
	result.merge(overrides, true)
	return result


static func _collect(root: String, files: Array[String]) -> void:
	var directory := DirAccess.open(root)
	assert(directory != null, "Missing render source directory: " + root)
	for file in directory.get_files():
		if file.get_extension() in ["gd", "glsl"]:
			files.append(root.path_join(file))
	for child in directory.get_directories():
		_collect(root.path_join(child), files)
