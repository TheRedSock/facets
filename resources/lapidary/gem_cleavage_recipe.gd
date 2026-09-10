class_name GemCleavageRecipe
extends Resource
## One plane-separation event, selected from declared Cartesian crystal-frame
## normals. These are NOT Miller indices for an arbitrary crystal lattice.
## Opposite normal signs select which outside cap is lost. No impact probability,
## hardness-to-damage conversion, or universal grade law is implied.
@export var normals := PackedVector3Array()
@export var depth_mm := 0.0
@export var seed := 1
@export var max_removed_fraction := 0.25
@export var finish: GemSurface = GemSurface.new()
@export_multiline var source_note := "Authored plane separation; no fracture dynamics prediction."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if normals.is_empty() or normals.size() > 64:
		errors.append("Cleavage needs 1..64 directed Cartesian plane normals")
	for i in normals.size():
		if not normals[i].is_finite() or absf(normals[i].length_squared()-1.0) > 1e-5:
			errors.append("Cleavage normals must be finite unit vectors")
		for j in i:
			if normals[i].distance_squared_to(normals[j]) < 1e-10:
				errors.append("Duplicate directed cleavage normal")
	if not is_finite(depth_mm) or depth_mm < 0 or depth_mm > 10000:
		errors.append("Cleavage depth must be finite and in 0..10000 mm")
	if not is_finite(max_removed_fraction) or max_removed_fraction <= 0 or max_removed_fraction >= 1:
		errors.append("Cleavage removal limit must be between zero and one")
	if finish != null:
		errors.append_array(finish.validate())
	return errors

func geometry_inputs() -> Dictionary:
	return {"normals":normals,"depth_mm":depth_mm,"seed":seed,"max_removed_fraction":max_removed_fraction}
