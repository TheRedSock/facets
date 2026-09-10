class_name GemLighting
extends RefCounted
## Atomic transport input: light records and their shared spectrum table, plus
## background and the print's independent as-shot white. Offsets never cross rigs.
var lights := PackedFloat32Array()
var spectra := PackedFloat32Array()
var background := Vector4.ZERO # zenith, horizon, below, spectrum offset
var white_xyz := Vector3.ZERO # zero = no chromatic adaptation

func validate() -> String:
	if lights.size() % 8 != 0 or lights.size() > 64 or spectra.is_empty() or spectra.size() % 401 != 0:
		return "Invalid light/spectrum buffer size"
	for value in spectra:
		if not is_finite(value) or value < 0.0:
			return "Spectrum contains invalid radiance"
	for value in lights:
		if not is_finite(value):
			return "Light contains a nonfinite value"
	for offset in range(0, lights.size(), 8):
		if not _valid_offset(lights[offset + 4]) or lights[offset + 5] < 0.0:
			return "Invalid light spectrum offset or power"
		if lights[offset + 7] < 0.0 or lights[offset + 7] > 4.0 or lights[offset + 7] != floorf(lights[offset + 7]):
			return "Invalid light role"
	if not background.is_finite() or minf(background.x, minf(background.y, background.z)) < 0.0 or not _valid_offset(background.w):
		return "Invalid background"
	if not white_xyz.is_finite() or (white_xyz != Vector3.ZERO and (white_xyz.y <= 0.0 or white_xyz.x < 0.0 or white_xyz.z < 0.0)):
		return "Invalid print neutral"
	return ""

func _valid_offset(value: float) -> bool:
	return is_finite(value) and value == floorf(value) and value >= 0.0 and int(value) % 401 == 0 and value + 401 <= spectra.size()

func add_spectrum(values: PackedFloat32Array) -> int:
	assert(values.size() == 401)
	for offset in range(0, spectra.size(), 401):
		if spectra.slice(offset, offset + 401) == values:
			return offset
	var offset := spectra.size()
	spectra.append_array(values)
	return offset

## Analytic physics fixtures: records contain Planck kelvin at slot4 (0=flat).
## Converts to the same sampled IR as authored rigs; no alternate GPU backend.
static func analytic(records: PackedFloat32Array, gradient := Vector4.ZERO) -> GemLighting:
	var result := GemLighting.new()
	result.lights = records.duplicate()
	assert(records.size() % 8 == 0)
	for offset in range(0, records.size(), 8):
		result.lights[offset + 4] = result.add_spectrum(_analytic_spectrum(records[offset + 4]))
	result.background = Vector4(gradient.x, gradient.y, gradient.z, result.add_spectrum(_analytic_spectrum(gradient.w)))
	return result

static func _analytic_spectrum(kelvin: float) -> PackedFloat32Array:
	var recipe := GemSpectrum.new()
	recipe.model = GemSpectrum.Model.EQUAL_ENERGY if kelvin == 0.0 else GemSpectrum.Model.BLACKBODY
	recipe.temperature_kelvin = kelvin
	recipe.normalization = GemSpectrum.Normalization.AT_560_NM
	return GemSpectrumCompiler.compile(recipe)
