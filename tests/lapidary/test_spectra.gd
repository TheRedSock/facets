extends SceneTree
## Independent standard-data anchors, spectral units, and recipe isolation.
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	# Publisher metadata validation sample and sums, not another analytic fit.
	check(GemStandardSpectra.xyz(479).distance_to(Vector3(0.1042979, 0.1334528, 0.8566193)) < 1e-7, "CIE publisher observer anchor")
	var sum := Vector3.ZERO
	for wavelength in range(360, 831):
		sum += GemStandardSpectra.xyz(wavelength)
	check(sum.distance_to(Vector3(106.86546949, 106.85691710, 106.89225128)) < 0.0003, "CIE full observer column sums")
	check(absf(GemStandardSpectra.daylight(419) - 0.932372) < 1e-7, "CIE D65 publisher anchor")
	check(GemStandardSpectra.xyz(359) == Vector3.ZERO and GemStandardSpectra.daylight(831) == 0.0, "standard extrapolation is zero")
	check(GemStandardSpectra.xyz(479.5).distance_to((GemStandardSpectra.xyz(479) + GemStandardSpectra.xyz(480)) * 0.5) < 1e-7, "standard linear interpolation")
	var recipe := GemSpectrum.new()
	recipe.model = GemSpectrum.Model.CIE_D65
	var daylight := GemSpectrumCompiler.compile(recipe)
	var xyz := GemColorimetry.spectrum_xyz(daylight)
	check(absf(xyz.y - 1.0) < 2e-6, "unit-luminance normalization")
	check((xyz / xyz.y).distance_to(GemColorimetry.D65_XYZ) < 0.0003, "integrated D65 agrees with standard white within visible truncation")
	var rgb := GemColorimetry.xyz_to_srgb(xyz) * xyz
	check(rgb.distance_to(Vector3.ONE) < 0.0003, "actual spectral neutral adapts to D65 sRGB")
	recipe.model = GemSpectrum.Model.BLACKBODY
	recipe.temperature_kelvin = 6500.0
	var thermal := GemSpectrumCompiler.compile(recipe)
	check(GemColorimetry.spectrum_xyz(thermal).distance_to(xyz) > 0.02, "6500 K blackbody is distinct from D65 daylight")
	recipe.model = GemSpectrum.Model.SAMPLED
	recipe.wavelength_start_nm = 380.0
	recipe.wavelength_step_nm = 200.0
	recipe.samples = PackedFloat32Array([0, 2, 0])
	recipe.normalization = GemSpectrum.Normalization.NONE
	var sampled := GemSpectrumCompiler.compile(recipe)
	check(sampled[0] == 0 and sampled[100] == 1 and sampled[200] == 2 and sampled[400] == 0, "sampled radiance scale and interpolation")
	sampled[200] = 99.0
	check(GemSpectrumCompiler.compile(recipe)[200] == 2, "callers cannot mutate the spectrum cache")
	recipe.samples[1] = 4.0
	check(GemSpectrumCompiler.compile(recipe)[200] == 4, "resource edits invalidate compiled spectral values")
	recipe.samples[1] = -1.0
	check(not GemSpectrumCompiler.validate(recipe).is_empty(), "negative radiance rejected")
	recipe.samples[1] = NAN
	check(not GemSpectrumCompiler.validate(recipe).is_empty(), "nonfinite radiance rejected")
	var rig: GemLightRig = load("res://data/lapidary/rigs/reference_daylight.tres")
	var lighting := GemRigCompiler.compile(rig)
	check(lighting.validate().is_empty() and lighting.spectra.size() == 401, "reference rig shares one genuine D65 spectrum")
	check(lighting.white_xyz.distance_to(xyz) < 2e-6, "reference neutral comes from its spectrum")
	lighting.background.w = 1.0
	check(not lighting.validate().is_empty(), "unaligned spectral offset rejected")
	_factory_identity()
	print("Spectra: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_spectra"); quit(1 if failures else 0)

func _factory_identity() -> void:
	var job := GemFrameJob.new()
	job.stone = load("res://data/lapidary/stones/quartz.tres")
	job.rig = load("res://data/lapidary/rigs/gameplay_studio.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.print_style = GemPrint.load_house()
	job.quality = GemRung.policy(GemRung.INTERACT)
	var original := GemFramePlan.master_key(job)
	var display := GemFramePlan.display_key(job)
	job.rig.white_spectrum = GemSpectrum.new()
	job.rig.white_spectrum.model = GemSpectrum.Model.CIE_D65
	check(GemFramePlan.master_key(job) == original and GemFramePlan.display_key(job) != display, "white-only edit reuses optical master")
	job.rig.lights[0].spectrum = GemSpectrum.new()
	job.rig.lights[0].spectrum.model = GemSpectrum.Model.CIE_D65
	check(GemFramePlan.master_key(job) != original, "light SPD changes optical identity")
	original = GemFramePlan.master_key(job)
	job.rig.background_spectrum = GemSpectrum.new()
	job.rig.background_spectrum.model = GemSpectrum.Model.EQUAL_ENERGY
	check(GemFramePlan.master_key(job) != original, "background SPD changes optical identity")
