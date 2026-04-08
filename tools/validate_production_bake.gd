extends SceneTree

const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const ProductionBakeProfileScript = preload("res://tools/production_bake_profile.gd")

var _errors: PackedStringArray = []
var _warnings: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_errors.clear()
	_warnings.clear()
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	if registry == null:
		_add_error("GemVisualRegistry autoload missing")
		_print_report()
		quit(1)
		return
	var args := _parse_args(OS.get_cmdline_user_args())
	var profile_path := String(args.get("profile", "")).strip_edges()
	if profile_path.is_empty():
		_add_error("Usage: --profile=res://config/bake_profiles/gameplay.json")
		_print_report()
		quit(1)
		return
	var profile: Dictionary = ProductionBakeProfileScript.load_profile_file(profile_path)
	if profile.is_empty():
		_print_report()
		quit(1)
		return
	var options: Dictionary = ProductionBakeProfileScript.profile_to_bake_options(profile, profile_path)
	var output_root := String(options.get("output_root", "")).strip_edges()
	if output_root.is_empty():
		_add_error("Profile output_root is empty")
		_print_report()
		quit(1)
		return
	var manifest_path := _join_path(output_root, GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME)
	if not FileAccess.file_exists(manifest_path):
		_add_error("Manifest missing: %s" % manifest_path)
		_print_report()
		quit(1)
		return
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		_add_error("Could not read manifest: %s" % manifest_path)
		_print_report()
		quit(1)
		return
	var parsed = JSON.parse_string(manifest_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_add_error("Manifest is not a JSON object")
		_print_report()
		quit(1)
		return
	var manifest: Dictionary = parsed
	_validate_identity(manifest, profile)
	_validate_geometry(manifest, profile, options)
	_validate_variant_settings(manifest, options)
	_validate_tiles(manifest, profile, registry)
	_validate_entries(manifest, output_root)
	_scan_orphan_textures(manifest, output_root, profile, registry)
	_print_report()
	quit(0 if _errors.is_empty() else 1)


func _add_error(msg: String) -> void:
	_errors.append(msg)
	push_error("validate_production_bake: %s" % msg)


func _add_warning(msg: String) -> void:
	_warnings.append(msg)
	push_warning("validate_production_bake: %s" % msg)


func _print_report() -> void:
	if not _warnings.is_empty():
		print("Warnings (%d):" % _warnings.size())
		for w in _warnings:
			print("  - %s" % w)
	if not _errors.is_empty():
		print("Errors (%d):" % _errors.size())
		for e in _errors:
			print("  - %s" % e)
	else:
		if _warnings.is_empty():
			print("Production bake validation: OK")


func _validate_identity(manifest: Dictionary, profile: Dictionary) -> void:
	var expect_id := String(profile.get("profile_id", "")).strip_edges()
	if not expect_id.is_empty():
		var got := String(manifest.get("profile_id", "")).strip_edges()
		if got != expect_id:
			_add_error("profile_id mismatch (manifest=%s profile=%s)" % [got, expect_id])
	if int(manifest.get("stylize_version", 0)) != GemTracedBakeContractScript.BAKED_LOOK_VERSION:
		_add_error(
			"stylize_version mismatch (manifest=%d expected=%d)" % [
				int(manifest.get("stylize_version", 0)),
				GemTracedBakeContractScript.BAKED_LOOK_VERSION,
			]
		)
	var prof_b := GemTracedBakeContractScript.resolve_max_trace_bounces(
		profile.get("max_trace_bounces", GemTracedBakeContractScript.DEFAULT_MAX_TRACE_BOUNCES)
	)
	if int(manifest.get("max_trace_bounces", 0)) != prof_b:
		_add_error(
			"max_trace_bounces mismatch (manifest=%d profile=%d)" % [
				int(manifest.get("max_trace_bounces", 0)),
				prof_b,
			]
		)
	if profile.has("vram_compress"):
		var want := bool(profile.get("vram_compress"))
		if not manifest.has("vram_compress"):
			_add_error("manifest missing vram_compress (profile expects %s)" % str(want))
		elif bool(manifest.get("vram_compress")) != want:
			_add_error("vram_compress mismatch (manifest=%s profile=%s)" % [
				str(manifest.get("vram_compress")),
				str(want),
			])
	if profile.has("atlas_output"):
		var want_a := bool(profile.get("atlas_output"))
		if not manifest.has("atlas_output"):
			_add_error("manifest missing atlas_output (profile expects %s)" % str(want_a))
		elif bool(manifest.get("atlas_output")) != want_a:
			_add_error("atlas_output mismatch (manifest=%s profile=%s)" % [
				str(manifest.get("atlas_output")),
				str(want_a),
			])


func _validate_geometry(manifest: Dictionary, profile: Dictionary, options: Dictionary) -> void:
	var cell := maxi(int(profile.get("cell_size", 112)), 16)
	var expect_cell := Vector2i(cell, cell)
	var m_cell := GemTracedBakeContractScript.normalize_size(manifest.get("cell_size"), Vector2i.ZERO)
	if m_cell != expect_cell:
		_add_error("cell_size mismatch manifest=%s expected=%s" % [str(m_cell), str(expect_cell)])
	var draw: Vector2i = options.get("draw_size", expect_cell)
	var m_draw := GemTracedBakeContractScript.normalize_size(manifest.get("draw_size"), Vector2i.ZERO)
	if m_draw != draw:
		_add_error("draw_size mismatch manifest=%s expected=%s" % [str(m_draw), str(draw)])
	var want_fmt := String(GemTracedBakeContractScript.normalize_image_format(options.get("image_format")))
	var got_fmt := String(manifest.get("image_format", "")).strip_edges().to_lower()
	if got_fmt != String(want_fmt):
		_add_error("image_format mismatch manifest=%s expected=%s" % [got_fmt, want_fmt])
	if int(manifest.get("sample_count", 0)) != int(options.get("sample_count", 1)):
		_add_error(
			"sample_count mismatch manifest=%d expected=%d" % [
				int(manifest.get("sample_count", 0)),
				int(options.get("sample_count", 1)),
			]
		)


func _validate_variant_settings(manifest: Dictionary, options: Dictionary) -> void:
	var entries: Array = manifest.get("entries", [])
	var rot_layers := GemTracedBakeContractScript.infer_rotation_layer_count_from_requests(entries)
	var expected := GemTracedBakeContractScript.merge_atlas_metadata_into_variant_settings(
		GemTracedBakeContractScript.build_manifest_variant_settings(options),
		rot_layers
	)
	var raw_vs: Dictionary = manifest.get("variant_settings", {})
	var actual := GemTracedBakeContractScript.merge_atlas_metadata_into_variant_settings(
		GemTracedBakeContractScript.build_manifest_variant_settings(raw_vs),
		rot_layers
	)
	if not _variant_settings_equal(expected, actual):
		_add_error(
			"variant_settings mismatch (atlas metadata or grid/rotation params differ from profile)"
		)


func _variant_settings_equal(expected: Dictionary, actual: Dictionary) -> bool:
	var keys := [
		"lighting_grid_preset",
		"lighting_grid_size",
		"lighting_runtime_grid_size",
		"rotation_base_view_count",
		"rotation_axis_steps",
		"rotation_step_degrees",
		"lighting_atlas_layers",
		"rotation_atlas_layers",
		"lighting_atlas_layer_order",
	]
	for k in keys:
		var ev = expected.get(k)
		var av = actual.get(k)
		if k.ends_with("_size"):
			ev = GemTracedBakeContractScript.normalize_size(ev, Vector2i.ZERO)
			av = GemTracedBakeContractScript.normalize_size(av, Vector2i.ZERO)
		if k == "rotation_step_degrees":
			if not is_equal_approx(float(ev), float(av)):
				return false
			continue
		if k == "lighting_grid_preset":
			if String(ev) != String(av):
				return false
			continue
		if ev != av:
			return false
	var e_axes: PackedStringArray = expected.get("rotation_axes", PackedStringArray())
	var a_axes = actual.get("rotation_axes", PackedStringArray())
	var e_list: Array = []
	for a in e_axes:
		e_list.append(String(a))
	var a_list: Array = []
	for b in a_axes:
		a_list.append(String(b))
	e_list.sort()
	a_list.sort()
	return e_list == a_list


func _validate_tiles(manifest: Dictionary, profile: Dictionary, registry: Node) -> void:
	var expected_ids: Array = ProductionBakeProfileScript.resolve_gems_list(profile.get("gems", "all"), registry)
	var tile_counts: Dictionary = manifest.get("tile_counts", {})
	for tid in expected_ids:
		var key := String(tid)
		if int(tile_counts.get(key, 0)) < 1:
			_add_error("tile_counts missing or zero for expected gem: %s" % key)


func _validate_entries(manifest: Dictionary, output_root: String) -> void:
	var entries: Array = manifest.get("entries", [])
	var root_norm := output_root.rstrip("/")
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var rel := String(entry.get("texture_path", "")).strip_edges()
		if rel.is_empty():
			_add_error("entry with empty texture_path (variant_key=%s)" % String(entry.get("variant_key", "")))
			continue
		if not rel.begins_with("res://"):
			_add_error("texture_path must be res:// path: %s" % rel)
			continue
		if not rel.begins_with(root_norm) and not _path_under_root(rel, root_norm):
			_add_warning("texture outside output_root: %s" % rel)
		if not FileAccess.file_exists(rel):
			_add_error("missing texture file: %s" % rel)


func _path_under_root(path: String, root_norm: String) -> bool:
	var r := root_norm
	var p := path.get_base_dir()
	return p.begins_with(r) or p == r


func _scan_orphan_textures(manifest: Dictionary, output_root: String, profile: Dictionary, registry: Node) -> void:
	var referenced := {}
	var entries: Array = manifest.get("entries", [])
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var p := String(raw.get("texture_path", "")).strip_edges()
		if not p.is_empty():
			referenced[ProjectSettings.globalize_path(p)] = true
	var expected_ids: Array = ProductionBakeProfileScript.resolve_gems_list(profile.get("gems", "all"), registry)
	var root_global := ProjectSettings.globalize_path(output_root)
	for tid in expected_ids:
		var sub := _join_path(output_root, String(tid))
		var abs_sub := ProjectSettings.globalize_path(sub)
		if not DirAccess.dir_exists_absolute(abs_sub):
			continue
		var dir := DirAccess.open(abs_sub)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and (fname.ends_with(".webp") or fname.ends_with(".png")):
				var full := abs_sub.path_join(fname)
				if not referenced.has(full):
					_add_warning("unreferenced texture (possible stale bake): %s" % full)
			fname = dir.get_next()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var trimmed := arg.substr(2)
		var parts := trimmed.split("=", false, 1)
		if parts.size() == 2:
			parsed[parts[0]] = parts[1]
		else:
			parsed[trimmed] = true
	return parsed


func _join_path(a: String, b: String) -> String:
	var aa := a.rstrip("/")
	return aa + "/" + b
