class_name GemSpecies
extends Resource
## Lattice physics of a mineral species. Shared by every stone of that mineral
## (ruby and sapphire share corundum). No color here — color is the chromophore.

@export var species_id: StringName
@export var display_name := ""
## Citation for the optical constants (journal / refractiveindex.info page).
@export var source_note := ""
@export_group("Refraction")
@export var ordinary: GemIndexCurve = GemIndexCurve.new()
## Null means isotropic real refraction. Otherwise both principal spectra
## are explicit. Biaxial approximations must be identified in the evidence.
@export var extraordinary: GemIndexCurve
## Optic axis in stone space (girdle plane z=0, crown +Z). Corundum cutters
## typically set the table perpendicular to c; tourmaline parallel to c.
@export var optic_axis_stone := Vector3(0.0, 0.0, 1.0)

@export_group("Wear & structure")
## Mohs hardness is authoring metadata, not a substitute for fracture toughness.
@export var hardness_mohs := 7.0



func ior_at(wl_nm: float) -> float:
	return ordinary.at(wl_nm) if ordinary != null else NAN

func extraordinary_ior_at(wl_nm: float) -> float:
	return extraordinary.at(wl_nm) if extraordinary != null else ior_at(wl_nm)

func birefringence_at(wl_nm: float) -> float:
	return extraordinary_ior_at(wl_nm) - ior_at(wl_nm)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if ordinary == null:
		errors.append("Ordinary principal index is missing")
	else:
		errors.append_array(ordinary.validate())
	if extraordinary != null:
		errors.append_array(extraordinary.validate())
	if not optic_axis_stone.is_finite() or (extraordinary != null and optic_axis_stone.length_squared() < 1e-12):
		errors.append("Invalid crystal optical axis")
	return errors
