class_name GemSpecies
extends Resource
## Lattice physics of a mineral species. Shared by every stone of that mineral
## (ruby and sapphire share corundum). No color here — color is the chromophore.

@export var species_id: StringName
@export var display_name := ""
## Citation for the optical constants (journal / refractiveindex.info page).
@export var source_note := ""

@export_group("Refraction")
## 3-term Sellmeier, ordinary ray: n^2 - 1 = sum B_i * L^2 / (L^2 - C_i), L in micrometers.
@export var sellmeier_b := Vector3.ZERO
@export var sellmeier_c_um2 := Vector3.ZERO
## Birefringence delta-n at 589 nm (0 for cubic minerals).
@export var birefringence := 0.0
@export var uniaxial_positive := true

@export_group("Pure crystal volume")
## Scatter of the flawless crystal (usually ~0; milkiness comes from grade).
@export var base_scatter_per_mm := 0.0
@export var scatter_anisotropy_g := 0.6
## GGX roughness of a fresh polish on this mineral (hardness-informed).
@export var base_polish_roughness := 0.008

@export_group("Fluorescence")
@export var fluorescence_emission_nm := 0.0
@export var fluorescence_strength := 0.0

@export_group("Wear & structure")
## Mohs hardness — shapes wear statistics (soft stones scratch broad/shallow).
@export var hardness_mohs := 7.0
## Species-typical inclusion vocabulary; grade decides how much of it appears.
@export var inclusions: Array[GemInclusionArchetype] = []
## Growth zoning typical of the species (banding axis in stone space).
@export var zoning_axis := Vector3(0, 0, 1)
@export var zoning_frequency := 0.0
@export var zoning_contrast := 0.0


func ior_at(wl_nm: float) -> float:
	var l2 := (wl_nm * 1e-3) * (wl_nm * 1e-3)
	var s := 1.0
	if sellmeier_c_um2.x > 0.0 or sellmeier_b.x > 0.0:
		s += sellmeier_b.x * l2 / (l2 - sellmeier_c_um2.x)
	if sellmeier_b.y > 0.0:
		s += sellmeier_b.y * l2 / (l2 - sellmeier_c_um2.y)
	if sellmeier_b.z > 0.0:
		s += sellmeier_b.z * l2 / (l2 - sellmeier_c_um2.z)
	return sqrt(maxf(s, 1.0))
