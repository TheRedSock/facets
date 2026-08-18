extends SceneTree

## Generalized surface wear diagnostic matrix.
##
## Produces an A/B PNG matrix for any gem, isolating:
##   - base only (clean polished gem)
##   - cut quality (deoptimized pavilion / crown only)
##   - haze (structured haze only)
##   - inclusions (inclusion profile only)
##   - wear mask (analytic grayscale, denoise disabled)
##   - wear material only (frosted shading without haze / inclusions)
##   - dirt only (dirt patches only)
##   - combined raw (all systems, no stylizer)
##   - combined stylized (final output)
##
## Usage:
##   godot --headless --path . --script res://tools/run_wear_diagnostics.gd -- \
##       --gem=quartz --size=256 --samples_per_pixel=96 \
##       --output=res://debug/damage_bakes/diagnostics

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemBakeStylizerScript = preload("res://core/visuals/gem_bake_stylizer.gd")

const DEFAULT_OUTPUT_ROOT := "user://traced_bakes/wear_diagnostics"
const DEFAULT_SIZE := 256
const DEFAULT_SPP := 96
const DEFAULT_GEM := "quartz"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var args := _parse_args(OS.get_cmdline_user_args())
	var output_root := String(args.get("output", DEFAULT_OUTPUT_ROOT)).strip_edges()
	var size := maxi(int(args.get("size", DEFAULT_SIZE)), 32)
	var samples_per_pixel := clampi(int(args.get("samples_per_pixel", DEFAULT_SPP)), 16, 512)
	var seed := int(args.get("seed", 4242))
	var gem_id := String(args.get("gem", DEFAULT_GEM)).strip_edges()

	var visual_path := "res://data/visuals/%s.tres" % gem_id
	if not ResourceLoader.exists(visual_path):
		push_error("Wear diagnostics: visual resource not found: %s" % visual_path)
		quit(1)
		return
	var visual: GemVisualResource = load(visual_path)
	if visual == null:
		push_error("Wear diagnostics: failed to load %s" % visual_path)
		quit(1)
		return
	if not ClassDB.class_exists(&"GemTraceKernel"):
		push_error("Wear diagnostics requires the native GemTraceKernel extension")
		quit(1)
		return
	var tracer = ClassDB.instantiate(&"GemTraceKernel")
	if tracer == null:
		push_error("Wear diagnostics: could not instantiate GemTraceKernel")
		quit(1)
		return

	var matrix_root := _join_path(output_root, gem_id)
	_ensure_dir(matrix_root)

	var has_wear := visual.surface_damage_profile != null
	var has_haze := visual.volume_pattern_type == GemVisualResource.MATERIAL_PATTERN_STRUCTURED_HAZE \
		and visual.haze_base_density > 0.0
	var has_inclusions := visual.inclusion_profile != null

	var variants := [
		{
			"id": "base_only",
			"stylize": false,
			"cut_quality": 1.0,
			"wear": false, "wear_types": "",
			"haze": false, "inclusions": false,
			"debug_mask": false,
		},
		{
			"id": "cut_quality_only",
			"stylize": false,
			"cut_quality": visual.cut_quality,
			"wear": false, "wear_types": "",
			"haze": false, "inclusions": false,
			"debug_mask": false,
		},
		{
			"id": "haze_only",
			"stylize": false,
			"cut_quality": 1.0,
			"wear": false, "wear_types": "",
			"haze": has_haze, "inclusions": false,
			"debug_mask": false,
		},
		{
			"id": "inclusions_only",
			"stylize": false,
			"cut_quality": 1.0,
			"wear": false, "wear_types": "",
			"haze": false, "inclusions": has_inclusions,
			"debug_mask": false,
		},
		{
			"id": "wear_mask",
			"stylize": false,
			"cut_quality": 1.0,
			"wear": has_wear, "wear_types": "",
			"haze": false, "inclusions": false,
			"debug_mask": true,
		},
		{
			"id": "wear_material_only",
			"stylize": false,
			"cut_quality": 1.0,
			"wear": has_wear, "wear_types": "",
			"haze": false, "inclusions": false,
			"debug_mask": false,
		},
		{
			"id": "dirt_only",
			"stylize": false,
			"cut_quality": 1.0,
			"wear": has_wear, "wear_types": "dirt",
			"haze": false, "inclusions": false,
			"debug_mask": false,
		},
		{
			"id": "combined_raw",
			"stylize": false,
			"cut_quality": visual.cut_quality,
			"wear": has_wear, "wear_types": "",
			"haze": has_haze, "inclusions": has_inclusions,
			"debug_mask": false,
		},
		{
			"id": "combined_stylized",
			"stylize": true,
			"cut_quality": visual.cut_quality,
			"wear": has_wear, "wear_types": "",
			"haze": has_haze, "inclusions": has_inclusions,
			"debug_mask": false,
		},
	]

	var profiles := {}
	for variant in variants:
		var variant_visual := _build_variant_visual(visual, variant)
		var mesh = GemMeshGeneratorsScript.generate_from_visual(variant_visual)
		if mesh == null:
			push_error("Wear diagnostics: failed to build mesh for %s" % String(variant.id))
			quit(1)
			return
		# "wear_types" = "dirt" isolates dirt patches by dropping the other
		# wear entries after generation. Mirrors the per-type A/B isolation
		# you get via wear_material_only vs wear_mask.
		if variant.has("wear_types") and String(variant.wear_types) == "dirt":
			if typeof(mesh.get("surface_wear_entries")) == TYPE_ARRAY:
				var filtered: Array[Dictionary] = []
				for entry in mesh.surface_wear_entries:
					if typeof(entry) == TYPE_DICTIONARY and int(entry.get("type", 0)) == 3:
						filtered.append(entry)
				mesh.surface_wear_entries = filtered
				mesh._trace_data_cache.clear()
		var request := {
			"trace_size": Vector2i(size, size),
			"draw_size": Vector2i(size, size),
			"target_size": Vector2i(size, size),
			"samples_per_pixel": samples_per_pixel,
			"seed": seed,
			"trace_profile": true,
			"debug_surface_wear_mask": bool(variant.debug_mask),
		}
		var image: Image = tracer.trace_to_image(mesh, variant_visual, request)
		if image == null:
			push_error("Wear diagnostics: trace failed for %s" % String(variant.id))
			quit(1)
			return
		if bool(variant.stylize):
			image = GemBakeStylizerScript.apply(image, variant_visual, request)
		var png_path := _join_path(matrix_root, "%s.png" % String(variant.id))
		var err := image.save_png(png_path)
		if err != OK:
			push_error("Wear diagnostics: failed to save %s (error %d)" % [png_path, err])
			quit(1)
			return
		profiles[String(variant.id)] = tracer.get_last_trace_profile()
		print("Saved %s" % ProjectSettings.globalize_path(png_path))

	var profile_path := _join_path(matrix_root, "trace_profiles.json")
	var profile_file := FileAccess.open(profile_path, FileAccess.WRITE)
	if profile_file != null:
		profile_file.store_string(JSON.stringify(profiles, "\t"))
	print("Wear diagnostic matrix complete: %s" % ProjectSettings.globalize_path(matrix_root))
	quit(0)


func _build_variant_visual(source: GemVisualResource, variant: Dictionary) -> GemVisualResource:
	var visual: GemVisualResource = source.duplicate(true)
	visual.cut_quality = float(variant.cut_quality)
	if not bool(variant.wear):
		visual.surface_damage_profile = null
		visual.damage_diffuse_albedo = 0.0
	if not bool(variant.haze):
		if visual.volume_pattern_type == GemVisualResource.MATERIAL_PATTERN_STRUCTURED_HAZE:
			visual.volume_pattern_type = GemVisualResource.MATERIAL_PATTERN_NONE
			visual.haze_base_density = 0.0
		visual.volume_pattern_mix = 0.0
		visual.scattering_coefficient_override = 0.0
		visual.volume_scattering_variation = 0.0
	if variant.has("inclusions") and not bool(variant.inclusions):
		visual.inclusion_profile = null
	return visual


func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _join_path(base: String, tail: String) -> String:
	return "%s%s" % [base, tail] if base.ends_with("/") else "%s/%s" % [base, tail]


func _parse_args(raw_args: PackedStringArray) -> Dictionary:
	var result := {}
	for arg in raw_args:
		if not arg.begins_with("--"):
			continue
		var trimmed := arg.substr(2)
		var eq := trimmed.find("=")
		if eq == -1:
			result[trimmed] = true
		else:
			result[trimmed.substr(0, eq)] = trimmed.substr(eq + 1)
	return result
