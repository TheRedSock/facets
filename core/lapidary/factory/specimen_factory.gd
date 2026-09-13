class_name GemSpecimenFactory
extends RefCounted
## Design-time realization: no light, camera, output resolution or style inputs.
## Grade labels select a preset; only realized physical inputs reach transport.
static func realize(recipe: GemSpecimenRecipe, preset_id: StringName, seed_value: int, source: GemStone = null) -> Dictionary:
	if recipe == null: return {"error": "Specimen recipe is missing"}
	var error := GemContentIdentity.graph_error(recipe)
	if not error.is_empty(): return {"error": error}
	if source != null:
		error = GemContentIdentity.graph_error(source)
		if not error.is_empty(): return {"error": error}
	error = recipe.validate()
	if not error.is_empty(): return {"error": error}
	if seed_value < 0 or seed_value > 2147483647: return {"error": "Specimen seed must be 0..2147483647"}
	var selected: GemQualityPreset = null
	for preset in recipe.presets:
		if preset.preset_id == preset_id: selected = preset; break
	if selected == null: return {"error": "Unknown quality preset: " + String(preset_id)}
	var base: GemStone = source if source != null else recipe.base
	if base.material == null or base.material.species == null: return {"error": "Base specimen needs a material species"}
	if not selected.allowed_species.is_empty() and base.material.species.species_id not in selected.allowed_species:
		return {"error": "Quality preset does not admit this material species"}
	var stone: GemStone = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.seed = seed_value
	stone.condition = selected.condition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if selected.cut_override != null:
		if stone.shape == null or stone.shape.mode != "faceted": return {"error": "A nominal cut override requires a faceted shape"}
		if not selected.cut_override is GemCutTemplate: return {"error": "Cut override must be a GemCutTemplate"}
		stone.cut = selected.cut_override.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.grade = selected.labels.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if stone.grade.grade_id == &"": stone.grade.grade_id = selected.preset_id
	var microstructure: GemMicrostructureRecipe = selected.microstructure.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if selected.microstructure != null else null
	var realized := {}
	var changed_scattering := false
	for variation in selected.variations:
		var q := quantile(seed_value, variation.channel_id)
		var value := exp(lerpf(log(variation.minimum), log(variation.maximum), q)) if variation.logarithmic else lerpf(variation.minimum, variation.maximum, q)
		var owner: Resource
		var property := variation.target.get_slice(".", 1)
		match variation.target.get_slice(".", 0):
			"cut":
				if stone.shape != null and stone.shape.mode == "faceted" and stone.cut is GemCutTemplate: owner = stone.cut
			"material": owner = stone.material
			"finish": owner = stone.condition.finish
			"rounding": owner = stone.condition.rounding
			"cleavage": owner = stone.condition.cleavage
			"workmanship": owner = stone.condition.workmanship
			"population":
				if microstructure != null:
					for population in microstructure.populations:
						if population.population_id == variation.population_id: owner = population; break
				value = minf(variation.maximum, variation.minimum + floorf(q * (variation.maximum - variation.minimum + 1)))
		if owner == null: return {"error": "Variation target was not explicitly authored: " + variation.target_key()}
		if variation.target.begins_with("material.") and owner.get(property) != value:
			changed_scattering = true
		owner.set(property, int(value) if variation.target == "population.count" else value)
		realized[variation.target_key()] = {"channel": String(variation.channel_id), "quantile": q, "value": value}
	if changed_scattering:
		stone.material.scattering_evidence = GemOpticalEvidence.derived(base.material.scattering_evidence, "Bounded specimen condition variation")
	error = GemJobValidator.specimen_error(stone)
	if not error.is_empty(): return {"error": "Realized condition rejected: " + error}
	var population_report := {}
	if microstructure != null:
		var populated := GemMicrostructureCompiler.realize(stone, microstructure)
		if not populated.error.is_empty(): return populated
		stone = populated.stone
		population_report = populated.report
		error = GemJobValidator.specimen_error(stone)
		if not error.is_empty(): return {"error": "Realized population rejected: " + error}
	var compiled := LapidaryStoneCompiler.compile(stone)
	if compiled.has("compilation_error"): return {"error": compiled.compilation_error}
	if not compiled.has("analytic_shape") and not compiled.has("rounded_solid"):
		var boundary: GemMesh = compiled.get("mesh", null)
		if boundary == null: boundary = GemShapeCompiler.from_hull(compiled.planes, compiled.get("facet_ids", PackedInt32Array()))
		var geometry_errors := boundary.validate()
		if not geometry_errors.is_empty(): return {"error": "Realized boundary rejected: " + "; ".join(geometry_errors)}
	var report := {"recipe_id": String(recipe.recipe_id), "preset_id": String(preset_id),
		"seed": seed_value, "source": base.fingerprint(), "recipe": GemContentIdentity.digest(recipe),
		"specimen": stone.fingerprint(), "realizer": FileAccess.get_sha256("res://core/lapidary/factory/specimen_factory.gd"),
		"parameters": realized, "microstructure": population_report, "geometry": compiled.get("condition_report", {}), "evidence": selected.source_note}
	# Portable provenance, explicitly excluded from optical/content identity.
	stone.set_meta("realization", report.duplicate(true))
	return {"error": "", "stone": stone, "report": report}

static func quantile(seed_value: int, channel: StringName) -> float:
	var channel_seed := GemContentIdentity.digest(["condition-variation-v1", seed_value, channel]).left(7).hex_to_int()
	return GemDefectCompiler.sample(channel_seed, 0)
