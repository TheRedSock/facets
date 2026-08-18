class_name GemChromophore
extends Resource
## Why ruby is not sapphire: the coloring agent as spectral absorption.
## Applied to a species; never contains lattice physics.

@export var chromophore_id: StringName
@export var display_name := ""
## Citation / derivation note for the absorption curve.
@export var source_note := ""

## Absorption alpha(lambda) per mm at reference concentration.
## 81 samples, 380..780 nm at 5 nm steps. Empty = colorless.
@export var absorption_mm := PackedFloat32Array()
## Concentration multiplier applied to the curve.
@export var concentration := 1.0

## Pleochroism: optional e-ray absorption curve (same sampling). Mixed by
## ray angle against the optic axis. Empty = isotropic absorption.
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
