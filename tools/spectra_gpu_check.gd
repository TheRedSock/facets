extends SceneTree
## CPU/GPU agreement for standard daylight, thermal and measured-like spectra.
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func mean_xyz(values: PackedFloat32Array) -> Vector3:
	var total := Vector3.ZERO
	var coverage := 0.0
	for pixel in values.size() / 4:
		total += Vector3(values[pixel * 4], values[pixel * 4 + 1], values[pixel * 4 + 2])
		coverage += values[pixel * 4 + 3]
	return total / maxf(coverage, 1.0)

func _initialize() -> void:
	var tracer := GemTracer.create(48, 48)
	if tracer == null:
		print("CHECK_COMPLETE: spectra_gpu_check"); quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres")
	var specimen := LapidaryStoneCompiler.compile(stone)
	specimen["sellmeier_b"] = Vector3.ZERO
	specimen["sellmeier_c"] = Vector3.ZERO
	specimen["extraordinary_refraction"] = {}
	specimen["absorption"].fill(0.0)
	specimen["absorption_eray"] = PackedFloat32Array()
	specimen["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	specimen["zoning"] = {}
	var policy := GemRung.policy(GemRung.REFERENCE)
	var recipe := GemSpectrum.new()
	var rig := GemLightRig.new()
	rig.bg_zenith = 1.0
	rig.bg_horizon = 1.0
	rig.bg_below = 1.0
	rig.background_spectrum = recipe
	for model in [GemSpectrum.Model.EQUAL_ENERGY, GemSpectrum.Model.CIE_D65, GemSpectrum.Model.BLACKBODY, GemSpectrum.Model.SAMPLED]:
		recipe.model = model
		recipe.temperature_kelvin = 2856.0
		recipe.wavelength_step_nm = 50.0
		recipe.samples = PackedFloat32Array([0.05, 0.1, 1.7, 0.2, 0.01, 0.5, 1.0, 0.1, 0.02])
		var lighting := GemRigCompiler.compile(rig)
		tracer.configure_stone(specimen, lighting, policy)
		tracer.accumulate(128)
		var expected := GemColorimetry.spectrum_xyz(GemSpectrumCompiler.compile(recipe))
		var actual := mean_xyz(tracer.read_xyz())
		check(actual.distance_to(expected) < 0.003, "background spectrum %d XYZ agrees: %s vs %s" % [model, actual, expected])
		var film := tracer.read_xyz()
		lighting.white_xyz = expected / expected.y
		tracer.set_lighting(lighting)
		check(tracer.samples_accumulated == 128 and tracer.read_xyz() == film, "neutral-only lighting update retains optical film")
	# Replace a multi-SPD rig with a smaller table and different background offset.
	var studio: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	tracer.set_lighting(GemRigCompiler.compile(studio))
	check(tracer.samples_accumulated == 0, "light change retires incompatible samples")
	tracer.accumulate(4)
	recipe.model = GemSpectrum.Model.CIE_D65
	tracer.set_lighting(GemRigCompiler.compile(rig))
	tracer.accumulate(128)
	check(mean_xyz(tracer.read_xyz()).distance_to(GemColorimetry.spectrum_xyz(GemSpectrumCompiler.compile(recipe))) < 0.003, "SPD table replacement leaves no stale offsets")
	# Light-cone spectrum follows the same table as background; make a cone
	# covering every unbent camera ray in this index-matched fixture.
	rig.bg_zenith = 0.0
	rig.bg_horizon = 0.0
	rig.bg_below = 0.0
	var light := GemRigLight.new()
	light.azimuth_deg = 180.0
	light.angular_radius_deg = 45.0
	light.elevation_deg = 0.0
	light.spectrum = recipe
	rig.lights = [light]
	tracer.set_lighting(GemRigCompiler.compile(rig))
	tracer.accumulate(128)
	check(mean_xyz(tracer.read_xyz()).distance_to(GemColorimetry.spectrum_xyz(GemSpectrumCompiler.compile(recipe))) < 0.003, "light-cone emission uses the compiled SPD")
	_absorption_band(tracer, specimen, policy)
	tracer.release()
	print("GPU spectra: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: spectra_gpu_check"); quit(1 if failures else 0)

func _absorption_band(tracer: GemTracer, specimen: Dictionary, policy: Dictionary) -> void:
	var material := GemMaterial.new()
	material.species = GemSpecies.new() # index-matched analytical slab
	material.absorbers = [GemAbsorber.relative(GemChromophore.new())]
	material.absorbers[0].chromophore.wavelength_step_nm = 1.0
	material.absorbers[0].chromophore.absorption_mm.resize(401)
	material.absorbers[0].chromophore.absorption_mm[182] = 1.0 # 562 nm: missed by the old 5 nm grid
	var bulk := GemMaterialCompiler.compile(material)
	specimen["absorption"] = bulk["absorption"]
	specimen["planes"] = PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var normal: Vector3 = axis * sign_value
			specimen["planes"].append_array(PackedFloat32Array([normal.x, normal.y, normal.z, 1, 0, 0, 0, 0]))
	var rig := GemLightRig.new()
	rig.background_spectrum.model = GemSpectrum.Model.CIE_D65
	rig.bg_zenith = 1.0
	rig.bg_horizon = 1.0
	rig.bg_below = 1.0
	var lighting := GemRigCompiler.compile(rig)
	tracer.configure_stone(specimen, lighting, policy)
	tracer.accumulate(256)
	var expected := Vector3.ZERO
	var emission := GemSpectrumCompiler.compile(rig.background_spectrum)
	for sample_index in 1600:
		var wavelength := 380.0 + (sample_index + 0.5) * 0.25
		var index := int(wavelength - 380.0)
		var fraction := wavelength - 380.0 - index
		var alpha := lerpf(specimen["absorption"][index], specimen["absorption"][index + 1], fraction)
		var radiance := lerpf(emission[index], emission[index + 1], fraction)
		expected += GemStandardSpectra.xyz(wavelength) * radiance * exp(-alpha * 2.0 * float(specimen["size_mm"])) * 0.25
	expected /= GemColorimetry.integral_ybar()
	var actual := mean_xyz(tracer.read_xyz())
	check(actual.distance_to(expected) < 0.0015, "1 nm absorption band agrees with independent slab quadrature: %s vs %s" % [actual, expected])
	check(actual.y < 0.99, "sub-5 nm absorption feature measurably reaches transport")
