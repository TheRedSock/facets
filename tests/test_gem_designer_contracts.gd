extends SceneTree
## Headless checks for gem designer JSON / session contracts (no UI).

const GemVisualResourceScript = preload("res://resources/visuals/gem_visual_resource.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const ProductionBakeProfileScript = preload("res://tools/production_bake_profile.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var errs: Array[String] = []
	errs.append_array(_test_visual_json_paths_and_override())
	errs.append_array(_test_zone_spectrum_json_roundtrip())
	errs.append_array(_test_mineral_json_roundtrip())
	errs.append_array(_test_cut_export_schema_stable_signature())
	errs.append_array(_test_preview_enrich_parity_keys())
	if not errs.is_empty():
		for e in errs:
			push_error(e)
		quit(1)
	else:
		quit(0)


func _test_visual_json_paths_and_override() -> Array[String]:
	var out: Array[String] = []
	var vis: GemVisualResource = GemVisualResourceScript.new()
	vis.visual_id = &"test_contract"
	var mt_path := "res://data/minerals/painite.tres"
	var mt = load(mt_path)
	if mt == null:
		out.append("Could not load mineral for test")
		return out
	vis.mineral_template = mt
	var env = load("res://data/environments/neutral_warm_reference.tres")
	if env:
		vis.bake_environment = env
	var ov := PackedFloat32Array()
	ov.resize(81)
	ov.fill(0.1)
	vis.absorption_spectrum_override = ov
	var d := vis.build_visual_json_dict()
	if int(d.get("visual_json_schema_version", 0)) <= 0:
		out.append("visual_json_schema_version missing")
	if String(d.get("mineral_template_path", "")) != mt_path:
		out.append("mineral_template_path not serialized")
	var arr = d.get("absorption_spectrum_override", null)
	if typeof(arr) != TYPE_ARRAY or (arr as Array).size() != 81:
		out.append("absorption_spectrum_override JSON shape")
	var vis2: GemVisualResource = GemVisualResourceScript.new()
	vis2.apply_visual_json_dict(d)
	if vis2.absorption_spectrum_override.size() != 81:
		out.append("absorption round-trip size")
	return out


func _test_zone_spectrum_json_roundtrip() -> Array[String]:
	var out: Array[String] = []
	var vis: GemVisualResource = GemVisualResourceScript.new()
	var z := PackedFloat32Array()
	z.resize(81)
	z.fill(0.05)
	vis.gradient_zone_spectrum = z
	var p := PackedFloat32Array()
	p.resize(81)
	p.fill(0.02)
	vis.phenomenon_zone_spectrum = p
	var d := vis.build_visual_json_dict()
	var vis2: GemVisualResource = GemVisualResourceScript.new()
	vis2.apply_visual_json_dict(d)
	if vis2.gradient_zone_spectrum.size() != 81:
		out.append("gradient_zone_spectrum round-trip size")
	if vis2.phenomenon_zone_spectrum.size() != 81:
		out.append("phenomenon_zone_spectrum round-trip size")
	var c := GemVisualResource.zone_spectrum_to_display_color(z)
	if c.r < 0.0 or c.g < 0.0 or c.b < 0.0:
		out.append("zone_spectrum_to_display_color range")
	return out


func _test_mineral_json_roundtrip() -> Array[String]:
	var out: Array[String] = []
	var mt := GemMineralTemplate.new()
	mt.mineral_id = &"test"
	var s := PackedFloat32Array()
	s.resize(81)
	s.fill(0.02)
	mt.absorption_spectrum = s
	var d := mt.build_mineral_json_dict()
	var mt2 := GemMineralTemplate.new()
	mt2.apply_mineral_json_dict(d)
	if mt2.absorption_spectrum.size() != 81:
		out.append("mineral absorption round-trip")
	return out


func _test_cut_export_schema_stable_signature() -> Array[String]:
	var out: Array[String] = []
	var session := GemDesignSession.new()
	if not session.load_from_visual_path("res://data/visuals/ruby.tres"):
		out.append("cut sig test: load ruby visual")
		return out
	if session.working_cut_spec == null:
		out.append("cut sig test: no working cut")
		return out
	var spec_id_before := session.working_cut_spec.spec_id
	var export_dict := session.build_cut_json_export_dict()
	if int(export_dict.get("cut_json_schema_version", 0)) <= 0:
		out.append("cut_json_schema_version missing")
	## Match the Cut JSON tab: text round-trip through JSON (float coercion).
	var text := JSON.stringify(export_dict)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		out.append("cut JSON text round-trip parse")
		return out
	session.apply_cut_json_export_dict(parsed)
	if session.working_cut_spec.spec_id != spec_id_before:
		out.append("cut spec_id changed after JSON round-trip")
	return out


func _test_preview_enrich_parity_keys() -> Array[String]:
	var out: Array[String] = []
	var registry = get_root().get_node_or_null("GemVisualRegistry")
	if registry == null:
		return out
	var session := GemDesignSession.new()
	if not session.load_from_visual_path("res://data/visuals/ruby.tres"):
		out.append("parity: could not load ruby visual")
		return out
	session.compile_geometry(true)
	var model = session.get_cached_model()
	var cut = session.get_cached_projected_cut()
	var vis: GemVisualResource = session.working_visual
	var mesh = session.get_cached_mesh()
	if model == null or cut == null or vis == null or mesh == null:
		out.append("parity: geometry compile failed")
		return out
	var prof: Dictionary = ProductionBakeProfileScript.load_profile_file(
		"res://config/bake_profiles/gameplay.json"
	)
	var bake_opts: Dictionary = ProductionBakeProfileScript.profile_to_bake_options(
		prof, "res://config/bake_profiles/gameplay.json"
	)
	var variant_opts: Dictionary = GemTracedBakeContractScript.build_manifest_variant_settings(bake_opts)
	var base_req: Dictionary = registry.build_designer_preview_crown_request(
		&"parity_tile",
		vis,
		model,
		cut,
		Vector2i(64, 64),
		Vector2i(64, 64),
		variant_opts,
		64
	)
	var enrich_opts := {"skip_stylize": true, "samples_per_pixel": 64}
	var job := OfflineGemBakeJobScript.new()
	var enriched: Dictionary = job.build_designer_enriched_request(
		base_req,
		vis,
		mesh,
		1,
		enrich_opts
	)
	for k in [&"light_dir", &"environment_profile", &"mesh_resource", &"samples_per_pixel", &"visual"]:
		if not enriched.has(k):
			out.append("parity: enriched request missing %s" % String(k))
	return out
