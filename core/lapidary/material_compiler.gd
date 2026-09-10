class_name GemMaterialCompiler
extends RefCounted
## Converts physical bulk properties once, independent of specimen geometry.
static func compile(material: GemMaterial) -> Dictionary:
	assert(material != null and material.validate().is_empty(), "Invalid bulk material")
	var species := material.species
	var index := species.ordinary.packed()
	var absorption:=PackedFloat32Array()
	var eray:=PackedFloat32Array()
	var has_parallel:=false
	for term in material.absorbers:
		has_parallel=has_parallel or (term.amount>0 and term.chromophore.has_parallel_curve())
	for wavelength in range(380,781):
		var ordinary:=0.0
		var parallel:=0.0
		for term in material.absorbers:
			var scale:=term.coefficient_scale(material.atom_density_per_cm3)
			ordinary+=term.chromophore.sample(wavelength)*scale
			if has_parallel:parallel+=term.chromophore.sample(wavelength,true)*scale
		absorption.append(ordinary)
		if has_parallel:eray.append(parallel)
	return {"absorption": absorption, "absorption_eray": eray,
		"sellmeier_b": index.b, "sellmeier_c": index.c,
		"index_offset": species.ordinary.index_offset,
		"extraordinary_refraction": species.extraordinary.packed() if species.extraordinary != null else {},
		"optic_axis": species.optic_axis_stone.normalized(),
		"scatter": {"sigma_per_mm": material.scatter_per_mm if material.scatter_per_mm >= 0.0 else species.base_scatter_per_mm,
			"g": material.scatter_g if material.scatter_per_mm >= 0.0 else species.scatter_anisotropy_g}}

## Compile each field's additional composition in its host lattice. No added
## optical boundary or independent refractive index is introduced by doping.
static func field_absorption(material:GemMaterial, fields:Array) -> Dictionary:
	var spectra:=[]
	for field:GemVolumeField in fields:
		if field==null:return {"error":"Spatial field is missing"}
		var errors:=field.validate()
		if not errors.is_empty():return {"error":"; ".join(errors)}
		if field.absorbers.is_empty():
			spectra.append({})
			continue
		var recipe:=GemMaterial.new()
		recipe.species=material.species
		recipe.atom_density_per_cm3=material.atom_density_per_cm3
		recipe.absorbers=field.absorbers
		errors=recipe.validate()
		if not errors.is_empty():return {"error":"Spatial composition: "+"; ".join(errors)}
		var bulk:=compile(recipe)
		spectra.append({"absorption":bulk.absorption,"absorption_eray":bulk.absorption_eray})
	return {"spectra":spectra}

## Conservative spectral bound for all overlapping fields, independent of pose.
## Float64 sums reject overflow before upload; weak-loss gates use both axes.
static func peak_absorption(material:Dictionary)->Dictionary:
	var fields:Array=material.get("volume_fields",[])
	var spectra:Array=material.get("field_absorption",[])
	var base:PackedFloat32Array=material.get("absorption",PackedFloat32Array())
	var extra:PackedFloat32Array=material.get("absorption_eray",PackedFloat32Array())
	if base.size()!=401 or (not extra.is_empty() and extra.size()!=401):return {"error":"Invalid absorption grid"}
	var scale:float=material.get("absorb_scale",1.0)
	var host_peak:float=1+absf(material.get("zoning",{}).get("contrast",0.0))
	var anisotropic:=not extra.is_empty()
	if fields.size()>16:return {"error":"Too many spatial fields"}
	for index in fields.size():
		var field:GemVolumeField=fields[index]
		if field==null or not field.validate().is_empty():return {"error":"Invalid spatial field"}
		host_peak+=field.absorption_concentration
		if not field.absorbers.is_empty() and (index>=spectra.size() or spectra[index].is_empty()):return {"error":"Spatial absorber spectra were not compiled"}
		if index<spectra.size() and not spectra[index].is_empty():
			var entry:Dictionary=spectra[index]
			if entry.get("absorption",[]).size()!=401 or entry.get("absorption_eray",[]).size() not in [0,401]:return {"error":"Invalid spatial absorption grid"}
			anisotropic=anisotropic or not entry.absorption_eray.is_empty()
	var ordinary:=PackedFloat64Array()
	var parallel:=PackedFloat64Array()
	for wavelength in 401:
		var ao:float=base[wavelength]*host_peak
		var ae:float=(extra[wavelength] if not extra.is_empty() else base[wavelength])*host_peak
		for index in fields.size():
			if index>=spectra.size() or spectra[index].is_empty():continue
			var entry:Dictionary=spectra[index]
			ao+=entry.absorption[wavelength]
			ae+=entry.absorption_eray[wavelength] if not entry.absorption_eray.is_empty() else entry.absorption[wavelength]
		ao*=scale;ae*=scale
		if not is_finite(ao) or not is_finite(ae) or minf(ao,ae)<0 or maxf(ao,ae)>3.4028234e38:return {"error":"Spatial absorption exceeds the float32 transport range"}
		ordinary.append(ao);parallel.append(ae)
	return {"ordinary":ordinary,"parallel":parallel,"anisotropic":anisotropic}


## Capability gate for the persistent polarized renderer. Axial dichroism is
## a weak-loss approximation; it does not make a strongly absorbing boundary
## behave like a complex-index dielectric. The bound is an admission policy,
## not a universal error estimate, especially near critical angles.
static func polarization_error(material: Dictionary) -> String:
	if anisotropy_max(material) >= 1e-8:
		return "polarization currently supports isotropic real refraction only"
	var peak:=peak_absorption(material)
	if peak.has("error"):return peak.error
	if not peak.anisotropic:
		return ""
	var axis: Vector3 = material.get("optic_axis", Vector3.BACK)
	if not axis.is_finite() or axis.length_squared() < 1e-12:
		return "dichroic absorption requires a physical axis"
	for sample in 401:
		var wavelength := 380.0 + sample
		var index := principal_index(material, wavelength, false)
		var ratio:float=maxf(peak.ordinary[sample],peak.parallel[sample])*wavelength*1e-6/(2*TAU*index)
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
