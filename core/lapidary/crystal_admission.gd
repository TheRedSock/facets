class_name GemCrystalAdmission
extends RefCounted
## Explicit domain of the reciprocal air-endpoint Maxwell path tracer.
static func stone_error(stone: GemStone) -> String:
	if stone == null or stone.material == null:
		return "Crystal transport needs a valid specimen"
	if not stone.material.validate().is_empty():
		return "; ".join(stone.material.validate())
	var material := GemMaterialCompiler.compile(stone.material)
	if stone.condition != null:
		if not stone.condition.validate_volume_fields().is_empty():
			return "; ".join(stone.condition.validate_volume_fields())
		material["surfaces"] = [stone.condition.finish] if stone.condition.finish != null else []
		material["volume_fields"] = stone.condition.volume_fields
		material["zoning"] = stone.condition.banding.normalized(stone.size_mm) if stone.condition.banding != null else {}
		for defect in stone.condition.defects:
			if defect == null or not defect.enabled:
				continue
			if defect.finish != null and maxf(defect.finish.alpha_u, defect.finish.alpha_v) >= 0.0001:
				return "Crystal transport does not yet support rough defect boundaries"
			if defect.filling != null:
				if not defect.filling.validate().is_empty():
					return "Invalid crystal defect filling"
				var why := compiled_error(GemMaterialCompiler.compile(defect.filling))
				if not why.is_empty():
					return why
	return compiled_error(material)

static func compiled_error(material: Dictionary) -> String:
	if material.get("scatter", {}).get("sigma_per_mm", 0.0) > 0:
		return "Crystal transport does not yet support volume scattering"
	for finish: GemSurface in material.get("surfaces", []):
		if maxf(finish.alpha_u, finish.alpha_v) >= 0.0001:
			return "Crystal transport does not yet support rough boundaries"
	var peak: float = 1.0 + absf(material.get("zoning", {}).get("contrast", 0.0))
	for field: GemVolumeField in material.get("volume_fields", []):
		if field.scatter_per_mm > 0:
			return "Crystal transport does not yet support spatial scattering"
		peak += field.absorption_concentration
	peak *= material.get("absorb_scale", 1.0)
	var absorption: PackedFloat32Array = material.get("absorption", PackedFloat32Array())
	var extraordinary: PackedFloat32Array = material.get("absorption_eray", PackedFloat32Array())
	for sample in absorption.size():
		var ao := absorption[sample] * peak
		var ae := extraordinary[sample] * peak if not extraordinary.is_empty() else ao
		var wavelength := 380.0 + sample
		var no := GemMaterialCompiler.principal_index(material, wavelength)
		var ne := GemMaterialCompiler.principal_index(material, wavelength, true)
		if GemCrystalLoss.relative_imaginary_index(no, ne, ao, ae, wavelength) > 0.001:
			return "Crystal absorption exceeds the weak-loss domain"
	return ""
