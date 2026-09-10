class_name GemSurface
extends Resource
## Physical boundary finish, independent of bulk absorption and geometry.
## GGX alpha values describe the slope distribution, not a perceptual slider.
## Single scattering is intended for polished surfaces. The explicit Smith walk
## includes higher orders; appearance calibration is still needed for grading.
@export_range(0.0, 1.0) var alpha_u := 0.0
@export_range(0.0, 1.0) var alpha_v := 0.0
## Experimental height-correlated Smith random walk, including inter-facet
## reflection/refraction. More expensive/noisy; never selected by grade labels.
@export var multiple_scattering := false
## Object-space polish direction, projected into each boundary's tangent plane.
@export var direction := Vector3.RIGHT
## Ordered local overrides. A field with zero target slopes can repolish a
## rough base; a nonzero field can describe a locally unfinished surface.
@export var fields: Array[GemFinishField] = []
@export_multiline var source_note := "Authored finish; not a measured roughness distribution."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(alpha_u) or not is_finite(alpha_v) or alpha_u < 0.0 or alpha_v < 0.0 or alpha_u > 1.0 or alpha_v > 1.0:
		errors.append("GGX slope widths must be finite and between zero and one")
	if not direction.is_finite() or direction.length_squared() < 1e-12:
		errors.append("Polish direction must be finite and nonzero")
	if fields.size() > 16:
		errors.append("At most 16 finish fields are supported per boundary")
	for field in fields:
		if field == null:
			errors.append("Finish field is missing")
		else:
			errors.append_array(field.validate())
	return errors

func has_roughness() -> bool:
	if maxf(alpha_u, alpha_v) >= 0.0001:
		return true
	for field in fields:
		if field != null and field.strength > 0.0 and maxf(field.alpha_u, field.alpha_v) >= 0.0001:
			return true
	return false

func packed(field_offset := 0) -> PackedFloat32Array:
	assert(validate().is_empty(), "Invalid boundary finish: %s" % validate())
	var axis := direction.normalized()
	return PackedFloat32Array([alpha_u, alpha_v, 1 if multiple_scattering else 0, field_offset, axis.x, axis.y, axis.z, fields.size()])
