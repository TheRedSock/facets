class_name GemCrystalInterface
extends RefCounted
## Lossless smooth uniaxial interface. Solve tangential E/H continuity for
## two reflected and two transmitted complex field amplitudes. This is a
## forward flux operator, not yet an adjoint rendering BSDF.
## Maxwell boundary construction follows the tangential continuity conditions
## discussed by Thomson et al. (2009), https://arxiv.org/abs/0901.2558 .
const V := preload("res://core/lapidary/crystal_modes.gd")

static func scatter(source: Dictionary, target: Dictionary, normal: PackedFloat64Array, incident: Dictionary) -> Dictionary:
	var n := V.unit(normal)
	var incident_flux := V.dot(incident.poynting, n)
	if incident.evanescent or incident_flux <= 1e-12:
		return {"error": "Incident mode must carry energy toward the interface"}
	var tangent := V.subtract(incident.k_real, V.scale(n, V.dot(incident.k_real, n)))
	var reflected := V.modes(source.no, source.ne, source.axis, n, tangent, -1)
	var transmitted := V.modes(target.no, target.ne, target.axis, n, tangent, 1)
	if reflected.size() != 2 or transmitted.size() != 2:
		return {"error": "Invalid medium or mode geometry"}
	var helper := V.vec(1, 0, 0) if absf(n[0]) < 0.8 else V.vec(0, 1, 0)
	var u := V.unit(V.cross(helper, n))
	var v := V.cross(n, u)
	var incoming := _tangent_fields(incident, u, v)
	var modes: Array[Dictionary] = []
	modes.append_array(reflected)
	modes.append_array(transmitted)
	var matrix := PackedFloat64Array()
	matrix.resize(32)
	for column in 4:
		var fields := _tangent_fields(modes[column], u, v)
		var sign_value := 1.0 if column < 2 else -1.0
		for row in 4:
			matrix[(row * 4 + column) * 2] = fields[row * 2] * sign_value
			matrix[(row * 4 + column) * 2 + 1] = fields[row * 2 + 1] * sign_value
	var rhs := incoming.duplicate()
	for i in rhs.size():
		rhs[i] = -rhs[i]
	var amplitudes := solve(matrix, rhs)
	if amplitudes.is_empty():
		return {"error": "Singular interface basis"}
	var branches: Array[Dictionary] = []
	var total := 0.0
	for column in 4:
		var ar := amplitudes[column * 2]
		var ai := amplitudes[column * 2 + 1]
		var side := -1.0 if column < 2 else 1.0
		var power: float = side * modes[column].normal_flux * (ar * ar + ai * ai) / incident_flux
		if modes[column].evanescent:
			power = 0.0
		total += power
		branches.append({"mode": modes[column], "reflected": column < 2,
			"amplitude": PackedFloat64Array([ar, ai]), "power": power})
	var residual := 0.0
	for row in 4:
		var real_value := incoming[row * 2]
		var imag_value := incoming[row * 2 + 1]
		for column in 4:
			var offset := (row * 4 + column) * 2
			var ar := amplitudes[column * 2]
			var ai := amplitudes[column * 2 + 1]
			real_value += matrix[offset] * ar - matrix[offset + 1] * ai
			imag_value += matrix[offset] * ai + matrix[offset + 1] * ar
		residual = maxf(residual, sqrt(real_value * real_value + imag_value * imag_value))
	return {"branches": branches, "total_power": total, "continuity_residual": residual,
		"matrix": matrix, "rhs": rhs, "amplitudes": amplitudes}

static func _tangent_fields(mode: Dictionary, u: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([V.dot(mode.E_real, u), V.dot(mode.E_imag, u),
		V.dot(mode.E_real, v), V.dot(mode.E_imag, v),
		V.dot(mode.H_real, u), V.dot(mode.H_imag, u),
		V.dot(mode.H_real, v), V.dot(mode.H_imag, v)])

## Row-major complex 4x4 partial-pivot elimination; complex numbers are adjacent
## float64 pairs. Avoid Vector2's float32 intermediates in this CPU reference.
static func solve(matrix: PackedFloat64Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	if matrix.size() != 32 or rhs.size() != 8:
		return PackedFloat64Array()
	var augmented := PackedFloat64Array()
	augmented.resize(40)
	for row in 4:
		for col in 4:
			augmented[row * 10 + col * 2] = matrix[row * 8 + col * 2]
			augmented[row * 10 + col * 2 + 1] = matrix[row * 8 + col * 2 + 1]
		augmented[row * 10 + 8] = rhs[row * 2]
		augmented[row * 10 + 9] = rhs[row * 2 + 1]
	for pivot in 4:
		var best := pivot
		var magnitude := 0.0
		for row in range(pivot, 4):
			var offset := row * 10 + pivot * 2
			var candidate := augmented[offset] * augmented[offset] + augmented[offset + 1] * augmented[offset + 1]
			if candidate > magnitude:
				magnitude = candidate
				best = row
		if magnitude < 1e-26:
			return PackedFloat64Array()
		if best != pivot:
			for i in 10:
				var temporary := augmented[pivot * 10 + i]
				augmented[pivot * 10 + i] = augmented[best * 10 + i]
				augmented[best * 10 + i] = temporary
		var diagonal := pivot * 10 + pivot * 2
		var dr := augmented[diagonal]
		var di := augmented[diagonal + 1]
		var divisor := dr * dr + di * di
		for col in range(pivot, 5):
			var offset := pivot * 10 + col * 2
			var ar := augmented[offset]
			var ai := augmented[offset + 1]
			augmented[offset] = (ar * dr + ai * di) / divisor
			augmented[offset + 1] = (ai * dr - ar * di) / divisor
		for row in 4:
			if row == pivot:
				continue
			var factor_r := augmented[row * 10 + pivot * 2]
			var factor_i := augmented[row * 10 + pivot * 2 + 1]
			for col in range(pivot, 5):
				var offset := pivot * 10 + col * 2
				augmented[row * 10 + col * 2] -= factor_r * augmented[offset] - factor_i * augmented[offset + 1]
				augmented[row * 10 + col * 2 + 1] -= factor_r * augmented[offset + 1] + factor_i * augmented[offset]
	var result := PackedFloat64Array()
	for row in 4:
		result.append(augmented[row * 10 + 8])
		result.append(augmented[row * 10 + 9])
	return result
