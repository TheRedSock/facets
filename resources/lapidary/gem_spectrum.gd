class_name GemSpectrum
extends Resource
## Emission spectrum recipe. Power is a separate light/gradient parameter.
## Samples describe relative radiance on a uniform wavelength grid in nanometers.
## The transport compiler resamples onto 380..780 nm at 1 nm; narrower features
## than this grid require a finer transport representation, not larger amplitudes.
enum Model { EQUAL_ENERGY, BLACKBODY, CIE_D65, SAMPLED }
enum Normalization { NONE, AT_560_NM, UNIT_LUMINANCE }

@export var model := Model.BLACKBODY
@export var temperature_kelvin := 5500.0
@export var wavelength_start_nm := 380.0
@export var wavelength_step_nm := 1.0
@export var samples := PackedFloat32Array()
## NONE preserves input scale. UNIT_LUMINANCE gives the same observer-weighted
## Y as unit equal-energy light. AT_560_NM requires nonzero radiance at 560 nm.
@export var normalization := Normalization.UNIT_LUMINANCE
@export_multiline var source_note := ""
