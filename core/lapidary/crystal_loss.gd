class_name GemCrystalLoss
extends RefCounted
## Weak dielectric loss on lossless Maxwell modes. Not used by the tracer yet.
## alpha_o/e are principal Napierian intensity coefficients in inverse mm,
## corresponding to imaginary principal indices kappa=alpha/(2*k0).
## Poynting's theorem gives Q=(omega/2) E* Im(epsilon) E. To first order in
## kappa/n, Im(epsilon)*k0 = no*alpha_o I + (ne*alpha_e-no*alpha_o) aa^T.
## Divide Q by |S| to obtain attenuation per energy-ray arclength.
## Sources: Chew, Theory of Microwave and Optical Waveguides, Sec1.7;
## https://engineering.purdue.edu/wcchew/course/tgwAll20160215.pdf
## and Fowler, Poynting's theorem in dispersive media with loss:
## https://galileoandeinstein.phys.virginia.edu/Elec_Mag/2022_Lectures/EM_42_Poynting_Losses.html
const V := preload("res://core/lapidary/crystal_modes.gd")
const Packet := preload("res://core/lapidary/crystal_packet.gd")

## Instantaneous loss rate. A fixed exponential over a segment is appropriate
## for a single eigenmode, not an arbitrary mixture with unequal attenuation.
static func rate(mode: Dictionary, no: float, ne: float, axis: PackedFloat64Array,
		alpha_o: float, alpha_e: float) -> float:
	if not _valid(no, ne, axis, alpha_o, alpha_e) or mode.evanescent:
		return NAN
	var a := V.unit(axis)
	var e2 := V.dot(mode.E_real, mode.E_real) + V.dot(mode.E_imag, mode.E_imag)
	var axial2 := pow(V.dot(mode.E_real, a), 2) + pow(V.dot(mode.E_imag, a), 2)
	var flux := sqrt(V.dot(mode.poynting, mode.poynting))
	if flux <= 0:
		return NAN
	# Separate nonnegative perpendicular/parallel terms to avoid cancellation
	# when one principal absorption coefficient is exactly zero.
	return (no * alpha_o * maxf(0, e2 - axial2) + ne * alpha_e * axial2) / (2 * flux)

## Diagnostic of the approximation domain, not an automatic accuracy guarantee.
## Near degeneracy or critical interfaces can be more sensitive than this ratio.
static func relative_imaginary_index(no: float, ne: float, alpha_o: float, alpha_e: float, wavelength_nm: float) -> float:
	if not is_finite(no) or not is_finite(ne) or not is_finite(alpha_o) or not is_finite(alpha_e) or no <= 0 or ne <= 0 or wavelength_nm <= 0 or not is_finite(wavelength_nm) or alpha_o < 0 or alpha_e < 0:
		return NAN
	var k0 := TAU / (wavelength_nm * 1e-6)
	return maxf(alpha_o / no, alpha_e / ne) / (2 * k0)

static func attenuate_eigenmode(mode: Dictionary, no: float, ne: float, axis: PackedFloat64Array,
		alpha_o: float, alpha_e: float, column_mm: float) -> Dictionary:
	var alpha := rate(mode, no, ne, axis, alpha_o, alpha_e)
	if not is_finite(alpha) or column_mm < 0 or not is_finite(column_mm):
		return {"error": "Invalid weak-loss eigenmode or optical column"}
	var result := mode.duplicate(true)
	var intensity := exp(-alpha * column_mm)
	for field in ["E_real", "E_imag", "H_real", "H_imag"]:
		result[field] = V.scale(result[field], sqrt(intensity))
	result["poynting"] = V.scale(result.poynting, intensity)
	if result.has("normal_flux"):
		result["normal_flux"] *= intensity
	return result

## Isotropic real index with an axial absorption tensor: propagate the two
## coherent transverse components separately, preserving the resulting Jones
## state between segments. Spatially separated anisotropic modes require their
## own geometric paths. Common optical phase is omitted here; this does not
## simulate interferometry or recombination of separately travelled paths.
static func propagate_isotropic(packet: Dictionary, index: float, axis: PackedFloat64Array,
		alpha_o: float, alpha_e: float, column_mm: float) -> Dictionary:
	if not _valid(index, index, axis, alpha_o, alpha_e) or column_mm < 0 or not is_finite(column_mm) or packet.evanescent:
		return {"error": "Invalid isotropic dichroic segment"}
	var direction := V.unit(packet.k_real)
	var basis := V.modes(index, index, axis, direction, V.vec(0, 0, 0), 1)
	if basis.size() != 2:
		return {"error": "Invalid isotropic ray direction"}
	var components := []
	for mode in basis:
		var alpha := rate(mode, index, index, axis, alpha_o, alpha_e)
		var amplitude := exp(-0.5 * alpha * column_mm)
		components.append({"mode": mode, "amplitude": [amplitude * V.dot(packet.E_real, mode.E_real), amplitude * V.dot(packet.E_imag, mode.E_real)]})
	return Packet.combine(components)

static func _valid(no: float, ne: float, axis: PackedFloat64Array, alpha_o: float, alpha_e: float) -> bool:
	return is_finite(no) and is_finite(ne) and no > 0 and ne > 0 and is_finite(alpha_o) and is_finite(alpha_e) and alpha_o >= 0 and alpha_e >= 0 and V.valid_vector(axis) and V.dot(axis, axis) > 1e-24
