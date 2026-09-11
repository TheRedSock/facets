class_name GemJobBundle
extends RefCounted
## A minimal independent Godot project plus bundled authored jobs. No game
## scenes, autoloads, imported textures, models or developer cache are required.
static func write(root: String, jobs: Array[GemFrameJob], clips: Dictionary, geometry_coverage_side := 0) -> Dictionary:
	if geometry_coverage_side not in [0, 1, 2, 4, 8]:
		push_error("Invalid requested geometry coverage")
		return {}
	for index in jobs.size():
		var error := GemJobValidator.validate(jobs[index])
		if error.is_empty() and geometry_coverage_side > 0:
			error = GemGeometryPlan.validate(jobs[index], geometry_coverage_side)
		if not error.is_empty():
			push_error("Job %d rejected before packaging: %s" % [index, error])
			return {}
	var absolute := ProjectSettings.globalize_path(root).replace("\\", "/").simplify_path().trim_suffix("/")
	if absolute == ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/"):
		push_error("A worker bundle cannot overwrite the current project")
		return {}
	if FileAccess.file_exists(root.path_join("project.godot")) and not FileAccess.file_exists(root.path_join("manifest.json")) and not FileAccess.file_exists(root.path_join("bundle.json")):
		push_error("Destination contains another Godot project")
		return {}
	if not _claim(absolute):
		push_error("Bundle output must be an unlinked empty directory or a previously generated bundle")
		return {}
	if not _safe_existing_tree(absolute):
		push_error("Generated bundle subtrees must not contain linked paths")
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
	var geometry := {}
	for job in jobs:
		var key := GemFramePlan.display_key(job)
		if records.has(key):
			continue
		# Binary resources preserve float64 scalar values. Text .tres saving
		# rounds some animation parameters and cannot be an immutable job wire format.
		var relative := "jobs/" + key + ".res"
		if GemResourceBundle.save(job, root.path_join(relative)) != OK:
			return {}
		records[key] = {"path": relative, "master": GemFramePlan.master_key(job), "engine": GemFramePlan.master_engine(job),
			"display_engine": GemFramePlan.display_engine(job), "sha256": FileAccess.get_sha256(root.path_join(relative))}
		if geometry_coverage_side > 0:
			var geometry_key := GemGeometryPlan.key(job, geometry_coverage_side)
			records[key]["geometry"] = geometry_key
			if not geometry.has(geometry_key):
				geometry[geometry_key] = {"path": relative, "sha256": records[key].sha256, "engine": GemGeometryPlan.source_digest(),
					"width": job.resolution.x, "height": job.resolution.y, "coverage_side": geometry_coverage_side}
	var project := 'config_version=5\n\n[application]\nconfig/name="Lapidary Asset Worker"\n\n[rendering]\nrenderer/rendering_method="mobile"\n'
	if not GemArtifactStore.atomic_write(root.path_join("project.godot"), project.to_utf8_buffer()):
		return {}
	var manifest := {"schema": 1, "engine": GemRenderIdentity.worker_digest(), "godot": Engine.get_version_info(),
		"source_sha256": checksums, "jobs": records, "geometry": geometry, "clips": clips, "estimate": GemFramePlan.estimate(jobs),
		"worker": {"gpu_required_for": ["transport", "mastering", "primary_geometry"], "headless_operations": ["cached_results", "style_cached_print"],
			"import_args": ["--headless", "--editor", "--quit"],
			"run_args": ["--audio-driver", "Dummy", "--script", "res://tools/gem_frame_worker.gd", "--", "--manifest=res://manifest.json", "--output=res://output"]}}
	if not _prune_generated(absolute, checksums, records):
		push_error("Cannot remove obsolete generated bundle files")
		return {}
	if not GemArtifactStore.atomic_write(root.path_join("manifest.json"), JSON.stringify(manifest, "\t").to_utf8_buffer()):
		return {}
	return manifest

static func _claim(root: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(root) != OK or not GemStorePath.unlinked_root(root):
		return false
	var marker_path := root.path_join("bundle.json")
	if FileAccess.file_exists(marker_path):
		if not GemStorePath.regular_path(root, "bundle.json"):
			return false
		var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
		return marker is Dictionary and marker.get("kind") == "lapidary_job_bundle" and marker.get("schema") == 1
	var files := DirAccess.get_files_at(root)
	var directories := DirAccess.get_directories_at(root)
	if not files.is_empty() or not directories.is_empty():
		# Adopt earlier generated bundles, never an arbitrary nonempty directory.
		if not GemStorePath.regular_path(root, "manifest.json") or not FileAccess.file_exists(root.path_join("manifest.json")):
			return false
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("manifest.json")))
		if not old is Dictionary or old.get("schema") != 1 or not GemArtifactStore.valid_key(str(old.get("engine", ""))) or not old.get("source_sha256") is Dictionary or not old.get("jobs") is Dictionary or not old.get("worker") is Dictionary:
			return false
	return GemArtifactStore.atomic_write(marker_path, '{"kind":"lapidary_job_bundle","schema":1}'.to_utf8_buffer())

static func _prune_generated(root: String, sources: Dictionary, jobs: Dictionary) -> bool:
	var wanted := sources.duplicate()
	for record: Dictionary in jobs.values():
		wanted[record.path] = true
	var owned: Array[String] = []
	for subtree in ["core/lapidary", "resources/lapidary", "data/lapidary/standards", "tools"]:
		if not _inventory_generated(root, subtree, owned):
			return false
	if not GemStorePath.regular_path(root, "jobs"):
		return false
	for file in DirAccess.get_files_at(root.path_join("jobs")):
		if file.get_extension() == "res" and GemArtifactStore.valid_key(file.get_basename()):
			owned.append("jobs/" + file)
	# Explicit file inventory only: no recursive deletion and no paths supplied
	# by old manifests. Generated source subtrees are owned by this bundle.
	for relative in owned:
		if not wanted.has(relative):
			if not GemStorePath.regular_path(root, relative) or DirAccess.remove_absolute(root.path_join(relative)) != OK:
				return false
	return true

static func _safe_existing_tree(root: String) -> bool:
	for relative in ["core/lapidary", "resources/lapidary", "data/lapidary/standards", "tools", "jobs"]:
		var cursor := root
		for component in relative.split("/"):
			var directory := DirAccess.open(cursor)
			if directory == null:
				break # Remaining components do not exist yet.
			if directory.is_link(component):
				return false
			cursor = cursor.path_join(component)
		if DirAccess.dir_exists_absolute(root.path_join(relative)):
			var inventory: Array[String] = []
			if not _inventory_generated(root, relative, inventory):
				return false
	return true

static func _inventory_generated(root: String, relative: String, files: Array[String]) -> bool:
	if not GemStorePath.regular_path(root, relative):
		return false
	var path := root.path_join(relative)
	for name in DirAccess.get_files_at(path):
		if not GemStorePath.regular_path(root, relative.path_join(name)):
			return false
		if name.get_extension() in ["gd", "glsl", "uid", "csv", "json"] or name == ".gdignore":
			files.append(relative.path_join(name))
	for name in DirAccess.get_directories_at(path):
		if not _inventory_generated(root, relative.path_join(name), files):
			return false
	return true

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
