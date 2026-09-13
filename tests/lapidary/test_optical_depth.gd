extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	for index in 24:
		var position := Vector3(sin(index * 0.7), cos(index * 0.3), -0.9)
		var direction := Vector3(cos(index * 0.4), sin(index * 0.8), 0.3).normalized()
		var axis := Vector3(0.2, 0.4, 0.7).normalized()
		var frequency := 0.001 if index == 0 else index * 0.71
		var contrast := 0.95
		var phase := index * 0.23
		var length := 0.2 + index * 0.087
		var integral := GemOpticalDepth.zoning_column(position, direction, length, axis, frequency, contrast, phase)
		var quadrature := 0.0
		for sample_index in 4096:
			var t := length * (sample_index + 0.5) / 4096.0
			quadrature += 1.0 + contrast * sin((position + direction * t).dot(axis) * frequency * PI + phase)
		quadrature *= length / 4096.0
		check(absf(integral - quadrature) < 0.00002, "analytic concentration agrees with independent quadrature")
		var split := length * 0.37
		var first := GemOpticalDepth.zoning_column(position, direction, split, axis, frequency, contrast, phase)
		var second := GemOpticalDepth.zoning_column(position + direction * split, direction, length - split, axis, frequency, contrast, phase)
		check(absf(exp(-0.4 * integral) - exp(-0.4 * first) * exp(-0.4 * second)) < 0.000002, "Beer transmittance composes across segmentation")
		var reverse := GemOpticalDepth.zoning_column(position + direction * length, -direction, length, axis, frequency, contrast, phase)
		check(absf(integral - reverse) < 0.000002, "concentration integral is reciprocal (error %.9f, case %d)" % [absf(integral - reverse), index])
	check(absf(GemOpticalDepth.zoning_column(Vector3.ZERO, Vector3.RIGHT, 2.0, Vector3.BACK, 3.0, 1.0, PI * 0.5) - 4.0) < 1e-7, "parallel-to-band limit is finite and exact")
	check(absf(GemOpticalDepth.zoning_column(Vector3(0, 0, 1), Vector3.FORWARD, 2.0, Vector3.BACK, 1.0, 0.8, PI * 0.5) - 2.0) < 1e-6, "one complete concentration period has unit mean")
	print("Optical depth: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_optical_depth"); quit(1 if failures else 0)
