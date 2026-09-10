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
		var spatial:=GemMaterialCompiler.field_absorption(stone.material,stone.condition.volume_fields)
		if spatial.has("error"):return spatial.error
		material["field_absorption"]=spatial.spectra
		material["zoning"] = stone.condition.banding.normalized(stone.size_mm) if stone.condition.banding != null else {}
		var cleavage := stone.condition.cleavage
		if cleavage != null and cleavage.depth_mm > 0 and cleavage.finish != null and cleavage.finish.has_roughness():
			return "Crystal transport does not yet support rough cleavage boundaries"
		for defect in stone.condition.defects:
			if defect == null or not defect.enabled:
				continue
			if defect.finish != null and defect.finish.has_roughness():
				return "Crystal transport does not yet support rough defect boundaries"
			if defect.filling != null:
				if not defect.filling.validate().is_empty():
					return "Invalid crystal defect filling"
				var why := compiled_error(GemMaterialCompiler.compile(defect.filling))
				if not why.is_empty():
					return why
	return compiled_error(material)

static func compiled_error(material: Dictionary) -> String:
	var peak:=GemMaterialCompiler.peak_absorption(material)
	if peak.has("error"):return peak.error
	if material.get("scatter", {}).get("sigma_per_mm", 0.0) > 0:
		return "Crystal transport does not yet support volume scattering"
	for finish: GemSurface in material.get("surfaces", []):
		if finish.has_roughness():
			return "Crystal transport does not yet support rough boundaries"
	for field: GemVolumeField in material.get("volume_fields", []):
		if field.scatter_per_mm > 0:
			return "Crystal transport does not yet support spatial scattering"
	for sample in 401:
		var ao:float=peak.ordinary[sample]
		var ae:float=peak.parallel[sample]
		var wavelength := 380.0 + sample
		var no := GemMaterialCompiler.principal_index(material, wavelength)
		var ne := GemMaterialCompiler.principal_index(material, wavelength, true)
		if GemCrystalLoss.relative_imaginary_index(no, ne, ao, ae, wavelength) > 0.001:
			return "Crystal absorption exceeds the weak-loss domain"
	return ""
