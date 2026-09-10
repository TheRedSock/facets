class_name GemChromophore
extends Resource
## Why ruby is not sapphire: the coloring agent as spectral absorption.
## Applied to a species; never contains lattice physics.

@export var chromophore_id: StringName
@export var display_name := ""
## Citation / derivation note for the absorption curve.
@export var source_note := ""
@export var absorption_evidence: GemOpticalEvidence = GemOpticalEvidence.new()

## Absorption alpha(lambda) per mm at reference concentration.
## Uniform source grid; the compiler resamples to the 1 nm transport grid.
## The catalog's authored approximations use 81 samples at 5 nm. Empty=colorless.
@export var wavelength_start_nm := 380.0
@export var wavelength_step_nm := 5.0
@export var absorption_mm := PackedFloat32Array()
## A measured cross section is a different quantity from absorption /mm.
## Exactly one basis is populated; concentrations belong to material terms.
enum SpectrumBasis { COEFFICIENT_PER_MM, CROSS_SECTION_CM2 }
@export var basis := SpectrumBasis.COEFFICIENT_PER_MM
@export var cross_section_cm2 := PackedFloat64Array()
@export var cross_section_parallel_cm2 := PackedFloat64Array()
## Cross sections are specific to an absorber AND its host lattice.
@export var host_species_id: StringName

## Optional principal parallel-axis absorption curve (same sampling).
## The polarized isotropic-real-index renderer propagates its weak-loss tensor
## with persistent polarization; scalar transport uses the legacy directional
## mixture. Empty = isotropic absorption. Authored curves are not measurements.
@export var absorption_eray_mm := PackedFloat32Array()

## Fluorescence belongs to the coloring ion, not the lattice: Cr3+ glows red
## in corundum AND beryl; Fe quenches it (blue sapphire). Override < 0 =
## inherit the species value; >= 0 replaces it. nm 0 = inherit.
@export var fluorescence_strength_override := -1.0
@export var fluorescence_emission_nm_override := 0.0

## UI chrome ONLY (tile tinting in menus etc.). Never enters transport.
@export var ui_color := Color.WHITE


func is_colorless() -> bool:
	return absorption_mm.is_empty() and cross_section_cm2.is_empty()

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if basis not in [SpectrumBasis.COEFFICIENT_PER_MM, SpectrumBasis.CROSS_SECTION_CM2]:
		errors.append("Unknown absorption spectrum basis")
	if basis == SpectrumBasis.COEFFICIENT_PER_MM and (not cross_section_cm2.is_empty() or not cross_section_parallel_cm2.is_empty()):
		errors.append("Coefficient spectra cannot also contain cross sections")
	if basis == SpectrumBasis.CROSS_SECTION_CM2:
		if not absorption_mm.is_empty() or not absorption_eray_mm.is_empty() or cross_section_cm2.is_empty() or host_species_id.is_empty():
			errors.append("Cross sections require their host species and an exclusive nonempty cross-section basis")
	if not is_finite(wavelength_start_nm) or not is_finite(wavelength_step_nm) or wavelength_step_nm <= 0.0:
		errors.append("Invalid absorption wavelength grid")
	for curve in [absorption_mm, absorption_eray_mm, cross_section_cm2, cross_section_parallel_cm2]:
		if not curve.is_empty() and (curve.size() < 2 or curve.size() > 10000 or wavelength_start_nm > 380.0 or wavelength_start_nm + wavelength_step_nm * (curve.size() - 1) < 780.0):
			errors.append("Absorption data must cover the complete 380..780 nm transport interval")
		for value in curve:
			if not is_finite(value) or value < 0.0:
				errors.append("Absorption coefficients must be finite and nonnegative")
	if not absorption_eray_mm.is_empty() and absorption_eray_mm.size() != absorption_mm.size():
		errors.append("Ordinary and extraordinary absorption must share the same source grid")
	if not cross_section_parallel_cm2.is_empty() and cross_section_parallel_cm2.size()!=cross_section_cm2.size():
		errors.append("Principal cross sections must share the source grid")
	if absorption_evidence == null:
		errors.append("Absorption evidence descriptor is missing")
	else:
		errors.append_array(absorption_evidence.validate())
	return errors

## Principal absorption axes are aligned with the material's host crystal frame.
func has_parallel_curve() -> bool:
	return not (absorption_eray_mm.is_empty() if basis==SpectrumBasis.COEFFICIENT_PER_MM else cross_section_parallel_cm2.is_empty())

func sample(wavelength_nm: float, parallel := false) -> float:
	if not is_finite(wavelength_nm) or not is_finite(wavelength_step_nm) or wavelength_step_nm <= 0.0:
		return NAN
	var values: Variant
	if basis==SpectrumBasis.COEFFICIENT_PER_MM:
		values=absorption_eray_mm if parallel and not absorption_eray_mm.is_empty() else absorption_mm
	else:
		values=cross_section_parallel_cm2 if parallel and not cross_section_parallel_cm2.is_empty() else cross_section_cm2
	if values.is_empty():return 0.0
	var position: float=(wavelength_nm-wavelength_start_nm)/wavelength_step_nm
	if position < 0.0 or position > values.size()-1:
		return NAN # Explicit source domain: never silently extrapolate a spectrum.
	var first:=clampi(int(position),0,values.size()-1)
	return lerpf(values[first],values[mini(first+1,values.size()-1)],position-first)
