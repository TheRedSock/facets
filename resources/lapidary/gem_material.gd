class_name GemMaterial
extends Resource
## Reusable bulk material recipe, independent of shape, grade, pose or lighting.
## The same material can be a host, a crystal inclusion, or a fracture filling.
@export var material_id: StringName
@export var species: GemSpecies
@export var chromophore: GemChromophore
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
	if chromophore != null:
		errors.append_array(chromophore.validate())
	if scattering_evidence == null:
		errors.append("Scattering evidence descriptor is missing")
	else:
		errors.append_array(scattering_evidence.validate())
	return errors
