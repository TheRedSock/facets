class_name GemPolarization
extends RefCounted
## Mueller/Stokes reference mathematics. Matrices are row-major scalar float64.
## Stokes axes are perpendicular to physical light propagation, not camera rays.
## This module is not yet the GPU transport's polarization implementation.
## Convention and independent checks: Mitsuba 3.9.1 Mueller calculus (Verdet).

static func identity() -> PackedFloat64Array:
	return PackedFloat64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

static func rotation(angle: float) -> PackedFloat64Array:
	var result := identity()
	var c := cos(2.0 * angle)
	var s := sin(2.0 * angle)
	result[5] = c
	result[6] = s
	result[9] = -s
	result[10] = c
	return result

static func diattenuator(transmission_x: float, transmission_y: float) -> PackedFloat64Array:
	var a := (transmission_x + transmission_y) * 0.5
	var b := (transmission_x - transmission_y) * 0.5
	var c := sqrt(maxf(0.0, transmission_x * transmission_y))
	return PackedFloat64Array([a, b, 0, 0, b, a, 0, 0, 0, 0, c, 0, 0, 0, 0, c])

static func retarder(phase: float) -> PackedFloat64Array:
	var result := identity()
	result[10] = cos(phase)
	result[11] = sin(phase)
	result[14] = -sin(phase)
	result[15] = cos(phase)
	return result

## eta is incident/transmitted index. Angle is measured in the incident medium.
## Reflection basis on each side is perpendicular to its plane of incidence.
static func dielectric(cos_incident: float, eta: float, transmission := false) -> PackedFloat64Array:
	assert(eta > 0.0 and is_finite(eta))
	var ci := clampf(cos_incident, 0.0, 1.0)
	if absf(eta - 1.0) < 1e-12:
		return identity() if transmission else diattenuator(0, 0)
	var sin_transmitted_squared := eta * eta * (1.0 - ci * ci)
	if sin_transmitted_squared >= 1.0:
		if transmission:
			return diattenuator(0, 0)
		var imaginary_cosine := sqrt(sin_transmitted_squared - 1.0)
		var phase_s := -2.0 * atan2(imaginary_cosine, eta * ci)
		var phase_p := -2.0 * atan2(eta * imaginary_cosine, ci)
		# Complex Fresnel amplitudes retain the relative TIR phase.
		return retarder(phase_p - phase_s)
	var ct := sqrt(1.0 - sin_transmitted_squared)
	var rs := (eta * ci - ct) / (eta * ci + ct)
	var rp := (ci - eta * ct) / (ci + eta * ct)
	if transmission:
		return diattenuator(1.0 - rs * rs, 1.0 - rp * rp)
	var result := diattenuator(rs * rs, rp * rp)
	result[10] = rs * rp
	result[15] = rs * rp
	return result

static func multiply(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(16)
	for row in 4:
		for column in 4:
			for inner in 4:
				result[row * 4 + column] += a[row * 4 + inner] * b[inner * 4 + column]
	return result

static func apply(matrix: PackedFloat64Array, stokes: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array([0, 0, 0, 0])
	for row in 4:
		for column in 4:
			result[row] += matrix[row * 4 + column] * stokes[column]
	return result

static func basis_rotation(forward: Vector3, current: Vector3, target: Vector3) -> PackedFloat64Array:
	return rotation(atan2(forward.dot(current.cross(target)), current.dot(target)))

## Express a matrix in different incident/outgoing reference axes.
static func change_basis(matrix: PackedFloat64Array, incident: Vector3, in_current: Vector3,
		in_target: Vector3, outgoing: Vector3, out_current: Vector3, out_target: Vector3) -> PackedFloat64Array:
	return multiply(basis_rotation(outgoing, out_current, out_target),
		multiply(matrix, basis_rotation(incident, in_target, in_current)))
