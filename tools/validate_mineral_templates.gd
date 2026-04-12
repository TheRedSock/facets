extends SceneTree

## Validates all mineral templates and gem visual resources.
##
## Usage:
##   godot --headless --script tools/validate_mineral_templates.gd

const MINERAL_DATA_PATH := "res://data/minerals/"
const VISUAL_DATA_PATH := "res://data/visuals/"

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _check_count := 0

## Published reference IOR at 589nm sodium D-line for verification.
const PUBLISHED_IOR := {
	&"diamond": 2.417,
	&"quartz": 1.544,
	&"corundum": 1.768,
	&"beryl": 1.577,
	&"topaz": 1.619,
	&"fluorite": 1.434,
	&"olivine": 1.654,
	&"chrysoberyl": 1.746,
	&"tourmaline": 1.624,
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("\n=== Mineral Template Validation ===\n")

	# 1. Validate all templates
	var templates := _load_resources(MINERAL_DATA_PATH)
	if templates.is_empty():
		_add_error("No mineral templates found in %s" % MINERAL_DATA_PATH)
	else:
		for path in templates:
			_validate_template(path, templates[path])

	# 2. Validate all gem visuals reference a template
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	if registry != null:
		var visual_ids: Array = registry.get_visual_ids()
		var tile_registry := get_root().get_node_or_null("TileRegistry")
		for vid in visual_ids:
			var visual: Resource = registry.get_visual(vid)
			if visual == null:
				continue
			# Check gameplay gems reference a template
			var is_gameplay: bool = (tile_registry == null or not tile_registry.has_definitions()
				or tile_registry.get_definition(vid) != null)
			var tmpl = visual.get("mineral_template")
			if is_gameplay and tmpl == null:
				_add_error("Gameplay gem '%s' has null mineral_template" % str(vid))
			# Check absorption_spectrum_override length
			var override_arr: PackedFloat32Array = visual.get("absorption_spectrum_override")
			if override_arr.size() != 0 and override_arr.size() != 81:
				_add_error("Gem '%s' absorption_spectrum_override has %d entries (expected 0 or 81)" % [
					str(vid), override_arr.size()])
	else:
		_add_warning("GemVisualRegistry not available; skipping gem reference checks")

	# 3. Published IOR comparison
	for path in templates:
		var tmpl: Resource = templates[path]
		var mid: StringName = tmpl.get("mineral_id")
		if PUBLISHED_IOR.has(mid):
			var computed := _sellmeier_ior(tmpl, 589.0)
			var published: float = PUBLISHED_IOR[mid]
			if absf(computed - published) > 0.002:
				_add_warning("%s: Sellmeier at 589nm gives %.4f, published is %.3f (deviation %.4f)" % [
					str(mid), computed, published, absf(computed - published)])
			else:
				_check_count += 1

	# Summary
	print("")
	if not _warnings.is_empty():
		print("Warnings (%d):" % _warnings.size())
		for w in _warnings:
			print("  WARN: %s" % w)
		print("")
	if _errors.is_empty():
		print("PASS: All %d checks passed, %d warnings." % [_check_count, _warnings.size()])
		quit(0)
	else:
		print("Errors (%d):" % _errors.size())
		for e in _errors:
			print("  ERROR: %s" % e)
		print("\nFAIL: %d errors, %d warnings." % [_errors.size(), _warnings.size()])
		quit(1)


func _validate_template(path: String, tmpl: Resource) -> void:
	var label := path.get_file()

	# Valid Sellmeier: 1.0 < n < 3.0
	var ior := _sellmeier_ior(tmpl, 589.0)
	if ior <= 1.0 or ior >= 3.0:
		_add_error("%s: Sellmeier at 589nm gives %.4f (must be in 1.0-3.0)" % [label, ior])
	else:
		_check_count += 1

	# Absorption spectrum sized correctly
	var absorption: PackedFloat32Array = tmpl.get("absorption_spectrum")
	if absorption.size() != 0 and absorption.size() != 81:
		_add_error("%s: absorption_spectrum has %d entries (expected 0 or 81)" % [label, absorption.size()])
	else:
		_check_count += 1

	# Non-negative absorption
	for i in absorption.size():
		if absorption[i] < 0.0:
			_add_error("%s: absorption_spectrum[%d] is negative (%.4f)" % [label, i, absorption[i]])
			break
	_check_count += 1


func _load_resources(dir_path: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var full_path := dir_path + file_name
			var resource := load(full_path)
			if resource != null:
				result[full_path] = resource
		file_name = dir.get_next()
	return result


func _sellmeier_ior(tmpl: Resource, lambda_nm: float) -> float:
	var b: Vector3 = tmpl.get("sellmeier_b")
	var c: Vector3 = tmpl.get("sellmeier_c")
	var l := lambda_nm * 0.001
	var l2 := l * l
	var n2 := 1.0 \
		+ b.x * l2 / (l2 - c.x) \
		+ b.y * l2 / (l2 - c.y) \
		+ b.z * l2 / (l2 - c.z)
	return sqrt(max(n2, 1.0))


func _add_error(msg: String) -> void:
	_errors.append(msg)


func _add_warning(msg: String) -> void:
	_warnings.append(msg)
