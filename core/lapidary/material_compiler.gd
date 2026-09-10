class_name GemMaterialCompiler
extends RefCounted
## Converts physical bulk properties once, independent of specimen geometry.
static func compile(material: GemMaterial) -> Dictionary:
	assert(material != null and material.validate().is_empty(), "Invalid bulk material")
	var species := material.species
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
		"sellmeier_b": species.sellmeier_b, "sellmeier_c": species.sellmeier_c_um2,
		"birefringence": species.birefringence * (1.0 if species.uniaxial_positive else -1.0),
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
	if absf(material.get("birefringence", 0.0)) >= 1e-8:
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
	var species := GemSpecies.new()
	species.sellmeier_b = material.sellmeier_b
	species.sellmeier_c_um2 = material.sellmeier_c
	for sample in 401:
		var wavelength := 380.0 + sample
		var index := species.ior_at(wavelength)
		var ratio := maxf(ordinary[sample], extraordinary[sample]) * peak * wavelength * 1e-6 / (2 * TAU * index)
		if not is_finite(ratio) or ratio < 0 or ratio > 0.001:
			return "dichroic absorption exceeds the weak-loss domain (imaginary/real index > 0.001)"
	return ""
