class_name GemRenderIdentity
extends RefCounted
## Result compatibility is distinct from the complete renderer inventory.
## Unknown/new files are shared conservatively until explicitly classified.
const EXCLUSIVE := {
	"style": ["core/lapidary/style_pipeline.gd", "resources/lapidary/gem_style.gd"],
	"frame_execution": ["core/lapidary/factory/frame_worker.gd"],
	"crystal": ["core/lapidary/tracer/crystal_shader.gd", "core/lapidary/tracer/shaders/gem_crystal.glsl", "core/lapidary/tracer/shaders/gem_crystal_path.glsl"],
	"print": ["core/lapidary/tracer/shaders/gem_print.glsl", "resources/lapidary/gem_print.gd"],
	"geometry": ["core/lapidary/tracer/geometry_aov.gd", "core/lapidary/tracer/shaders/gem_geometry_aov.glsl"],
	"transport": ["core/lapidary/tracer/shaders/gem_pathtrace.glsl", "core/lapidary/tracer/shaders/gem_surface.glsl",
		"core/lapidary/tracer/shaders/gem_volume.glsl", "core/lapidary/tracer/shaders/gem_polarization.glsl", "core/lapidary/tracer/shaders/gem_denoise.glsl", "core/lapidary/microsurface/smith_walk.glsl"]
}
const DOMAINS := ["worker", "scalar", "polarized", "crystal", "print", "geometry", "style"]
static var _inventory: Dictionary = {}
static var _digests: Dictionary = {}

static func worker_digest() -> String:
	return pipeline_digest("worker")

static func transport_domain(policy: Dictionary) -> String:
	return "crystal" if policy.get("crystal_transport", false) else ("polarized" if policy.get("polarization", false) else "scalar")

static func pipeline_digest(domain: String) -> String:
	if not _digests.has(domain):
		_digests[domain] = digest_inventory(domain, inventory(), Engine.get_version_info().get("hash", "unknown"))
	return _digests[domain]

## Detached inventory for dependency mutation tests without editing live files.
static func inventory() -> Dictionary:
	if _inventory.is_empty():
		var files: Array[String] = []
		for root in ["res://core/lapidary/cut", "res://core/lapidary/geometry", "res://core/lapidary/lighting", "res://core/lapidary/tracer", "res://resources/lapidary"]:
			_collect(root, files)
		files.append_array(["res://core/lapidary/stone_compiler.gd", "res://core/lapidary/material_compiler.gd",
			"res://core/lapidary/style_pipeline.gd",
			"res://core/lapidary/render_identity.gd", "res://core/lapidary/factory/frame_worker.gd",
			"res://core/lapidary/factory/frame_plan.gd", "res://core/lapidary/microsurface/smith_walk.glsl", GemStandardSpectra.CMF_FILE, GemStandardSpectra.D65_FILE])
		for path in files:
			_inventory[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
	return _inventory.duplicate()

static func digest_inventory(domain: String, hashes: Dictionary, engine_hash: String) -> String:
	assert(domain in DOMAINS, "Unknown result pipeline")
	var paths := hashes.keys()
	paths.sort()
	var sources: Array = ["pipeline-source-v1", domain, engine_hash]
	for path: String in paths:
		if includes_source(domain, path):
			sources.append([path, hashes[path]])
	return GemContentIdentity.digest(sources)

static func includes_source(domain: String, path: String) -> bool:
	assert(domain in DOMAINS)
	if domain == "worker":
		return true
	for group: String in EXCLUSIVE:
		if path in EXCLUSIVE[group]:
			if group == "frame_execution":
				return domain != "geometry"
			return domain in ["scalar", "polarized", "crystal"] if group == "transport" else domain == group
	return true

static func _collect(root: String, files: Array[String]) -> void:
	var directory := DirAccess.open(root)
	assert(directory != null, "Missing render source directory: " + root)
	for file in directory.get_files():
		if file.get_extension() in ["gd", "glsl"]:
			files.append(root.path_join(file))
	for child in directory.get_directories():
		_collect(root.path_join(child), files)
