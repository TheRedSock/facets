extends SceneTree
const V := preload("res://core/lapidary/crystal_modes.gd")
const Loss := preload("res://core/lapidary/crystal_loss.gd")
const Packet := preload("res://core/lapidary/crystal_packet.gd")
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var normal := V.vec(0, 0, 1)
	var cases := []
	for index in 120:
		var no := 1.5
		var ne := 1.8 if index % 2 else 1.3
		var axis := V.unit(V.vec(sin(index * 0.7), cos(index * 0.4), 0.3))
		var tangent := V.vec(0.9 * sin(index * 0.3), 0, 0)
		var ao := 0.1 + (index % 7) * 0.35
		var ae := 0.2 + (index % 11) * 0.27
		for mode in V.modes(no, ne, axis, normal, tangent, 1):
			var alpha := Loss.rate(mode, no, ne, axis, ao, ae)
			check(alpha >= 0 and is_finite(alpha), "passive modal loss is finite and nonnegative")
			if not mode.extraordinary:
				check(absf(alpha - ao) < 1e-12, "ordinary eigenmode has principal ordinary attenuation")
			var whole := Loss.attenuate_eigenmode(mode, no, ne, axis, ao, ae, 2.4)
			var split := Loss.attenuate_eigenmode(mode, no, ne, axis, ao, ae, 0.7)
			split = Loss.attenuate_eigenmode(split, no, ne, axis, ao, ae, 1.7)
			check(absf(V.dot(whole.poynting, normal) - V.dot(split.poynting, normal)) < 1e-12, "modal attenuation is independent of segment partition")
			cases.append({"no": no, "ne": ne, "axis": axis, "kx": tangent[0], "alpha_o": ao, "alpha_e": ae,
				"wavelength_nm": 380 + index % 81 * 5, "mode": mode, "rate": alpha})
	# An equal coherent mixture becomes polarized under unequal absorption. It
	# must not be reset to a fresh equal mixture at the next geometry segment.
	var axis := V.vec(1, 0, 0)
	var modes := V.modes(1.5, 1.5, axis, normal, V.vec(0, 0, 0), 1)
	var initial := Packet.combine([{"mode": modes[0], "amplitude": [sqrt(0.5), 0]}, {"mode": modes[1], "amplitude": [0, sqrt(0.5)]}])
	var whole := Loss.propagate_isotropic(initial, 1.5, axis, 0.2, 1.3, 3.0)
	var split := Loss.propagate_isotropic(initial, 1.5, axis, 0.2, 1.3, 1.0)
	split = Loss.propagate_isotropic(split, 1.5, axis, 0.2, 1.3, 2.0)
	var expected := 0.5 * (exp(-0.2 * 3) + exp(-1.3 * 3))
	check(absf(V.dot(whole.poynting, normal) / V.dot(initial.poynting, normal) - expected) < 1e-12, "dichroic Jones propagation matches the two-polarization Beer law")
	for field in ["E_real", "E_imag", "H_real", "H_imag"]:
		var error := V.subtract(whole[field], split[field])
		check(V.dot(error, error) < 1e-24, "dichroic state persists across segmented geometry")
	var reset := 0.25 * (exp(-0.2) + exp(-1.3)) * (exp(-0.4) + exp(-2.6))
	check(absf(expected - reset) > 0.05, "fixture detects repeated unpolarized averaging")
	check(is_nan(Loss.rate(modes[0], 1.5, 1.5, axis, -1, 1)), "negative absorption is rejected")
	check(Loss.attenuate_eigenmode(modes[0], 1.5, 1.5, axis, 1, 1, -1).has("error"), "negative optical length is rejected")
	GemArtifactStore.atomic_write("res://artifacts/reference/crystal-loss.json", JSON.stringify(cases).to_utf8_buffer())
	print("Crystal loss: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_crystal_loss"); quit(1 if failures else 0)
