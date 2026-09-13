extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var unpolarized := PackedFloat64Array([1, 0, 0, 0])
	var brewster := GemPolarization.apply(GemPolarization.dielectric(cos(atan(1.5)), 1.0 / 1.5), unpolarized)
	check(absf(brewster[0] - brewster[1]) < 1e-12 and brewster[0] > 0.05, "Brewster reflection is fully s-polarized")
	var half := GemPolarization.diattenuator(exp(-0.1), exp(-1.0))
	var twice := GemPolarization.apply(GemPolarization.multiply(half, half), unpolarized)
	var whole := GemPolarization.apply(GemPolarization.diattenuator(exp(-0.2), exp(-2.0)), unpolarized)
	check(absf(twice[0] - whole[0]) < 1e-12, "dichroic attenuation composes without resetting polarization")
	check(absf(twice[0] - pow(0.5 * (exp(-0.1) + exp(-1.0)), 2)) > 0.05, "fresh unpolarized averaging at each segment gives a materially wrong result")
	var crossed := GemPolarization.multiply(GemPolarization.diattenuator(1, 0), GemPolarization.multiply(GemPolarization.rotation(PI * 0.5), GemPolarization.diattenuator(1, 0)))
	check(absf(GemPolarization.apply(crossed, unpolarized)[0]) < 1e-12, "crossed ideal linear polarizers extinguish light")
	for index in 80:
		var eta := 0.4 + index * 0.027
		var cosine := 0.01 + index / 81.0
		var polarization := Vector3(sin(index * 0.7), cos(index * 0.4), sin(index * 0.3)).normalized() * 0.9
		var state := PackedFloat64Array([1, polarization.x, polarization.y, polarization.z])
		var r := GemPolarization.apply(GemPolarization.dielectric(cosine, eta), state)
		var t := GemPolarization.apply(GemPolarization.dielectric(cosine, eta, true), state)
		check(absf(r[0] + t[0] - 1.0) < 1e-12, "dielectric conserves flux for polarized input")
		for output in [r, t]:
			check(output[0] + 1e-8 >= sqrt(output[1] * output[1] + output[2] * output[2] + output[3] * output[3]), "Mueller output remains a physical Stokes vector")
	var tir := GemPolarization.apply(GemPolarization.dielectric(0.5, 1.5), PackedFloat64Array([1, 0, 1, 0]))
	check(absf(tir[3]) > 0.6 and absf(tir[0] - 1.0) < 1e-12, "TIR retains flux and converts linear to elliptical polarization")
	var quartz:=LapidaryStoneCompiler.compile(load("res://data/lapidary/stones/quartz.tres"))
	var tracer:=GemTracer.new()
	var lighting:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	check(not tracer.configure_stone(quartz,lighting,{"polarization":true}) and "isotropic real refraction" in tracer.configuration_error,"reject unsupported polarized host before device access")
	var diamond:=LapidaryStoneCompiler.compile(load("res://data/lapidary/stones/diamond.tres"))
	diamond["region_materials"]=[quartz]
	check(not tracer.configure_stone(diamond,lighting,{"polarization":true}) and "isotropic real refraction" in tracer.configuration_error,"reject unsupported nested polarized material before device access")
	print("Polarization: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_polarization"); quit(1 if failures else 0)
