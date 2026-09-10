class_name GemIndexCurve
extends Resource
## One principal real refractive-index spectrum. Coefficients remain float64
## while authoring and in the Maxwell reference; GPU packing is explicit.
## n(lambda) = sqrt(1 + sum B_i lambda^2/(lambda^2-C_i)) + index_offset.
## lambda is micrometers; a C=0 term represents an additive n^2 constant.
@export var b := PackedFloat64Array([0.0, 0.0, 0.0])
@export var c_um2 := PackedFloat64Array([0.0, 0.0, 0.0])
## An explicit empirical approximation, never inferred from another axis.
@export var index_offset := 0.0
@export var range_nm := Vector2(380.0, 780.0)
@export var evidence: GemOpticalEvidence = GemOpticalEvidence.new()

func at(wavelength_nm: float) -> float:
	if b.size() != 3 or c_um2.size() != 3 or not is_finite(wavelength_nm) or wavelength_nm < range_nm.x or wavelength_nm > range_nm.y:
		return NAN
	return _evaluate(b, c_um2, index_offset, wavelength_nm)

static func _evaluate(coeff_b, coeff_c, offset: float, wavelength_nm: float) -> float:
	var l2 := pow(wavelength_nm * 0.001, 2)
	var n2 := 1.0
	for term in 3:
		if coeff_b[term] == 0.0:
			continue
		var denominator: float = l2 - coeff_c[term]
		if absf(denominator) < 1e-12:
			return NAN
		n2 += coeff_b[term] * l2 / denominator
	return sqrt(n2) + offset if n2 > 0.0 else NAN

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if b.size() != 3 or c_um2.size() != 3:
		errors.append("Index curve requires three B and C coefficients")
		return errors
	if not range_nm.is_finite() or range_nm.x > 380.0 or range_nm.y < 780.0 or range_nm.x <= 0:
		errors.append("Index curve does not cover the transport interval")
	if not is_finite(index_offset):
		errors.append("Index offset must be finite")
	for term in 3:
		if not is_finite(b[term]) or not is_finite(c_um2[term]) or absf(b[term]) > 1e30 or absf(c_um2[term]) > 1e30:
			errors.append("Index coefficients exceed finite GPU precision")
		if b[term] != 0.0 and c_um2[term] >= 0.38 * 0.38 and c_um2[term] <= 0.78 * 0.78:
			errors.append("Index curve pole lies inside the transport interval")
	var wire_b := PackedFloat32Array([b[0], b[1], b[2]])
	var wire_c := PackedFloat32Array([c_um2[0], c_um2[1], c_um2[2]])
	var wire_offset := PackedFloat32Array([index_offset])[0]
	for wavelength in range(380, 781):
		var n := at(wavelength)
		if not is_finite(n) or n < 1.0 or n > 100.0:
			errors.append("Invalid visible dielectric index (supported range 1..100)")
			break
		# This bounds coefficient quantization, not every GPU arithmetic error
		# or sub-nanometer resonance. Reject ill-conditioned authored curves.
		var gpu_input_n := _evaluate(wire_b, wire_c, wire_offset, wavelength)
		if not is_finite(gpu_input_n) or absf(n - gpu_input_n) > 1e-6:
			errors.append("Index curve exceeds the float32 coefficient error budget (1e-6)")
			break
	if evidence == null:
		errors.append("Index evidence descriptor is missing")
	else:
		errors.append_array(evidence.validate())
	return errors

func packed() -> Dictionary:
	return {"b": Vector3(b[0], b[1], b[2]), "c": Vector3(c_um2[0], c_um2[1], c_um2[2]), "offset": index_offset}
