extends SceneTree
## Public schema/tool admission after removal of inert authoring properties.
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + label)

func _init() -> void:
	var material := GemMaterial.new()
	material.species = load("res://data/lapidary/species/quartz.tres")
	check(material.validate().is_empty() and GemMaterialCompiler.compile(material).scatter.sigma_per_mm == 0.0, "new material scattering is explicit zero")
	material.scatter_per_mm = -1.0
	check(not material.validate().is_empty(), "negative scattering does not inherit a hidden species value")
	var request := GemAssetRequest.new()
	request.asset_id = &"contract_probe"
	request.stone = load("res://data/lapidary/stones/quartz.tres")
	request.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	request.print_style = GemPrint.load_house()
	request.clips = [load("res://data/lapidary/clips/idle.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)]
	request.clips[0].orientation_keys.clear()
	var batch := GemAssetBatch.new(); batch.requests = [request]
	check(not GemAssetPlanner.plan(batch).error.is_empty(), "empty orientation track is rejected")
	request.clips[0].orientation_keys = [GemOrientationKey.new()]
	request.clips[0].effect_envelopes["unknown_effect"] = Curve.new()
	check(not GemAssetPlanner.plan(batch).error.is_empty(), "unknown effect is rejected")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/engine_checks.json"))
	var names := {}
	for stage in registry.stages:
		check(not names.has(stage.name) and not String(stage.completion).is_empty(), "unique named check with completion")
		names[stage.name] = true
		for argument: String in stage.args:
			if argument.begins_with("res://"):
				check(FileAccess.file_exists(argument), "registered entry point exists: " + argument)
	print("Authoring surface: %d failures" % failures)
	print("CHECK_COMPLETE: test_authoring_surface"); quit(1 if failures else 0)
