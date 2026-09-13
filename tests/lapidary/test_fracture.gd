extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var report := []
	var contacts_seen := false
	var pockets_seen := false
	for seed_value in 12:
		var defect := GemDefect.new()
		defect.seed = seed_value + 17
		defect.fracture_profile.aperture_variation = 1.0
		defect.fracture_profile.correlation_mm = 0.15
		defect.fracture_profile.resolution = 32
		var previous := INF
		for closure in [0.0, 0.001, 0.002, 0.003, 0.006]:
			defect.fracture_profile.closure_mm = closure
			var mesh := GemDefectCompiler.compile(defect, 4.0)
			if mesh.vertices.is_empty():
				previous = 0.0
				continue
			var errors := mesh.validate()
			check(errors.is_empty(), "seed%d closure%.4f is a closed oriented volume: %s" % [seed_value, closure, errors])
			var volume := mesh.signed_volume() * 64.0
			check(volume <= previous + 1e-9 and volume > 0, "closure monotonically removes aperture volume")
			previous = volume
			var topology := _topology(mesh)
			contacts_seen = contacts_seen or topology.genus > 0
			pockets_seen = pockets_seen or topology.components > 1
			report.append({"seed": defect.seed, "closure_mm": closure, "volume_mm3": volume, "triangles": mesh.triangle_count(), "topology": topology})
	check(contacts_seen, "closure can produce host bridges through a connected fracture")
	check(pockets_seen, "closure can leave separated pockets without spawning independent primitives")
	var defect := GemDefect.new()
	var original := GemDefectCompiler.compile(defect, 4)
	check(original.fingerprint() == GemDefectCompiler.compile(defect, 4).fingerprint(), "aperture construction is deterministic")
	var scaled := GemDefectCompiler.compile(defect, 8)
	check(absf(original.signed_volume() / scaled.signed_volume() - 8) < 0.00001, "physical fracture size is independent of host normalization")
	for resolution in [8, 16, 64, 128]:
		defect.fracture_profile.resolution = resolution
		defect.orientation = Quaternion(Vector3(1, 2, 3).normalized(), 0.7)
		defect.center_mm = Vector3(0.4, -0.3, 0.2)
		var transformed := GemDefectCompiler.compile(defect, 4)
		check(transformed.validate().is_empty(), "rotated aperture is valid at resolution %d: %s" % [resolution, transformed.validate()])
		defect.orientation = Quaternion.IDENTITY
		defect.center_mm = Vector3.ZERO
		var untransformed := GemDefectCompiler.compile(defect, 4)
		check(absf(transformed.signed_volume() / untransformed.signed_volume() - 1) < 0.0001, "rigid placement preserves physical void volume")
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var clean := LapidaryStoneCompiler.compile(stone)
	defect.fracture_profile.closure_mm = 1.0
	stone.condition.defects.append(defect)
	var closed := LapidaryStoneCompiler.compile(stone)
	check(not closed.has("boundaries") and closed.planes == clean.planes, "fully closed fracture leaves the exact host geometry untouched")
	for index in GemBoundarySet.MAX_REGIONS:
		stone.condition.defects.append(defect)
	var job := GemFrameJob.new()
	job.stone = stone
	job.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	job.print_style = GemPrint.load_house()
	var admission := GemJobValidator.validate(job)
	check(admission.is_empty(), "closed apertures consume no region budget: " + admission)
	defect.fracture_profile.correlation_mm = 0
	check(not defect.fracture_profile.validate().is_empty(), "invalid correlation length rejected")
	GemArtifactStore.atomic_write("res://artifacts/fracture/topology.json", JSON.stringify(report, "\t").to_utf8_buffer())
	print("Fracture: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_fracture"); quit(1 if failures else 0)

func _topology(mesh: GemMesh) -> Dictionary:
	var parent := PackedInt32Array()
	parent.resize(mesh.vertices.size())
	for index in parent.size():
		parent[index] = index
	var edges := {}
	for triangle in mesh.triangle_count():
		var vertices := mesh.indices.slice(triangle * 3, triangle * 3 + 3)
		for index in 3:
			var a := vertices[index]
			var b := vertices[(index + 1) % 3]
			edges[Vector2i(mini(a, b), maxi(a, b))] = true
			parent[_root(parent, a)] = _root(parent, b)
	var roots := {}
	for index in parent.size():
		roots[_root(parent, index)] = true
	var euler := mesh.vertices.size() - edges.size() + mesh.triangle_count()
	return {"components": roots.size(), "genus": roots.size() - euler / 2, "euler": euler}

func _root(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index:
		index = parent[index]
	return index
