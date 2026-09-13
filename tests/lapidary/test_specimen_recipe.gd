extends SceneTree
class SharedGraph extends Resource:
	@export var left: Resource
	@export var right: Resource
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	var recipe: GemSpecimenRecipe = load("res://data/lapidary/recipes/quartz_condition_study.tres")
	check(recipe.validate().is_empty(), "authored recipe validates")
	var original := GemContentIdentity.digest(recipe)
	var results := {}
	for preset in recipe.presets:
		var result := GemSpecimenFactory.realize(recipe, preset.preset_id, 17)
		check(result.error.is_empty(), "realize " + String(preset.preset_id))
		if not result.error.is_empty(): continue
		results[preset.preset_id] = result
		check(result.stone.fingerprint() == GemSpecimenFactory.realize(recipe, preset.preset_id, 17).stone.fingerprint(), "repeat specimen is exact")
		check(GemJobValidator.specimen_error(result.stone).is_empty(), "realized geometry/material admission")
		check(result.stone.seed == 17 and result.stone.grade.grade_id == preset.preset_id, "explicit seed and selection label")
	check(GemContentIdentity.digest(recipe) == original, "authoring graph remains immutable")
	if results.size() != 5: print("CHECK_COMPLETE: test_specimen_recipe"); quit(1); return
	var reference: GemStone = results[&"reference"].stone
	var softened: GemStone = results[&"softened_polish"].stone
	var cut: GemStone = results[&"cut_tolerance"].stone
	var cloud: GemStone = results[&"cloud"].stone
	var crystals: GemStone = results[&"foreign_crystals"].stone
	check(reference.material.scatter_per_mm == 0 and reference.condition.banding.contrast == 0, "preset replaces base condition and explicitly clears bulk scatter")
	check(softened.condition.rounding.radius_mm >= 0.04 and softened.condition.rounding.radius_mm <= 0.08, "physical radius bounds")
	check(absf(softened.condition.finish.alpha_u / softened.condition.finish.alpha_v - 2) < 1e-12, "shared channel preserves prescribed anisotropy ratio")
	check(softened.condition.workmanship.polar_error_deg == 0 and softened.condition.volume_fields.is_empty(), "surface preset does not add cut errors or haze")
	check(cut.condition.workmanship.polar_error_deg >= 0.08 and cut.condition.finish.alpha_u == 0 and cut.condition.defects.is_empty(), "cut variation remains its own axis")
	check(cloud.condition.volume_fields.size() == 1 and cloud.condition.finish.alpha_u == 0 and cloud.condition.defects.is_empty(), "cloud remains a physical field, not visible primitive marks")
	check(crystals.condition.defects.size() >= 4 and crystals.condition.defects.size() <= 8 and crystals.material.scatter_per_mm == 0, "bounded explicit crystal count without duplicate haze")
	var reordered: GemSpecimenRecipe = recipe.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	reordered.presets.reverse()
	for preset in reordered.presets: preset.variations.reverse()
	check(GemSpecimenFactory.realize(reordered, &"softened_polish", 17).stone.fingerprint() == softened.fingerprint(), "preset and target ordering do not alter realization")
	var relabeled: GemSpecimenRecipe = recipe.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	relabeled.presets[1].labels.surface = 0.1
	var renamed := GemSpecimenFactory.realize(relabeled, &"softened_polish", 17)
	check(GemContentIdentity.digest(renamed.stone.transport_inputs()) == GemContentIdentity.digest(softened.transport_inputs()), "labels do not become hidden physical parameters")
	var additional := GemConditionVariation.new()
	additional.channel_id = &"other_process"; additional.target = "workmanship.polar_error_deg"; additional.minimum = 0.01; additional.maximum = 0.02
	relabeled.presets[1].variations.append(additional)
	var extended := GemSpecimenFactory.realize(relabeled, &"softened_polish", 17)
	check(extended.stone.condition.rounding.radius_mm == softened.condition.rounding.radius_mm and extended.stone.condition.finish.alpha_u == softened.condition.finish.alpha_u, "unrelated channel insertion preserves existing physical draws")
	check(GemSpecimenFactory.realize(recipe, &"softened_polish", 18).stone.condition.rounding.radius_mm != softened.condition.rounding.radius_mm, "new specimen seed varies realized condition")
	var larger: GemStone = recipe.base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	larger.size_mm *= 2
	var scaled := GemSpecimenFactory.realize(recipe, &"softened_polish", 17, larger)
	check(scaled.error.is_empty() and scaled.stone.condition.rounding.radius_mm == softened.condition.rounding.radius_mm, "source size changes do not silently rescale physical wear")
	var recut: GemStone = recipe.base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	recut.shape.outline = &"oval"; recut.shape.aspect_ratio = 1.4
	var alternate := GemSpecimenFactory.realize(recipe, &"foreign_crystals", 17, recut)
	check(alternate.error.is_empty(), "same population can be recut")
	if alternate.error.is_empty():
		for i in crystals.condition.defects.size():
			check(GemContentIdentity.digest(alternate.stone.condition.defects[i]) == GemContentIdentity.digest(crystals.condition.defects[i]), "recut keeps physical inclusions")
	var output := "res://artifacts/specimen-recipe/%d.res" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	check(GemResourceBundle.save(softened, output) == OK, "save explicit binary specimen")
	var restored: GemStone = load(output)
	check(restored.fingerprint() == softened.fingerprint(), "binary serialization retains exact realization")
	check(restored.get_meta("realization", {}) == results[&"softened_polish"].report, "realization provenance survives portable binary resources")
	check(not GemSpecimenFactory.realize(recipe, &"missing", 1).has("stone"), "unknown quality has no partial output")
	check(not GemSpecimenFactory.realize(recipe, &"reference", -1).has("stone"), "invalid seed has no partial output")
	check(not GemSpecimenFactory.realize(recipe, &"reference", 1, load("res://data/lapidary/stones/diamond.tres")).has("stone"), "species restriction rejects unsafe template reuse")
	var broken: GemSpecimenRecipe = recipe.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.presets[1].condition.rounding = null
	check(not GemSpecimenFactory.realize(broken, &"softened_polish", 1).has("stone"), "missing physical target is not silently created")
	broken = recipe.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.presets[1].variations.append(broken.presets[1].variations[0])
	check(not broken.validate().is_empty(), "ambiguous duplicate writes rejected")
	var variation := GemConditionVariation.new(); variation.channel_id = &"probe"
	variation.minimum = NAN
	check(not variation.validate().is_empty(), "nonfinite variation rejected")
	variation.minimum = 0; variation.logarithmic = true
	check(not variation.validate().is_empty(), "zero logarithmic bound rejected")
	variation.logarithmic = false; variation.target = "script.source_code"
	check(not variation.validate().is_empty(), "arbitrary property access rejected")
	variation.target = "cut.parameters.table"
	check(not variation.validate().is_empty(), "condition variation cannot rewrite the nominal facet program")
	variation.target = "material.scatter_g"; variation.minimum = -0.99; variation.maximum = 0.99
	check(variation.validate().is_empty(), "exact declared decimal endpoints are admitted")
	var alternate_cut: GemSpecimenRecipe = recipe.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	alternate_cut.presets[0].cut_override = recipe.base.cut.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	alternate_cut.presets[0].cut_override.parameters.table = 0.64
	var new_design := GemSpecimenFactory.realize(alternate_cut, &"reference", 17)
	check(new_design.error.is_empty() and new_design.stone.cut.parameters.table == 0.64 and recipe.base.cut.parameters.table != 0.64, "preset may select an explicit independent nominal cut")
	var mutated: GemStone = softened.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	check(GemJobValidator.specimen_error(mutated).is_empty(), "detached identical physical content admitted")
	mutated.condition.finish.alpha_u = -0.1
	check(not GemJobValidator.specimen_error(mutated).is_empty(), "cached admission detects physical edits")
	mutated.condition.finish.alpha_u = softened.condition.finish.alpha_u
	mutated.grade.surface = NAN
	check(not GemJobValidator.specimen_error(mutated).is_empty(), "cached admission still validates nonphysical grade ranges")
	check(not GemJobValidator.specimen_error(reference, true).is_empty(), "scalar admission cannot bypass polarized capability checks")
	for i in GemJobValidator.SPECIMEN_CACHE_LIMIT + 1:
		var varied: GemStone = reference.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		varied.grade.grade_id = StringName("cache-fixture-%d" % i)
		check(GemJobValidator.specimen_error(varied).is_empty(), "admit bounded-cache fixture")
	check(GemJobValidator._specimen_cache.size() <= GemJobValidator.SPECIMEN_CACHE_LIMIT and GemJobValidator._specimen_order.size() == GemJobValidator._specimen_cache.size(), "admission cache has bounded ownership")
	var measured: GemStone = recipe.base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	measured.material.scattering_evidence.kind = GemOpticalEvidence.Kind.SUPPLIED_MEASUREMENT
	measured.material.scattering_evidence.citation = "Synthetic test fixture for evidence handling"
	measured.material.scattering_evidence.dataset_sha256 = "a".repeat(64)
	measured.material.scattering_evidence.method = "Synthetic fixture"
	var changed := GemSpecimenFactory.realize(recipe, &"reference", 17, measured)
	check(changed.error.is_empty(), "realize variation from measured-evidence fixture")
	if changed.error.is_empty():
		check(changed.stone.material.scattering_evidence.kind == GemOpticalEvidence.Kind.AUTHORED_APPROXIMATION, "varied measurement becomes explicitly authored evidence")
		check(changed.stone.material.scattering_evidence.source_record.parent_evidence == GemContentIdentity.digest(measured.material.scattering_evidence), "varied evidence retains parent identity")
	check(measured.material.scattering_evidence.kind == GemOpticalEvidence.Kind.SUPPLIED_MEASUREMENT, "source measurement evidence remains unchanged")
	var cyclic: GemStone = reference.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	cyclic.cut = cyclic
	check(GemJobValidator.specimen_error(cyclic).contains("Cyclic"), "cache preflight rejects cyclic input before content hashing")
	check(GemSpecimenFactory.realize(recipe, &"reference", 17, cyclic).error.contains("Cyclic"), "realizer rejects cyclic source before deep duplication")
	var cyclic_recipe: GemSpecimenRecipe = recipe.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	cyclic_recipe.presets[0].cut_override = cyclic_recipe
	check(GemSpecimenFactory.realize(cyclic_recipe, &"reference", 17).error.contains("Cyclic"), "realizer rejects cyclic preset before hashing provenance")
	cyclic_recipe.presets[0].cut_override = null
	cyclic.cut = null
	var shared := [reference, reference]
	check(GemContentIdentity.graph_error(shared).is_empty(), "shared resources are not mistaken for cycles")
	var nested: Array = []
	nested.append(nested)
	check(not GemContentIdentity.graph_error(nested).is_empty(), "recursive containers stop at the traversal bound")
	nested.clear()
	var expanded := SharedGraph.new()
	for i in 18:
		var parent := SharedGraph.new()
		parent.left = expanded; parent.right = expanded
		expanded = parent
	check(not GemContentIdentity.graph_error(expanded).is_empty(), "shared DAG expansion is bounded before canonical serialization")
	print("Specimen recipe: %d checks, %d failures" % [checks, failures]); print("CHECK_COMPLETE: test_specimen_recipe"); quit(1 if failures else 0)
