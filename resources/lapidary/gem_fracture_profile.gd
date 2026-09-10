class_name GemFractureProfile
extends Resource
## Authored rough-surface aperture statistics, not fracture mechanics or a
## calibrated healing simulation. Zero-aperture contact patches remain host.
@export_range(8, 128) var resolution := 32
## Spatial correlation scale in the fracture's own x/y plane, in millimeters.
@export var correlation_mm := 0.25
## Fraction of the nominal opening modulated by the correlated aperture field.
@export_range(0.0, 1.0) var aperture_variation := 0.75
## Total closure of the two walls, in mm; removes locally closed void regions.
@export var closure_mm := 0.0
## Shared mid-surface height variation; both walls follow the same field.
@export var roughness_mm := 0.001
## Multiscale amplitude exponent. An authoring parameter, not a species constant.
@export_range(0.1, 1.0) var hurst := 0.8
@export_multiline var source_note := "Procedural correlated aperture/contact field; no mineral-specific calibration."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if resolution < 8 or resolution > 128:
		errors.append("Fracture grid resolution must be 8..128")
	if not is_finite(correlation_mm) or correlation_mm < 0.001 or correlation_mm > 10000:
		errors.append("Fracture correlation length must be 0.001..10000 mm")
	if not is_finite(aperture_variation) or aperture_variation < 0 or aperture_variation > 1:
		errors.append("Fracture aperture variation must be in [0,1]")
	if not is_finite(closure_mm) or closure_mm < 0 or closure_mm > 10 or not is_finite(roughness_mm) or roughness_mm < 0 or roughness_mm > 10:
		errors.append("Fracture closure and roughness must be finite and in [0,10] mm")
	if not is_finite(hurst) or hurst < 0.1 or hurst > 1:
		errors.append("Fracture roughness exponent must be in [0.1,1]")
	return errors
