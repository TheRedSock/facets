extends SceneTree
const V := preload("res://core/lapidary/crystal_modes.gd")
const Interface := preload("res://core/lapidary/crystal_interface.gd")
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
	for index in 180:
		var source := {"no": 1.0 if index % 3 == 0 else 1.6, "ne": 1.0 if index % 3 == 0 else 1.8,
			"axis": V.unit(V.vec(sin(index * 0.4), cos(index * 0.3), 0.7))}
		var target := {"no": 1.0 if index % 3 == 1 else 1.7, "ne": 1.0 if index % 3 == 1 else 1.5,
			"axis": V.unit(V.vec(sin(index * 0.7), cos(index * 0.5), 0.3))}
		var tangent := V.vec((index % 17) * 0.095, 0, 0)
		for incoming in V.modes(source.no, source.ne, source.axis, normal, tangent, 1):
			if incoming.evanescent or incoming.normal_flux < 1e-10:
				continue
			var result := Interface.scatter(source, target, normal, incoming)
			check(not result.has("error"), "interface has a nonsingular field basis")
			if result.has("error"):
				continue
			check(absf(result.total_power - 1) < 1e-10, "lossless interface conserves total flux")
			check(result.continuity_residual < 1e-10, "tangential electric and magnetic fields are continuous")
			for branch in result.branches:
				check(branch.power >= -1e-12 and branch.power <= 1.0 + 1e-10, "outgoing modal flux is physical")
			cases.append(result)
			var identity := Interface.scatter(source, source, normal, incoming)
			check(not identity.has("error") and identity.branches[0].power + identity.branches[1].power < 1e-20, "identical crystal boundary is invisible")
	# Isotropic reduction against the exact separate s and p Fresnel laws.
	for angle in [0.0, 0.2, 0.6, 1.0]:
		var source := {"no": 1.0, "ne": 1.0, "axis": normal}
		var target := {"no": 1.5, "ne": 1.5, "axis": normal}
		var ci := cos(angle)
		var ct := sqrt(1 - pow(sin(angle) / 1.5, 2))
		var expected := [pow((ci - 1.5 * ct) / (ci + 1.5 * ct), 2), pow((1.5 * ci - ct) / (1.5 * ci + ct), 2)]
		var incoming := V.modes(1, 1, normal, normal, V.vec(sin(angle), 0, 0), 1)
		for mode in 2:
			var result := Interface.scatter(source, target, normal, incoming[mode])
			var reflection: float = result.branches[0].power + result.branches[1].power
			check(absf(reflection - expected[mode]) < 1e-12, "isotropic reduction matches s/p Fresnel")
	# At normal incidence a tangential optic axis makes one polarization see ne.
	var source := {"no": 1.0, "ne": 1.0, "axis": normal}
	var target := {"no": 1.5, "ne": 1.7, "axis": V.vec(1, 0, 0)}
	for incoming in V.modes(1, 1, normal, normal, V.vec(0, 0, 0), 1):
		var n: float = target.ne if absf(incoming.E_real[0]) > 0.9 else target.no
		var result := Interface.scatter(source, target, normal, incoming)
		check(absf(result.branches[0].power + result.branches[1].power - pow((1 - n) / (1 + n), 2)) < 1e-12, "principal normal-incidence reflectance uses the correct index")
	GemArtifactStore.atomic_write("res://artifacts/reference/crystal-interfaces.json", JSON.stringify(cases).to_utf8_buffer())
	print("Crystal interface: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
