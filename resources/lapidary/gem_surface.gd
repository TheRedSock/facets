class_name GemSurface
extends Resource
## Physical boundary finish, independent of bulk absorption and geometry.
## GGX alpha values describe the slope distribution, not a perceptual slider.
## The current single-scattering model is intended for polished surfaces;
## strong frosting needs multiple microfacet scattering before grade automation.
@export_range(0.0, 1.0) var alpha_u := 0.0
@export_range(0.0, 1.0) var alpha_v := 0.0
## Object-space polish direction, projected into each boundary's tangent plane.
@export var direction := Vector3.RIGHT
@export_multiline var source_note := "Authored finish; not a measured roughness distribution."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(alpha_u) or not is_finite(alpha_v) or alpha_u < 0.0 or alpha_v < 0.0 or alpha_u > 1.0 or alpha_v > 1.0:
		errors.append("GGX slope widths must be finite and between zero and one")
	if not direction.is_finite() or direction.length_squared() < 1e-12:
		errors.append("Polish direction must be finite and nonzero")
	return errors

func packed() -> PackedFloat32Array:
	assert(validate().is_empty(), "Invalid boundary finish: %s" % validate())
	var axis := direction.normalized()
	return PackedFloat32Array([alpha_u, alpha_v, 0, 0, axis.x, axis.y, axis.z, 0])
