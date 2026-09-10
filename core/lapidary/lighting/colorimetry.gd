class_name GemColorimetry
extends RefCounted
## Host-side colorimetry shared with the kernel: the CIE 1931 2° observer
## tabulated at 1 nm (GemStandardSpectra) and 560 nm-relative Planck
## spectrum compiled into GPU tables, plus the as-shot white balance of the print
## (Bradford chromatic adaptation from the rig's neutral to D65).

const D65_XYZ := Vector3(0.95047, 1.0, 1.08883)
static var _ybar_integral := 0.0

# Bradford cone response matrix (rows), Lindbloom / Fairchild.
const BRADFORD_R0 := Vector3(0.8951, 0.2664, -0.1614)
const BRADFORD_R1 := Vector3(-0.7502, 1.7135, 0.0367)
const BRADFORD_R2 := Vector3(0.0389, -0.0685, 1.0296)

# sRGB (D65) from XYZ, rows (IEC 61966-2-1).
const SRGB_R0 := Vector3(3.2406, -1.5372, -0.4986)
const SRGB_R1 := Vector3(-0.9689, 1.8758, 0.0415)
const SRGB_R2 := Vector3(0.0557, -0.2040, 1.0570)


static func cie_xyz(w: float) -> Vector3:
	return GemStandardSpectra.xyz(w)


## Exact integral of the piecewise-linear ybar table over the transport domain.
static func integral_ybar() -> float:
	if _ybar_integral > 0.0:
		return _ybar_integral
	var total := 0.0
	for i in 401:
		total += cie_xyz(380.0 + float(i)).y * (0.5 if i == 0 or i == 400 else 1.0)
	_ybar_integral = total
	return total


## Planck spectral radiance relative to 560 nm (sampled by GemSpectrumCompiler).
static func planck_rel(wl_nm: float, kelvin: float) -> float:
	var c2 := 1.4388e7
	var r := 560.0 / wl_nm
	return r * r * r * r * r * (exp(c2 / (560.0 * kelvin)) - 1.0) / maxf(exp(c2 / (wl_nm * kelvin)) - 1.0, 1e-12)


## XYZ of a Planckian illuminant, normalised to Y = 1.
static func illuminant_xyz(kelvin: float) -> Vector3:
	var acc := Vector3.ZERO
	for i in 401:
		var w := 380.0 + float(i)
		acc += cie_xyz(w) * planck_rel(w, kelvin) * (0.5 if i == 0 or i == 400 else 1.0)
	return acc / maxf(acc.y, 1e-9)


## Bradford chromatic adaptation taking colours seen under `src_white` to how
## they read under `dst_white` (both XYZ, Y = 1).
static func bradford(src_white: Vector3, dst_white: Vector3) -> Basis:
	var m := from_rows(BRADFORD_R0, BRADFORD_R1, BRADFORD_R2)
	var cs := m * src_white
	var cd := m * dst_white
	var d := Basis.from_scale(Vector3(cd.x / cs.x, cd.y / cs.y, cd.z / cs.z))
	return m.inverse() * d * m


## Integrates two piecewise-linear tables exactly within each 1 nm interval.
## Y is relative to unit equal-energy radiance over the transport domain.
static func spectrum_xyz(values: PackedFloat32Array) -> Vector3:
	assert(values.size() == 401)
	var total := Vector3.ZERO
	for index in 400:
		var a := cie_xyz(380.0 + index)
		var b := cie_xyz(381.0 + index)
		total += (a * values[index] + (a + b) * (values[index] + values[index + 1]) + b * values[index + 1]) / 6.0
	return total / integral_ybar()


## Print matrix from scene XYZ to D65 sRGB. Zero means no adaptation.
static func xyz_to_srgb(white_xyz := Vector3.ZERO) -> Basis:
	var srgb := from_rows(SRGB_R0, SRGB_R1, SRGB_R2)
	if white_xyz == Vector3.ZERO:
		return srgb
	return srgb * bradford(white_xyz / white_xyz.y, D65_XYZ)


## Basis whose matrix has the given rows (Basis stores columns).
static func from_rows(r0: Vector3, r1: Vector3, r2: Vector3) -> Basis:
	return Basis(Vector3(r0.x, r1.x, r2.x), Vector3(r0.y, r1.y, r2.y), Vector3(r0.z, r1.z, r2.z))
