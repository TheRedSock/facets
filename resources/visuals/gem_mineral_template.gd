class_name GemMineralTemplate extends Resource

## Unique identifier for this mineral species.
@export var mineral_id: StringName = &""

## Human-readable name (e.g., "Corundum (Al₂O₃)").
@export var mineral_name: String = ""

## Sellmeier dispersion coefficients.
## n²(λ) = 1 + B1·λ²/(λ²-C1) + B2·λ²/(λ²-C2) + B3·λ²/(λ²-C3)
## B values are dimensionless. C values are in μm².
@export var sellmeier_b: Vector3 = Vector3(0.696, 0.408, 0.898)
@export var sellmeier_c: Vector3 = Vector3(0.00468, 0.01351, 97.934)

## Absorption spectrum: extinction coefficient at 5nm intervals, 380-780nm.
## 81 float values. Units: per model-space-unit.
## Empty = fully transparent mineral (no inherent absorption).
## For minerals with multiple chromophore variants (e.g., corundum → sapphire, ruby),
## this is the BASE absorption of the pure mineral. Per-gem absorption overrides are
## on the GemVisualResource.
@export var absorption_spectrum: PackedFloat32Array = PackedFloat32Array()

## Scattering coefficient (σ_s) in model-space units. 0 = no scattering.
@export_range(0.0, 50.0) var scattering_coefficient: float = 0.0

## Henyey-Greenstein anisotropy parameter.
## 0 = isotropic, positive = forward-scattering, negative = back-scattering.
@export_range(-0.99, 0.99) var scattering_anisotropy: float = 0.0

## Fluorescence: quantum yield (probability of re-emission per absorption event).
@export_range(0.0, 1.0) var fluorescence_quantum_yield: float = 0.0

## Fluorescence excitation band center (nm).
@export_range(300.0, 700.0) var fluorescence_excitation_center_nm: float = 550.0

## Fluorescence excitation band width (nm, Gaussian sigma).
@export_range(5.0, 100.0) var fluorescence_excitation_width_nm: float = 30.0

## Fluorescence emission band center (nm).
@export_range(400.0, 780.0) var fluorescence_emission_center_nm: float = 694.0

## Fluorescence emission band width (nm, Gaussian sigma).
@export_range(5.0, 100.0) var fluorescence_emission_width_nm: float = 15.0

## Birefringence Δn (difference between ordinary and extraordinary refractive indices).
## 0 = isotropic crystal (cubic system: diamond, garnet, fluorite).
@export_range(0.0, 0.2) var birefringence_delta_n: float = 0.0

## Pleochroism: absorption spectrum along the extraordinary axis.
## If empty, absorption is the same in all directions (no pleochroism).
## If provided, the base absorption_spectrum is treated as the ordinary-ray absorption,
## and this is the extraordinary-ray absorption. Actual absorption is interpolated
## based on the angle between the ray direction and the optic axis.
@export var pleochroism_absorption_spectrum: PackedFloat32Array = PackedFloat32Array()

## Default surface roughness (GGX α parameter) for typical polish of this mineral.
## 0.0 = perfect mirror polish, 0.01 = excellent polish, 0.05 = fair, 0.1+ = rough/frosted.
@export_range(0.0, 1.0) var default_surface_roughness: float = 0.01

## Display color for UI / procedural fallback (NOT used in ray transport).
@export var display_color: Color = Color.WHITE


## Compute the Sellmeier IOR at a reference wavelength (589nm sodium D-line).
## Useful for validation and display.
func get_reference_ior() -> float:
	var l := 0.589  # μm
	var l2 := l * l
	var n2 := 1.0 \
		+ sellmeier_b.x * l2 / (l2 - sellmeier_c.x) \
		+ sellmeier_b.y * l2 / (l2 - sellmeier_c.y) \
		+ sellmeier_b.z * l2 / (l2 - sellmeier_c.z)
	return sqrt(max(n2, 1.0))
