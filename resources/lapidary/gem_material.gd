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
@export_enum("measured", "literature_fit", "authored") var provenance := "authored"
@export_multiline var source_note := ""

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if species == null:
		errors.append("Material needs a mineral or filling species")
	if not is_finite(scatter_per_mm) or not is_finite(scatter_g) or absf(scatter_g) >= 1.0:
		errors.append("Invalid volume scattering coefficients")
	if chromophore != null:
		for curve in [chromophore.absorption_mm, chromophore.absorption_eray_mm]:
			if not curve.is_empty() and curve.size() != 81:
				errors.append("Absorption must have 81 samples at 380..780 nm")
			for value in curve:
				if not is_finite(value) or value < 0.0:
					errors.append("Absorption must be finite and nonnegative")
	return errors
