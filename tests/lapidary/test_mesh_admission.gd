extends SceneTree
const P := preload("res://core/lapidary/geometry/exact_predicates.gd")
const Contact := preload("res://core/lapidary/geometry/mesh_intersections.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func box(low: Vector3, high: Vector3) -> GemMesh:
	return GemShapeCompiler.loft(PackedVector2Array([Vector2(low.x, low.y), Vector2(high.x, low.y), Vector2(high.x, high.y), Vector2(low.x, high.y)]), PackedVector2Array([Vector2(low.z, 1), Vector2(high.z, 1)]))

func invert(mesh: GemMesh) -> void:
	for i in mesh.triangle_count():
		var temporary := mesh.indices[i * 3]
		mesh.indices[i * 3] = mesh.indices[i * 3 + 1]
		mesh.indices[i * 3 + 1] = temporary

func _initialize() -> void:
	var outer := box(Vector3(-2, -2, -2), Vector3(2, 2, 2))
	check(outer.validate().is_empty(), "valid cube")
	outer.region_ids[0] = 1
	check(not outer.validate().is_empty(), "faces from different regions cannot close each other; cache invalidates")
	outer.region_ids[0] = 0
	check(outer.validate().is_empty(), "restoring content restores admission")
	var inner := box(Vector3(-1, -1, -1), Vector3(1, 1, 1))
	outer.append_region(inner, 0)
	check(not outer.validate().is_empty(), "nested outward shell cannot share one region state")
	outer = box(Vector3(-2, -2, -2), Vector3(2, 2, 2))
	invert(inner)
	outer.append_region(inner, 0)
	check(outer.validate().is_empty(), "inward cavity inside outward shell is valid: %s" % outer.validate())
	outer.append_region(box(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5)), 0)
	check(outer.validate().is_empty(), "nested solid island restores region at depth two")
	var regions := GemBoundarySet.new()
	check(regions.add(outer, 0), "hollow region accepted by boundary set")
	var segments := regions.segments(Vector3(0.1, 0.2, 3), Vector3.FORWARD)
	var length := 0.0
	for segment in segments:
		length += segment.end - segment.begin
	check(absf(length - 3.0) < 0.0001, "nested cavity and island produce correct medium length")
	var disjoint := box(Vector3(-2, -2, -2), Vector3(2, 2, 2))
	var small := box(Vector3(3, 3, 3), Vector3(4, 4, 4))
	invert(small)
	disjoint.append_region(small, 0)
	check(disjoint.signed_volume() > 0 and not disjoint.validate().is_empty(), "positive total volume cannot hide inverted disconnected shell")
	for contact in [0.0, 1.0, 2.0]:
		var mesh := box(Vector3(-1, -1, -1), Vector3(1, 1, 1))
		mesh.append_region(box(Vector3(contact, contact, contact), Vector3(contact + 2, contact + 2, contact + 2)), 0)
		check(mesh.validate().is_empty() == (contact > 1), "same-region overlap/touch rejected, separate pockets accepted %.1f" % contact)
	var priority := box(Vector3(-1, -1, -1), Vector3(1, 1, 1))
	priority.append_region(box(Vector3.ZERO, Vector3(2, 2, 2)), 1)
	check(priority.validate().is_empty(), "intentional different-region overlap allowed")
	check(not GemBoundarySet.new().add(priority, 0), "add cannot silently collapse separate regions into one")
	var coincident := box(Vector3(-1,-1,-1), Vector3(1,1,1))
	coincident.append_region(box(Vector3(-1,-1,-1), Vector3(1,1,1)), 1)
	check(not coincident.validate().is_empty(), "coincident priority interfaces rejected")
	var rejected := GemTracer.new()
	var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	check(not rejected.configure_stone({"mesh":coincident}, lighting, {}) and "Invalid optical boundary mesh" in rejected.configuration_error, "renderer rejects invalid meshes without a device or debug assertion")
	var pinch := box(Vector3(-1, -1, -1), Vector3(1, 1, 1))
	pinch.append_region(box(Vector3.ONE, Vector3(2, 2, 2)), 0)
	var matching: Array[int] = []
	for i in pinch.vertices.size():
		if pinch.vertices[i] == Vector3.ONE:
			matching.append(i)
	check(matching.size() == 2, "pinch fixture has two coincident indexed vertices")
	for i in pinch.indices.size():
		if pinch.indices[i] == matching[1]:
			pinch.indices[i] = matching[0]
	check("fan" in str(pinch.validate()), "disconnected vertex fan rejected before geometry traversal")
	var translated := box(Vector3.ZERO, Vector3(2, 2, 2))
	for i in translated.vertices.size():
		translated.vertices[i] += Vector3(1000000, 1000000, 1000000)
	check(translated.validate().is_empty() and absf(translated.signed_volume() - 8) < 1e-12, "translated volume uses local binary64 accumulation")
	var job := GemFrameJob.new()
	job.stone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	job.print_style = GemPrint.load_house()
	var defect := GemDefect.new()
	defect.kind = "crystal"
	job.stone.condition.defects.append(defect)
	job.stone.condition.defects.append(defect.duplicate_deep(Resource.DEEP_DUPLICATE_ALL))
	check("combined region" in GemJobValidator.validate(job), "factory rejects coincident defect regions before GPU acquisition")
	_triangle_cases()
	_predicate_reference()
	print("Mesh admission: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_mesh_admission"); quit(1 if failures else 0)

func _triangle_cases() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(2, 0, 0)
	var c := Vector3(0, 2, 0)
	var cases := [
		[[a,b,c,Vector3(1,1,0)], [0,1,2,0,1,3], true, "coplanar shared-edge fold"],
		[[a,b,c,Vector3(0,-2,0)], [0,1,2,0,1,3], false, "coplanar adjacent faces"],
		[[a,b,c,Vector3(0,0,1)], [0,1,2,0,1,3], false, "noncoplanar shared edge"],
		[[a,b,c,Vector3(1,0,0),Vector3(0,1,0)], [0,1,2,0,3,4], true, "shared-vertex containment"],
		[[a,b,c,Vector3(-1,0,0),Vector3(0,-1,0)], [0,1,2,0,3,4], false, "shared vertex only"],
		[[a,b,c,Vector3(.5,.5,-1),Vector3(.5,.5,1),Vector3(1,1,1)], [0,1,2,3,4,5], true, "proper noncoplanar crossing"],
		[[a,b,c,Vector3(.5,.5,0),Vector3(.75,.5,0),Vector3(.5,.75,0)], [0,1,2,3,4,5], true, "unshared coplanar containment"],
		[[a,b,c,Vector3(0,0,1e-30),Vector3(2,0,1e-30),Vector3(0,2,1e-30)], [0,1,2,3,4,5], false, "tiny finite gap is not contact"],
		[[a,b,c,a,Vector3(-1,0,0),Vector3(0,-1,0)], [0,1,2,3,4,5], true, "unshared vertex contact"],
		[[a,b,c,Vector3(-1,1,0),Vector3(1,-0.5,0)], [0,1,2,0,3,4], true, "opposite edge crosses with shared vertex"]
	]
	var permutations := [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]
	for fixture: Array in cases:
		for pa: Array in permutations:
			for pb: Array in permutations:
				var mesh := GemMesh.new()
				mesh.vertices = PackedVector3Array(fixture[0])
				mesh.add_triangle(fixture[1][pa[0]], fixture[1][pa[1]], fixture[1][pa[2]], 0)
				mesh.add_triangle(fixture[1][3+pb[0]], fixture[1][3+pb[1]], fixture[1][3+pb[2]], 1)
				check(Contact.invalid_pair(mesh, 0, 1) == fixture[2], fixture[3])

func _predicate_reference() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 827119
	var rows: Array = []
	for i in 2048:
		var points: Array[Vector3] = []
		for j in 4:
			var v := Vector3.ZERO
			for axis in 3:
				v[axis] = float(rng.randi_range(-1000000, 1000000)) * pow(2.0, rng.randi_range(-120, 100) if i % 2 else (i % 101 - 50))
			points.append(v)
		if i % 4 == 0:
			points[3] = points[0] + points[1] - points[2]
		if i % 8 == 0:
			points[3] = points[0]
		if i % 8 == 4:
			var bytes := PackedByteArray()
			bytes.resize(4)
			bytes.encode_float(0, points[3].z)
			bytes.encode_u32(0, bytes.decode_u32(0) ^ 1)
			points[3].z = bytes.decode_float(0)
		var row := {"points": [], "signs": [P.orient3(points[0],points[1],points[2],points[3])]}
		for p in points:
			row.points.append([p.x,p.y,p.z])
		for axes in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,0)]:
			row.signs.append(P.orient2(points[0],points[1],points[2],axes.x,axes.y))
		rows.append(row)
	var pairs := []
	for i in 768:
		var mesh := GemMesh.new()
		while mesh.triangle_count() < 2:
			var ids: Array[int] = []
			for k in 3:
				if mesh.triangle_count() == 1 and k < i % 4:
					ids.append(mesh.indices[k])
				else:
					ids.append(mesh.vertices.size())
					mesh.vertices.append(Vector3(rng.randi_range(-4,4),rng.randi_range(-4,4),0 if i % 3 == 0 else rng.randi_range(-4,4)))
			if Contact.projection(mesh.vertices[ids[0]],mesh.vertices[ids[1]],mesh.vertices[ids[2]]).x >= 0:
				mesh.add_triangle(ids[0],ids[1],ids[2],0)
		var points := []
		for vertex in mesh.vertices:
			points.append([vertex.x,vertex.y,vertex.z])
		var invalid := Contact.invalid_pair(mesh,0,1)
		check((Contact.first_invalid(mesh).x >= 0) == invalid, "BVH broad phase preserves triangle contact result")
		pairs.append({"points":points,"indices":Array(mesh.indices),"invalid":invalid})
	GemArtifactStore.atomic_write("res://artifacts/geometry/predicates.json", JSON.stringify({"source":FileAccess.get_sha256("res://core/lapidary/geometry/exact_predicates.gd"),"intersection_source":FileAccess.get_sha256("res://core/lapidary/geometry/mesh_intersections.gd"),"cases":rows,"pairs":pairs}, "", true, true).to_utf8_buffer())
