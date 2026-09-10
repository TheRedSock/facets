class_name GemMaterialCompiler
extends RefCounted
## Converts physical bulk properties once, independent of specimen geometry.
static func compile(material: GemMaterial) -> Dictionary:
	assert(material != null and material.validate().is_empty(), "Invalid bulk material")
	var species := material.species
	var absorption := PackedFloat32Array()
	absorption.resize(81)
	var eray := PackedFloat32Array()
	var chromo := material.chromophore
	if chromo != null:
		if not chromo.absorption_mm.is_empty():
			absorption = chromo.absorption_mm.duplicate()
			eray = chromo.absorption_eray_mm.duplicate()
		for i in absorption.size():
			absorption[i] *= chromo.concentration
		for i in eray.size():
			eray[i] *= chromo.concentration
	return {"absorption": absorption, "absorption_eray": eray,
		"sellmeier_b": species.sellmeier_b, "sellmeier_c": species.sellmeier_c_um2,
		"birefringence": species.birefringence * (1.0 if species.uniaxial_positive else -1.0),
		"optic_axis": species.optic_axis_stone.normalized(),
		"scatter": {"sigma_per_mm": material.scatter_per_mm if material.scatter_per_mm >= 0.0 else species.base_scatter_per_mm,
			"g": material.scatter_g if material.scatter_per_mm >= 0.0 else species.scatter_anisotropy_g}}
