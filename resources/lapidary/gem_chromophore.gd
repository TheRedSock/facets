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
## Concentration multiplier applied to the curve.
@export var concentration := 1.0

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
	return absorption_mm.is_empty()

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(concentration) or concentration < 0.0:
		errors.append("Absorption concentration must be finite and nonnegative")
	if not is_finite(wavelength_start_nm) or not is_finite(wavelength_step_nm) or wavelength_step_nm <= 0.0:
		errors.append("Invalid absorption wavelength grid")
	for curve in [absorption_mm, absorption_eray_mm]:
		if not curve.is_empty() and (curve.size() < 2 or curve.size() > 10000 or wavelength_start_nm > 380.0 or wavelength_start_nm + wavelength_step_nm * (curve.size() - 1) < 780.0):
			errors.append("Absorption data must cover the complete 380..780 nm transport interval")
		for value in curve:
			if not is_finite(value) or value < 0.0:
				errors.append("Absorption coefficients must be finite and nonnegative")
			if value * concentration > 3.4028234e38:
				errors.append("Scaled absorption exceeds the float32 transport range")
	if not absorption_eray_mm.is_empty() and absorption_eray_mm.size() != absorption_mm.size():
		errors.append("Ordinary and extraordinary absorption must share the same source grid")
	if absorption_evidence == null:
		errors.append("Absorption evidence descriptor is missing")
	else:
		errors.append_array(absorption_evidence.validate())
	return errors
