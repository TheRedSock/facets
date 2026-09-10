class_name GemCrystalModes
extends RefCounted
## Lossless uniaxial Maxwell modes. Float64 arrays keep the CPU reference
## independent of Godot's float32 Vector3 arithmetic. k is divided by vacuum k0.
## exp(i k.x - i omega t); normal points into the positive half-space.
## Evanescent modes participate in boundary equations, never geometric transport.
## No GPU transport calls this module yet.
## Modal reference: Thomson, Wilen & Wettlaufer, JPCM21 (2009)195407, Sec2.1:
## https://arxiv.org/abs/0901.2558 . Implementation derives roots from k^T M k=1.

static func modes(no: float, ne: float, axis: PackedFloat64Array, normal: PackedFloat64Array,
		tangent: PackedFloat64Array, side: int) -> Array[Dictionary]:
	if no <= 0 or ne <= 0 or not is_finite(no) or not is_finite(ne) or side not in [-1, 1]:
		return []
	if not valid_vector(axis) or not valid_vector(normal) or not valid_vector(tangent) or dot(axis, axis) < 1e-24 or dot(normal, normal) < 1e-24:
		return []
	var a := unit(axis)
	var n := unit(normal)
	if absf(dot(tangent, n)) > 1e-10 * maxf(1, sqrt(dot(tangent, tangent))):
		return []
	var result: Array[Dictionary] = []
	for extraordinary in [false, true]:
		var coefficient := 1.0
		var linear := 0.0
		var constant := dot(tangent, tangent) - no * no
		if extraordinary:
			var mn := metric(n, a, no, ne)
			var mt := metric(tangent, a, no, ne)
			coefficient = dot(n, mn)
			linear = dot(n, mt)
			constant = dot(tangent, mt) - 1.0
		var discriminant := linear * linear - coefficient * constant
		var qr := -linear / coefficient
		var qi := 0.0
		if discriminant >= 0:
			qr += side * sqrt(discriminant) / coefficient
		else:
			qi = side * sqrt(-discriminant) / coefficient
		var kr := add(tangent, scale(n, qr))
		var ki := scale(n, qi)
		var oray_r := cross(a, kr)
		var oray_i := cross(a, ki)
		var degenerate := dot(oray_r, oray_r) + dot(oray_i, oray_i) < 1e-22
		if degenerate:
			# Along the optic axis both modes have the ordinary index. Choose a
			# deterministic orthogonal transverse basis, not a singular 0/0.
			var helper := vec(1, 0, 0) if absf(kr[0]) < 0.8 * sqrt(dot(kr, kr)) else vec(0, 1, 0)
			oray_r = cross(helper, kr)
			oray_i = cross(helper, ki)
		var er := oray_r
		var ei := oray_i
		if extraordinary:
			var dr := subtract(cross(kr, oray_r), cross(ki, oray_i))
			var di := add(cross(kr, oray_i), cross(ki, oray_r))
			er = inverse_permittivity(dr, a, no, ne)
			ei = inverse_permittivity(di, a, no, ne)
		var norm := sqrt(dot(er, er) + dot(ei, ei))
		if norm <= 1e-30 or not is_finite(norm):
			return []
		er = scale(er, 1.0 / norm)
		ei = scale(ei, 1.0 / norm)
		var hr := subtract(cross(kr, er), cross(ki, ei))
		var hi := add(cross(kr, ei), cross(ki, er))
		var poynting := scale(add(cross(er, hr), cross(ei, hi)), 0.5)
		result.append({"extraordinary": extraordinary, "q": PackedFloat64Array([qr, qi]),
			"k_real": kr, "k_imag": ki, "E_real": er, "E_imag": ei,
			"H_real": hr, "H_imag": hi, "poynting": poynting,
			"normal_flux": dot(poynting, n), "evanescent": discriminant < 0,
			"ray": unit(poynting), "degenerate": degenerate})
	return result

## Extraordinary dispersion: k^T M k = 1, M = I/ne² + (1/no²-1/ne²) aa^T.
## Its gradient gives the energy direction; phase and energy generally differ.
static func metric(value: PackedFloat64Array, axis: PackedFloat64Array, no: float, ne: float) -> PackedFloat64Array:
	return add(scale(value, 1.0 / (ne * ne)), scale(axis, dot(value, axis) * (1.0 / (no * no) - 1.0 / (ne * ne))))

static func permittivity(value: PackedFloat64Array, axis: PackedFloat64Array, no: float, ne: float) -> PackedFloat64Array:
	return add(scale(value, no * no), scale(axis, dot(value, axis) * (ne * ne - no * no)))

static func inverse_permittivity(value: PackedFloat64Array, axis: PackedFloat64Array, no: float, ne: float) -> PackedFloat64Array:
	return add(scale(value, 1.0 / (no * no)), scale(axis, dot(value, axis) * (1.0 / (ne * ne) - 1.0 / (no * no))))

static func maxwell_residual(mode: Dictionary, no: float, ne: float, axis: PackedFloat64Array) -> float:
	var lhs_r := subtract(cross(mode.k_real, mode.H_real), cross(mode.k_imag, mode.H_imag))
	var lhs_i := add(cross(mode.k_real, mode.H_imag), cross(mode.k_imag, mode.H_real))
	var residual_r := add(lhs_r, permittivity(mode.E_real, unit(axis), no, ne))
	var residual_i := add(lhs_i, permittivity(mode.E_imag, unit(axis), no, ne))
	return sqrt(dot(residual_r, residual_r) + dot(residual_i, residual_i))

static func vec(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])

static func valid_vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and is_finite(value[0]) and is_finite(value[1]) and is_finite(value[2])

static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return vec(a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

static func scale(a: PackedFloat64Array, value: float) -> PackedFloat64Array:
	return vec(a[0] * value, a[1] * value, a[2] * value)

static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return vec(a[0] + b[0], a[1] + b[1], a[2] + b[2])

static func subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return add(a, scale(b, -1))

static func unit(a: PackedFloat64Array) -> PackedFloat64Array:
	var length := sqrt(dot(a, a))
	return scale(a, 1.0 / length) if length > 0 else vec(0, 0, 0)
