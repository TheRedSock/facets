class_name GemFinishField
extends Resource
## Authored region of local boundary finish, not an inclusion or painted mark.
## Smooth compact support in physical millimeters. Ordered fields interpolate
## the GGX slope-shape matrix, not variance (GGX variance is unbounded), nor a
## mixture of separate BSDFs. No material-removal or polishing-rate law is implied.
@export var center_mm := Vector3.ZERO
@export var radius_mm := Vector3.ONE
@export var orientation := Quaternion.IDENTITY
@export_range(0.0, 1.0) var strength := 1.0
@export_range(0.0, 1.0) var alpha_u := 0.0
@export_range(0.0, 1.0) var alpha_v := 0.0
@export var direction := Vector3.RIGHT
@export_multiline var source_note := "Authored local finish; not a measured process or wear history."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not center_mm.is_finite() or center_mm.length() > 100000.0 or not radius_mm.is_finite() or minf(radius_mm.x, minf(radius_mm.y, radius_mm.z)) < 0.001 or maxf(radius_mm.x, maxf(radius_mm.y, radius_mm.z)) > 10000.0:
		errors.append("Finish field needs finite coordinates and radii in [0.001,10000] mm")
	if not orientation.is_finite() or absf(orientation.length_squared()-1.0) > 0.00001:
		errors.append("Finish field orientation must be a unit quaternion")
	for value in [strength, alpha_u, alpha_v]:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("Finish field strength and slope widths must be in [0,1]")
	if not direction.is_finite() or direction.length_squared() < 1e-12:
		errors.append("Finish field polish direction must be finite and nonzero")
	return errors

func weight(point_mm: Vector3) -> float:
	var local := (orientation.inverse() * (point_mm-center_mm)) / radius_mm
	var density := maxf(0.0, 1.0-local.length_squared())
	return strength*density*density*density

func packed() -> PackedFloat32Array:
	assert(validate().is_empty(), str(validate()))
	var axis := direction.normalized()
	return PackedFloat32Array([center_mm.x, center_mm.y, center_mm.z, strength,
		radius_mm.x, radius_mm.y, radius_mm.z, 0,
		orientation.x, orientation.y, orientation.z, orientation.w,
		alpha_u, alpha_v, 0, 0, axis.x, axis.y, axis.z, 0])
