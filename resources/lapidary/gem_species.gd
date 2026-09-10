class_name GemSpecies
extends Resource
## Lattice physics of a mineral species. Shared by every stone of that mineral
## (ruby and sapphire share corundum). No color here — color is the chromophore.

@export var species_id: StringName
@export var display_name := ""
## Citation for the optical constants (journal / refractiveindex.info page).
@export var source_note := ""
@export var refraction_evidence: GemOpticalEvidence = GemOpticalEvidence.new()
## Model evaluation domain, not a claim of measured accuracy throughout it.
@export var refraction_range_nm := Vector2(380.0, 780.0)

@export_group("Refraction")
## 3-term Sellmeier, ordinary ray: n^2 - 1 = sum B_i * L^2 / (L^2 - C_i), L in micrometers.
@export var sellmeier_b := Vector3.ZERO
@export var sellmeier_c_um2 := Vector3.ZERO
## Birefringence |delta-n| at 589 nm (0 for cubic minerals). Sign from uniaxial_positive.
@export var birefringence := 0.0
@export var uniaxial_positive := true
## Optic axis in stone space (girdle plane z=0, crown +Z). Corundum cutters
## typically set the table perpendicular to c; tourmaline parallel to c.
@export var optic_axis_stone := Vector3(0.0, 0.0, 1.0)

@export_group("Pure crystal volume")
## Scatter of the flawless crystal (usually ~0; milkiness comes from grade).
@export var base_scatter_per_mm := 0.0
@export var scatter_anisotropy_g := 0.6
## Historical authoring metadata; actual boundary finish belongs to GemSurface.
@export var base_polish_roughness := 0.008

@export_group("Fluorescence")
@export var fluorescence_emission_nm := 0.0
@export var fluorescence_strength := 0.0

@export_group("Wear & structure")
## Mohs hardness is authoring metadata, not a substitute for fracture toughness.
@export var hardness_mohs := 7.0
## Species-typical inclusion vocabulary; no automatic realization is enabled.
@export var inclusions: Array[GemInclusionArchetype] = []
## Growth zoning typical of the species (banding axis in stone space).
@export var zoning_axis := Vector3(0, 0, 1)
@export var zoning_frequency := 0.0
@export var zoning_contrast := 0.0


func ior_at(wl_nm: float) -> float:
	var l2 := (wl_nm * 1e-3) * (wl_nm * 1e-3)
	var s := 1.0
	for index in 3:
		if sellmeier_b[index] != 0.0:
			var denominator := l2 - sellmeier_c_um2[index]
			if absf(denominator) < 1e-12:
				return NAN
			s += sellmeier_b[index] * l2 / denominator
	return sqrt(s) if s > 0.0 else NAN

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not sellmeier_b.is_finite() or not sellmeier_c_um2.is_finite():
		errors.append("Refraction coefficients must be finite")
	if not refraction_range_nm.is_finite() or refraction_range_nm.x > 380.0 or refraction_range_nm.y < 780.0:
		errors.append("Refraction model does not cover the transport interval")
	for index in 3:
		if sellmeier_b[index] != 0.0 and sellmeier_c_um2[index] >= 0.38 * 0.38 and sellmeier_c_um2[index] <= 0.78 * 0.78:
			errors.append("Sellmeier pole lies inside the transport interval")
	for wavelength in range(380, 781, 5):
		var value := ior_at(wavelength)
		if not is_finite(value) or value < 1.0:
			errors.append("Invalid visible dielectric refractive index")
			break
	if not is_finite(birefringence) or birefringence < 0.0 or not optic_axis_stone.is_finite() or (birefringence > 0.0 and optic_axis_stone.length_squared() < 1e-12):
		errors.append("Invalid crystal optical axis or birefringence")
	if not is_finite(base_scatter_per_mm) or base_scatter_per_mm < 0.0 or not is_finite(scatter_anisotropy_g) or absf(scatter_anisotropy_g) >= 1.0:
		errors.append("Invalid species scattering")
	if refraction_evidence == null:
		errors.append("Refraction evidence descriptor is missing")
	else:
		errors.append_array(refraction_evidence.validate())
	return errors
