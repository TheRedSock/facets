class_name GemColorimetry
extends RefCounted
## Host-side colorimetry shared with the kernel: the same CIE 1931 2° CMF
## analytic fit (Wyman, Sloan, Shirley, JCGT 2013) and 560 nm-relative Planck
## spectrum the shaders use, plus the as-shot white balance of the print
## (Bradford chromatic adaptation from the rig's neutral to D65).

const D65_XYZ := Vector3(0.95047, 1.0, 1.08883)

# Bradford cone response matrix (rows), Lindbloom / Fairchild.
const BRADFORD_R0 := Vector3(0.8951, 0.2664, -0.1614)
const BRADFORD_R1 := Vector3(-0.7502, 1.7135, 0.0367)
const BRADFORD_R2 := Vector3(0.0389, -0.0685, 1.0296)

# sRGB (D65) from XYZ, rows (IEC 61966-2-1).
const SRGB_R0 := Vector3(3.2406, -1.5372, -0.4986)
const SRGB_R1 := Vector3(-0.9689, 1.8758, 0.0415)
const SRGB_R2 := Vector3(0.0557, -0.2040, 1.0570)


static func cie_xyz(w: float) -> Vector3:
	var x1 := (w - 442.0) * (0.0624 if w < 442.0 else 0.0374)
	var x2 := (w - 599.8) * (0.0264 if w < 599.8 else 0.0323)
	var x3 := (w - 501.1) * (0.0490 if w < 501.1 else 0.0382)
	var y1 := (w - 568.8) * (0.0213 if w < 568.8 else 0.0247)
	var y2 := (w - 530.9) * (0.0613 if w < 530.9 else 0.0322)
	var z1 := (w - 437.0) * (0.0845 if w < 437.0 else 0.0278)
	var z2 := (w - 459.0) * (0.0385 if w < 459.0 else 0.0725)
	return Vector3(
		0.362 * exp(-0.5 * x1 * x1) + 1.056 * exp(-0.5 * x2 * x2) - 0.065 * exp(-0.5 * x3 * x3),
		0.821 * exp(-0.5 * y1 * y1) + 0.286 * exp(-0.5 * y2 * y2),
		1.217 * exp(-0.5 * z1 * z1) + 0.681 * exp(-0.5 * z2 * z2))


## Integral of the ybar fit over 380..780 nm at 1 nm (kernel spectral_norm).
static func integral_ybar() -> float:
	var total := 0.0
	for i in 401:
		total += cie_xyz(380.0 + float(i)).y
	return total


## Planck spectral radiance relative to 560 nm (matches gem_common.glsl).
static func planck_rel(wl_nm: float, kelvin: float) -> float:
	var c2 := 1.4388e7
	var r := 560.0 / wl_nm
	return r * r * r * r * r * (exp(c2 / (560.0 * kelvin)) - 1.0) / maxf(exp(c2 / (wl_nm * kelvin)) - 1.0, 1e-12)


## XYZ of a Planckian illuminant, normalised to Y = 1.
static func illuminant_xyz(kelvin: float) -> Vector3:
	var acc := Vector3.ZERO
	for i in 401:
		var w := 380.0 + float(i)
		acc += cie_xyz(w) * planck_rel(w, kelvin)
	return acc / maxf(acc.y, 1e-9)


## Bradford chromatic adaptation taking colours seen under `src_white` to how
## they read under `dst_white` (both XYZ, Y = 1).
static func bradford(src_white: Vector3, dst_white: Vector3) -> Basis:
	var m := from_rows(BRADFORD_R0, BRADFORD_R1, BRADFORD_R2)
	var cs := m * src_white
	var cd := m * dst_white
	var d := Basis.from_scale(Vector3(cd.x / cs.x, cd.y / cs.y, cd.z / cs.z))
	return m.inverse() * d * m


## Print matrix: XYZ (scene, lit by a `white_kelvin` neutral) -> linear sRGB,
## white-balanced so that illuminant renders as D65 white. 0 = no adaptation.
static func xyz_to_srgb(white_kelvin: float) -> Basis:
	var srgb := from_rows(SRGB_R0, SRGB_R1, SRGB_R2)
	if white_kelvin <= 0.0:
		return srgb
	return srgb * bradford(illuminant_xyz(white_kelvin), D65_XYZ)


## Basis whose matrix has the given rows (Basis stores columns).
static func from_rows(r0: Vector3, r1: Vector3, r2: Vector3) -> Basis:
	return Basis(Vector3(r0.x, r1.x, r2.x), Vector3(r0.y, r1.y, r2.y), Vector3(r0.z, r1.z, r2.z))
