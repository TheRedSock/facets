extends SceneTree
const V := preload("res://core/lapidary/crystal_modes.gd")
const Packet := preload("res://core/lapidary/crystal_packet.gd")
const Measure := preload("res://core/lapidary/crystal_measure.gd")
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_measure_checks()
	_packet_checks()
	_reciprocity_checks()
	_export_chains()
	print("Crystal packet/measure: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_crystal_packet"); quit(1 if failures else 0)

func _measure_checks() -> void:
	var n := V.vec(0, 0, 1)
	for index in 96:
		var medium := {"no": 1.5, "ne": 1.8 if index % 2 else 1.3,
			"axis": V.unit(V.vec(sin(index * 0.7), cos(index * 0.4), 0.3))}
		var t := V.vec(0.7 * sin(index * 0.3), 0.6 * cos(index * 0.2), 0)
		var modes := V.modes(medium.no, medium.ne, medium.axis, n, t, 1)
		for mode_index in 2:
			var mode: Dictionary = modes[mode_index]
			# Independent local area Jacobian of the Gauss map parameterized by
			# conserved tangential k. It must equal K / |ray.normal|.
			var derivatives: Array[PackedFloat64Array] = []
			var h := 1e-5
			for axis in 2:
				var plus := t.duplicate()
				var minus := t.duplicate()
				plus[axis] += h
				minus[axis] -= h
				var p := V.modes(medium.no, medium.ne, medium.axis, n, plus, 1)[mode_index]
				var m := V.modes(medium.no, medium.ne, medium.axis, n, minus, 1)[mode_index]
				derivatives.append(V.scale(V.subtract(p.ray, m.ray), 0.5 / h))
			var area := V.cross(derivatives[0], derivatives[1])
			var jacobian := sqrt(V.dot(area, area))
			var expected := Measure.curvature(mode, medium) / absf(V.dot(mode.ray, n))
			check(absf(jacobian / expected - 1) < 1e-8, "curvature predicts independently differentiated ray solid angle")
	var air := {"no": 1.0, "ne": 1.0, "axis": n}
	var glass := {"no": 1.5, "ne": 1.5, "axis": n}
	var a := V.modes(1, 1, n, n, V.vec(0.5, 0, 0), 1)[0]
	var g := V.modes(1.5, 1.5, n, n, V.vec(0.5, 0, 0), 1)[1]
	check(absf(Measure.camera_radiance_factor(a, air, g, glass) - 1.0 / 2.25) < 1e-12, "camera measure reduces to isotropic eta squared")
	check(absf(Measure.forward_radiance_factor(a, air, g, glass) - 2.25) < 1e-12, "forward measure is the inverse radiance conversion")

func _packet_checks() -> void:
	var n := V.vec(0, 0, 1)
	var glass := {"no": 1.5, "ne": 1.5, "axis": n}
	var air := {"no": 1.0, "ne": 1.0, "axis": n}
	for angle in [0.2, 0.8, 1.2]:
		var modes := V.modes(1.5, 1.5, n, n, V.vec(1.5 * sin(angle), 0, 0), 1)
		# Coherent equal s,p input, with a relative complex phase.
		for phase in [0.0, 0.7, 1.5707963267948966]:
			var incoming := Packet.combine([{"mode": modes[0], "amplitude": [sqrt(0.5), 0]},
				{"mode": modes[1], "amplitude": [sqrt(0.5) * cos(phase), sqrt(0.5) * sin(phase)]}])
			var scatter := GemCrystalInterface.scatter(glass, air, n, incoming)
			check(not scatter.has("error"), "arbitrary Jones state solves the interface")
			var packets := Packet.outgoing(scatter, glass, air, n, incoming)
			check(packets.size() == (1 if angle > asin(1.0 / 1.5) else 2), "isotropic components recombine into one ray per side")
			var sum := 0.0
			for packet in packets:
				sum += packet.power
				check(V.maxwell_residual(packet, 1.5 if packet.reflected else 1.0, 1.5 if packet.reflected else 1.0, n) < 1e-12, "recombined complex field satisfies Maxwell equations")
			check(absf(sum - 1) < 1e-12, "coherent ray powers conserve flux")

func _reciprocity_checks() -> void:
	var n := V.vec(0, 0, 1)
	for index in 64:
		var source := {"no": 1.6, "ne": 1.8, "axis": V.unit(V.vec(sin(index * 0.4), cos(index * 0.7), 0.6))}
		var target := {"no": 1.5, "ne": 1.3, "axis": V.unit(V.vec(sin(index * 0.2), cos(index * 0.5), 0.3))}
		for incoming in V.modes(source.no, source.ne, source.axis, n, V.vec(0.9 * sin(index * 0.3), 0.4, 0), 1):
			var scatter := GemCrystalInterface.scatter(source, target, n, incoming)
			for branch in scatter.branches:
				if branch.mode.evanescent:
					continue
				var reversed: Dictionary = branch.mode.duplicate(true)
				reversed["k_real"] = V.scale(reversed.k_real, -1)
				reversed["E_imag"] = V.scale(reversed.E_imag, -1)
				reversed["H_real"] = V.scale(reversed.H_real, -1)
				reversed["poynting"] = V.scale(reversed.poynting, -1)
				var reverse := GemCrystalInterface.scatter(source if branch.reflected else target,
					target if branch.reflected else source, n if branch.reflected else V.scale(n, -1), reversed)
				check(not reverse.has("error"), "time-reversed propagating channel solves")
				var expected_index := (0 if branch.reflected else 2) + int(incoming.extraordinary)
				check(absf(reverse.branches[expected_index].power - branch.power) < 1e-10, "flux-normalized modal channel is reciprocal")

func _export_chains() -> void:
	var cases := []
	for index in 64:
		var direction := V.unit(V.vec(sin(0.3 + index * 0.012), 0, 1))
		var u := V.unit(V.cross(V.vec(0, 1, 0), direction))
		var v := V.cross(direction, u)
		var theta := 0.2 + index * 0.031
		var phase := index * 0.17
		var er := V.add(V.scale(u, cos(theta)), V.scale(v, sin(theta) * cos(phase)))
		var ei := V.scale(v, sin(theta) * sin(phase))
		var packet := {"k_real": direction, "k_imag": V.vec(0, 0, 0), "E_real": er, "E_imag": ei,
			"H_real": V.cross(direction, er), "H_imag": V.cross(direction, ei),
			"poynting": V.scale(direction, 0.5), "evanescent": false, "extraordinary": false, "degenerate": false}
		var initial := _stokes(Packet.jones(packet, u, v))
		var steps := []
		var flux_product := 1.0
		for step in 5:
			var normal := V.vec(0, 0, 1)
			if step > 0:
				var tangent := V.unit(V.cross(direction, V.vec(0, 1, 0)))
				var bitangent := V.cross(direction, tangent)
				var azimuth := index * 0.13 + step * 0.87
				var cosine := 0.85 if step == 4 else 0.5 + 0.1 * sin(index * 0.3 + step)
				normal = V.add(V.scale(direction, cosine), V.scale(V.add(V.scale(tangent, cos(azimuth)), V.scale(bitangent, sin(azimuth))), sqrt(1 - cosine * cosine)))
			var before := 1.0 if step == 0 else 1.5
			var after := 1.5 if step == 0 else 1.0
			var transmission := step in [0, 4]
			var source := {"no": before, "ne": before, "axis": normal}
			var target := {"no": after, "ne": after, "axis": normal}
			var scatter := GemCrystalInterface.scatter(source, target, normal, packet)
			var packets := Packet.outgoing(scatter, source, target, normal, packet)
			var selected := false
			for candidate in packets:
				if candidate.reflected != transmission:
					packet = candidate
					flux_product *= candidate.power
					selected = true
			check(selected, "five-interface chain retains the requested physical ray")
			var next: PackedFloat64Array = packet.ray
			steps.append({"before": before, "after": after, "direction": direction, "next": next, "normal": normal, "transmission": transmission})
			direction = next
		var final_u := V.unit(V.cross(V.vec(0, 1, 0), direction))
		var final_v := V.cross(direction, final_u)
		var final := _stokes(Packet.jones(packet, final_u, final_v))
		var flux_stokes := final.duplicate()
		for component in 4:
			flux_stokes[component] *= flux_product / final[0]
		cases.append({"initial": initial, "initial_axis": u, "steps": steps,
			"final_axis": final_u, "final": final, "flux_stokes": flux_stokes})
	GemArtifactStore.atomic_write("res://artifacts/reference/crystal-packet-chains.json", JSON.stringify(cases).to_utf8_buffer())

func _stokes(j: PackedFloat64Array) -> PackedFloat64Array:
	var a := j[0] * j[0] + j[1] * j[1]
	var b := j[2] * j[2] + j[3] * j[3]
	# Export convention: V = 2 Im(Eu*conj(Ev)), matching Mitsuba's Mueller basis.
	return PackedFloat64Array([a + b, a - b, 2 * (j[0] * j[2] + j[1] * j[3]), 2 * (j[1] * j[2] - j[0] * j[3])])
