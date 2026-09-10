class_name GemRenderIdentity
extends RefCounted
## Recipe identity is independent of worker/GPU identity. A packaged result
## may be served on any device; its producer and validation live in metadata.

static var _optical_digest := ""

static func optical_digest() -> String:
	if _optical_digest.is_empty():
		var files: Array[String] = []
		for root in ["res://core/lapidary/cut", "res://core/lapidary/geometry", "res://core/lapidary/lighting", "res://core/lapidary/tracer", "res://resources/lapidary"]:
			_collect(root, files)
		files.append("res://core/lapidary/stone_compiler.gd")
		files.append("res://core/lapidary/material_compiler.gd")
		files.sort()
		var sources: Array = [Engine.get_version_info().get("hash", "unknown")]
		for path in files:
			# Factory scheduling, delivery codecs and runtime cache policy must
			# not retire expensive optical masters.
			sources.append([path, FileAccess.get_sha256(path)])
		_optical_digest = GemContentIdentity.digest(sources)
	return _optical_digest

static func _collect(root: String, files: Array[String]) -> void:
	var directory := DirAccess.open(root)
	assert(directory != null, "Missing render source directory: " + root)
	for file in directory.get_files():
		if file.get_extension() in ["gd", "glsl"]:
			files.append(root.path_join(file))
	for child in directory.get_directories():
		_collect(root.path_join(child), files)
