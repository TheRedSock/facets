class_name GemJobBundle
extends RefCounted
## A minimal independent Godot project plus bundled authored jobs. No game
## scenes, autoloads, imported textures, models or developer cache are required.
static func write(root: String, jobs: Array[GemFrameJob], clips: Dictionary) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/")
	if absolute == ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/"):
		push_error("A worker bundle cannot overwrite the current project")
		return {}
	if FileAccess.file_exists(root.path_join("project.godot")) and not FileAccess.file_exists(root.path_join("manifest.json")):
		push_error("Destination contains another Godot project")
		return {}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("jobs"))) != OK:
		return {}
	var files: Array[String] = []
	for source in ["res://core/lapidary", "res://resources/lapidary", "res://data/lapidary/standards"]:
		_collect(source, files)
	files.append("res://tools/gem_frame_worker.gd")
	var checksums := {}
	for source in files:
		var relative := source.trim_prefix("res://")
		if not GemArtifactStore.atomic_write(root.path_join(relative), FileAccess.get_file_as_bytes(source)):
			return {}
		checksums[relative] = FileAccess.get_sha256(source)
	var records := {}
	for job in jobs:
		var key := GemFramePlan.display_key(job)
		if records.has(key):
			continue
		# Binary resources preserve float64 scalar values. Text .tres saving
		# rounds some animation parameters and cannot be an immutable job wire format.
		var relative := "jobs/" + key + ".res"
		if GemResourceBundle.save(job, root.path_join(relative)) != OK:
			return {}
		records[key] = {"path": relative, "master": GemFramePlan.master_key(job), "sha256": FileAccess.get_sha256(root.path_join(relative))}
	var project := 'config_version=5\n\n[application]\nconfig/name="Lapidary Asset Worker"\n\n[rendering]\nrenderer/rendering_method="mobile"\n'
	if not GemArtifactStore.atomic_write(root.path_join("project.godot"), project.to_utf8_buffer()):
		return {}
	var manifest := {"schema": 1, "engine": GemRenderIdentity.optical_digest(), "godot": Engine.get_version_info(),
		"source_sha256": checksums, "jobs": records, "clips": clips, "estimate": GemFramePlan.estimate(jobs),
		"worker": {"gpu_required": true, "headless_supported": false,
			"import_args": ["--headless", "--editor", "--quit"],
			"run_args": ["--script", "res://tools/gem_frame_worker.gd", "--", "--manifest=res://manifest.json", "--output=res://output"]}}
	if not GemArtifactStore.atomic_write(root.path_join("manifest.json"), JSON.stringify(manifest, "\t").to_utf8_buffer()):
		return {}
	return manifest

static func _collect(root: String, files: Array[String]) -> void:
	for file in DirAccess.get_files_at(root):
		if file.get_extension() in ["gd", "glsl", "uid", "csv", "json"] or file == ".gdignore":
			files.append(root.path_join(file))
	for directory in DirAccess.get_directories_at(root):
		_collect(root.path_join(directory), files)

static func archive(root: String, path: String) -> Error:
	var zip := ZIPPacker.new()
	var result := zip.open(path)
	if result != OK:
		return result
	var files: Array[String] = []
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("manifest.json")))
	files.assign([root.path_join("manifest.json"), root.path_join("project.godot")])
	for relative: String in manifest["source_sha256"]:
		files.append(root.path_join(relative))
	for key: String in manifest["jobs"]:
		files.append(root.path_join(manifest["jobs"][key]["path"]))
	files.sort()
	for file in files:
		result = zip.start_file(file.trim_prefix(root.trim_suffix("/") + "/"))
		if result == OK:
			result = zip.write_file(FileAccess.get_file_as_bytes(file))
		zip.close_file()
		if result != OK:
			zip.close()
			return result
	return zip.close()
