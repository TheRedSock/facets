class_name GemSpectrumCompiler
extends RefCounted
## One compiled spectrum is 401 nonnegative finite radiance samples, 380..780 nm.
static var _cache: Dictionary = {}
const CACHE_LIMIT := 64

static func validate(recipe: GemSpectrum) -> String:
	if recipe == null:
		return "Spectrum is missing"
	if recipe.model < 0 or recipe.model > GemSpectrum.Model.SAMPLED:
		return "Unknown spectrum model"
	if recipe.normalization < 0 or recipe.normalization > GemSpectrum.Normalization.UNIT_LUMINANCE:
		return "Unknown spectrum normalization"
	if recipe.model == GemSpectrum.Model.BLACKBODY and (not is_finite(recipe.temperature_kelvin) or recipe.temperature_kelvin < 500.0 or recipe.temperature_kelvin > 100000.0):
		return "Blackbody temperature must be 500..100000 K"
	if recipe.model == GemSpectrum.Model.SAMPLED:
		if not is_finite(recipe.wavelength_start_nm) or not is_finite(recipe.wavelength_step_nm) or recipe.wavelength_step_nm < 1.0 or recipe.samples.size() < 2 or recipe.samples.size() > 10000:
			return "Sampled spectrum requires a finite uniform grid, step >= 1 nm, and 2..10000 samples"
		for value in recipe.samples:
			if not is_finite(value) or value < 0.0:
				return "Spectral radiance must be finite and nonnegative"
	return ""

static func compile(recipe: GemSpectrum) -> PackedFloat32Array:
	var error := validate(recipe)
	if not error.is_empty():
		push_error(error)
		return PackedFloat32Array()
	var key := GemContentIdentity.digest([recipe.model, recipe.temperature_kelvin,
		recipe.wavelength_start_nm, recipe.wavelength_step_nm, recipe.samples, recipe.normalization])
	if _cache.has(key):
		return _cache[key].duplicate()
	var values := PackedFloat32Array()
	for index in 401:
		var wavelength := 380.0 + index
		var value := 1.0
		match recipe.model:
			GemSpectrum.Model.BLACKBODY:
				value = GemColorimetry.planck_rel(wavelength, recipe.temperature_kelvin)
			GemSpectrum.Model.CIE_D65:
				value = GemStandardSpectra.daylight(wavelength)
			GemSpectrum.Model.SAMPLED:
				var position := (wavelength - recipe.wavelength_start_nm) / recipe.wavelength_step_nm
				value = 0.0
				if position >= 0.0 and position <= recipe.samples.size() - 1:
					var first := int(position)
					value = lerpf(recipe.samples[first], recipe.samples[mini(first + 1, recipe.samples.size() - 1)], position - first)
		values.append(value)
	var scale := 1.0
	match recipe.normalization:
		GemSpectrum.Normalization.AT_560_NM:
			scale = values[180]
		GemSpectrum.Normalization.UNIT_LUMINANCE:
			scale = GemColorimetry.spectrum_xyz(values).y
	if not is_finite(scale) or scale <= 0.0:
		push_error("Spectrum has no energy at the requested normalization")
		return PackedFloat32Array()
	for index in values.size():
		values[index] /= scale
		if not is_finite(values[index]):
			push_error("Normalized spectrum exceeds float32 range")
			return PackedFloat32Array()
	if _cache.size() >= CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	_cache[key] = values.duplicate()
	return values
