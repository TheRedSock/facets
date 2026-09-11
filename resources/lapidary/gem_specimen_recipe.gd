class_name GemSpecimenRecipe
extends Resource
## Material/shape/cut template plus named quality states. Realization produces
## an ordinary GemStone; workers never interpret this authoring program.
@export var recipe_id: StringName
@export var base: GemStone
@export var presets: Array[GemQualityPreset] = []
@export_multiline var source_note := "Authored specimen family."

func validate() -> String:
	if recipe_id == &"" or base == null or presets.is_empty() or presets.size() > 64:
		return "Recipe needs an ID, base specimen and 1..64 presets"
	var ids := {}
	for preset in presets:
		if preset == null: return "Missing quality preset"
		var error := preset.validate()
		if not error.is_empty(): return error
		if ids.has(preset.preset_id): return "Duplicate quality preset ID"
		ids[preset.preset_id] = true
	return ""
