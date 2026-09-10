class_name GemWorkmanship
extends Resource
## Explicit bounded manufacturing deviations from the nominal facet program.
## These are authored tolerances, not a fracture model or certified cut grade.
@export var azimuth_error_deg := 0.0
@export var polar_error_deg := 0.0
@export var inward_offset_mm := 0.0
@export var girdle_inward_mm := 0.0
@export_multiline var source_note := "Authored tolerances; no measured manufacturing process."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["azimuth_error_deg", "polar_error_deg", "inward_offset_mm", "girdle_inward_mm"]:
		var value: float = get(key)
		var limit := 5.0 if key.ends_with("deg") else 1.0
		if not is_finite(value) or value < 0 or value > limit:
			errors.append("Workmanship %s must be finite and in [0, %s]" % [key, limit])
	return errors

func normalized_tolerances(size_mm: float) -> Vector4:
	return Vector4(azimuth_error_deg, polar_error_deg, inward_offset_mm / size_mm, girdle_inward_mm / size_mm)
