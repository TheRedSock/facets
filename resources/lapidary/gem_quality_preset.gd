class_name GemQualityPreset
extends Resource
## An authored condition state, not a universal gemological grading law.
## Replaces the base condition completely; physical parameters are inspectable.
@export var preset_id: StringName
@export var condition: GemCondition = GemCondition.new()
@export var labels: GemGrade = GemGrade.new()
## Optional complete nominal facet program. Null retains the source cut.
@export var cut_override: Resource
@export var microstructure: GemMicrostructureRecipe
@export var variations: Array[GemConditionVariation] = []
@export var allowed_species: Array[StringName] = []
@export_multiline var source_note := "Authored physical condition; no measured wear-history or clarity calibration."

func validate() -> String:
	if preset_id == &"" or condition == null or labels == null: return "Preset needs ID, explicit condition and labels"
	if source_note.strip_edges().is_empty(): return "Preset needs a provenance statement"
	if variations.size() > 64: return "At most 64 variation targets are supported"
	var targets := {}
	for variation in variations:
		if variation == null: return "Missing condition variation"
		var error := variation.validate()
		if not error.is_empty(): return error
		if targets.has(variation.target_key()): return "Duplicate variation target: " + variation.target_key()
		targets[variation.target_key()] = true
	if microstructure != null and not microstructure.validate().is_empty(): return "; ".join(microstructure.validate())
	return ""
