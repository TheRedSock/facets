class_name GemBanding
extends Resource
## An authored sinusoidal concentration field in specimen coordinates.
## c(x)=1+contrast*sin(2*pi*dot(axis,x_mm)/period_mm+phase_radians).
## This is a transport approximation, not a crystal-growth or sector-zoning model.
@export var axis := Vector3.BACK
@export var period_mm := 1.0
@export_range(0.0, 1.0) var contrast := 0.0
@export var phase_radians := 0.0
@export var evidence: GemOpticalEvidence = GemOpticalEvidence.new()

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not axis.is_finite() or axis.length_squared() < 1e-12:
		errors.append("Banding needs a finite nonzero specimen-space axis")
	if not is_finite(period_mm) or period_mm < 0.001 or period_mm > 10000:
		errors.append("Banding period must be 0.001..10000 mm")
	if not is_finite(contrast) or contrast < 0 or contrast > 1 or not is_finite(phase_radians):
		errors.append("Banding needs contrast in [0,1] and finite phase")
	if evidence == null:
		errors.append("Banding evidence descriptor is missing")
	else:
		errors.append_array(evidence.validate())
	return errors

func normalized(size_mm: float) -> Dictionary:
	return {"axis": axis.normalized(), "frequency": 2.0 * size_mm / period_mm,
		"contrast": contrast, "phase": fposmod(phase_radians, TAU)}
