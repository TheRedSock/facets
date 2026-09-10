class_name GemMaterial
extends Resource
## Reusable bulk material recipe, independent of shape, grade, pose or lighting.
## The same material can be a host, a crystal inclusion, or a fracture filling.
@export var material_id: StringName
@export var species: GemSpecies
@export var absorbers: Array[GemAbsorber] = []
## Total host atoms per cm3, required only for PPMA_TOTAL_ATOMS terms.
## This is not cation-site ppm, mass ppm, molarity, or an inferred density.
@export var atom_density_per_cm3 := 0.0
## Optional measured or authored bulk scattering; negative inherits species.
@export var scatter_per_mm := -1.0
@export_range(-0.99, 0.99) var scatter_g := 0.6
@export var scattering_evidence: GemOpticalEvidence = GemOpticalEvidence.new()
@export_multiline var source_note := ""

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if species == null:
		errors.append("Material needs a mineral or filling species")
	else:
		errors.append_array(species.validate())
	if not is_finite(scatter_per_mm) or not is_finite(scatter_g) or absf(scatter_g) >= 1.0:
		errors.append("Invalid volume scattering coefficients")
	if not is_finite(atom_density_per_cm3) or atom_density_per_cm3<0 or absorbers.size()>64:
		errors.append("Invalid host atom density or more than 64 absorption terms")
	for term in absorbers:
		if term==null:
			errors.append("Null absorption term")
		else:
			errors.append_array(term.validate(species.species_id if species!=null else &"",atom_density_per_cm3))
	if errors.is_empty():
		for wavelength in range(380,781):
			var ordinary:=0.0
			var parallel:=0.0
			for term in absorbers:
				var scale:=term.coefficient_scale(atom_density_per_cm3)
				ordinary+=term.chromophore.sample(wavelength)*scale
				parallel+=term.chromophore.sample(wavelength,true)*scale
			if not is_finite(ordinary) or not is_finite(parallel) or maxf(ordinary,parallel)>3.4028234e38:
				errors.append("Combined absorption exceeds the float32 transport range")
				break
	if scattering_evidence == null:
		errors.append("Scattering evidence descriptor is missing")
	else:
		errors.append_array(scattering_evidence.validate())
	return errors
