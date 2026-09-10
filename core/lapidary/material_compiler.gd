class_name GemMaterialCompiler
extends RefCounted
## Converts physical bulk properties once, independent of specimen geometry.
static func compile(material: GemMaterial) -> Dictionary:
	assert(material != null and material.validate().is_empty(), "Invalid bulk material")
	var species := material.species
	var index := species.ordinary.packed()
	var absorption := PackedFloat32Array()
	absorption.resize(401)
	var eray := PackedFloat32Array()
	var chromo := material.chromophore
	if chromo != null:
		if not chromo.absorption_mm.is_empty():
			absorption = _resample(chromo.absorption_mm, chromo)
		if not chromo.absorption_eray_mm.is_empty():
			eray = _resample(chromo.absorption_eray_mm, chromo)
	return {"absorption": absorption, "absorption_eray": eray,
		"sellmeier_b": index.b, "sellmeier_c": index.c,
		"index_offset": species.ordinary.index_offset,
		"extraordinary_refraction": species.extraordinary.packed() if species.extraordinary != null else {},
		"optic_axis": species.optic_axis_stone.normalized(),
		"scatter": {"sigma_per_mm": material.scatter_per_mm if material.scatter_per_mm >= 0.0 else species.base_scatter_per_mm,
			"g": material.scatter_g if material.scatter_per_mm >= 0.0 else species.scatter_anisotropy_g}}


static func _resample(values: PackedFloat32Array, chromo: GemChromophore) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	for index in 401:
		var position := (380.0 + index - chromo.wavelength_start_nm) / chromo.wavelength_step_nm
		var first := clampi(int(position), 0, values.size() - 1)
		output.append(lerpf(values[first], values[mini(first + 1, values.size() - 1)], position - first) * chromo.concentration)
	return output


## Capability gate for the persistent polarized renderer. Axial dichroism is
## a weak-loss approximation; it does not make a strongly absorbing boundary
## behave like a complex-index dielectric. The bound is an admission policy,
## not a universal error estimate, especially near critical angles.
static func polarization_error(material: Dictionary) -> String:
	if anisotropy_max(material) >= 1e-8:
		return "polarization currently supports isotropic real refraction only"
	var extraordinary: PackedFloat32Array = material.get("absorption_eray", PackedFloat32Array())
	if extraordinary.is_empty():
		return ""
	var axis: Vector3 = material.get("optic_axis", Vector3.BACK)
	if not axis.is_finite() or axis.length_squared() < 1e-12:
		return "dichroic absorption requires a physical axis"
	var ordinary: PackedFloat32Array = material.get("absorption", PackedFloat32Array())
	if ordinary.size() != 401 or extraordinary.size() != 401:
		return "dichroic spectra require the complete transport grid"
	var peak: float = 1.0 + absf(material.get("zoning", {}).get("contrast", 0.0))
	for field: GemVolumeField in material.get("volume_fields", []):
		peak += field.absorption_concentration
	peak *= material.get("absorb_scale", 1.0)
	for sample in 401:
		var wavelength := 380.0 + sample
		var index := principal_index(material, wavelength, false)
		var ratio := maxf(ordinary[sample], extraordinary[sample]) * peak * wavelength * 1e-6 / (2 * TAU * index)
		if not is_finite(ratio) or ratio < 0 or ratio > 0.001:
			return "dichroic absorption exceeds the weak-loss domain (imaginary/real index > 0.001)"
	return ""


## Evaluates the actual float32 coefficient wire format in CPU float64.
## Empty extraordinary data explicitly means isotropic, never a hidden offset.
static func principal_index(material: Dictionary, wavelength: float, extraordinary := false) -> float:
	var axis: Dictionary = material.get("extraordinary_refraction", {}) if extraordinary else {}
	var b: Vector3 = axis.get("b", material.sellmeier_b)
	var c: Vector3 = axis.get("c", material.sellmeier_c)
	var l2 := pow(wavelength * 0.001, 2)
	var n2 := 1.0
	for term in 3:
		if b[term] != 0:
			n2 += b[term] * l2 / (l2 - c[term])
	return sqrt(n2) + axis.get("offset", material.get("index_offset", 0.0))


## Admission uses the whole visible interval, not a signed difference at a
## single wavelength: principal curves can cross and still be anisotropic.
static func anisotropy_max(material: Dictionary) -> float:
	if material.get("extraordinary_refraction", {}).is_empty():
		return 0.0
	var largest := 0.0
	for wavelength in range(380, 781):
		largest = maxf(largest, absf(principal_index(material, wavelength, true) - principal_index(material, wavelength)))
	return largest
