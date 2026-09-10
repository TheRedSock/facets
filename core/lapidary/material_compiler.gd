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
