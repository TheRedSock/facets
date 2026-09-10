extends SceneTree
const Modes := preload("res://core/lapidary/crystal_modes.gd")
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var cases: Array[Dictionary] = []
	var normal := Modes.vec(0, 0, 1)
	for indices in [[1.5, 1.5], [1.5, 1.7], [1.7, 1.5], [1.544, 1.553]]:
		for orientation in 13:
			var axis := Modes.unit(Modes.vec(sin(orientation * 0.7), sin(orientation * 1.1), cos(orientation * 0.3)))
			for sample in 11:
				var kx := sample * 0.21
				var tangent := Modes.vec(kx, 0, 0)
				for side in [-1, 1]:
					var modes := Modes.modes(indices[0], indices[1], axis, normal, tangent, side)
					check(modes.size() == 2, "ordinary and extraordinary boundary modes exist")
					for mode in modes:
						check(Modes.maxwell_residual(mode, indices[0], indices[1], axis) < 1e-10, "mode solves Maxwell equations")
						check(absf(mode.k_real[0] - kx) < 1e-12 and absf(mode.k_real[1]) < 1e-12, "tangential phase is conserved")
						if mode.evanescent:
							check(side * mode.q[1] > 0 and absf(mode.normal_flux) < 1e-10, "evanescent mode decays outward without normal energy transport")
						else:
							check(side * mode.normal_flux >= -1e-12, "mode energy propagates into selected half-space")
							var predicted: PackedFloat64Array = Modes.metric(mode.k_real, axis, indices[0], indices[1]) if mode.extraordinary else mode.k_real
							check(Modes.dot(mode.ray, Modes.unit(predicted)) > 1.0 - 1e-12, "Poynting direction matches dispersion gradient")
					cases.append({"no": indices[0], "ne": indices[1], "axis": Array(axis), "kx": kx, "side": side, "modes": modes})
	var split := Modes.modes(1.5, 1.7, Modes.vec(0.4, 0.5, 0.8), normal, Modes.vec(0.6, 0, 0), 1)
	check(absf(split[1].ray[1]) > 0.01 and absf(split[0].ray[1]) < 1e-12, "extraordinary energy can leave the incidence plane")
	check(Modes.modes(0, 1.5, normal, normal, Modes.vec(0, 0, 0), 1).is_empty(), "invalid index rejected")
	check(Modes.modes(1.5, 1.6, normal, normal, Modes.vec(0, 0, 0.1), 1).is_empty(), "non-tangent boundary input rejected")
	var rotation_axis := Modes.unit(Modes.vec(0.4, 0.7, -0.2))
	var optic := Modes.unit(Modes.vec(0.3, -0.4, 0.8))
	var tangent := Modes.vec(0.6, 0, 0)
	var original := Modes.modes(1.5, 1.7, optic, normal, tangent, 1)
	for step in 17:
		var angle := step * 0.37
		var rotated := Modes.modes(1.5, 1.7, rotate(optic, rotation_axis, angle), rotate(normal, rotation_axis, angle), rotate(tangent, rotation_axis, angle), 1)
		check(rotated.size() == 2, "arbitrary boundary normal supports both modes")
		for mode in 2:
			var expected := rotate(original[mode].ray, rotation_axis, angle)
			check(Modes.dot(expected, rotated[mode].ray) > 1 - 1e-12, "mode ray transforms covariantly in world space")
	GemArtifactStore.atomic_write("res://artifacts/reference/crystal-modes.json", JSON.stringify(cases).to_utf8_buffer())
	print("Crystal modes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

static func rotate(value: PackedFloat64Array, axis: PackedFloat64Array, angle: float) -> PackedFloat64Array:
	return Modes.add(Modes.add(Modes.scale(value, cos(angle)), Modes.scale(Modes.cross(axis, value), sin(angle))), Modes.scale(axis, Modes.dot(axis, value) * (1 - cos(angle))))
