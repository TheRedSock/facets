extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

static func box(low: Vector3, high: Vector3) -> GemMesh:
	var points := PackedVector2Array([Vector2(low.x, low.y), Vector2(high.x, low.y), Vector2(high.x, high.y), Vector2(low.x, high.y)])
	return GemShapeCompiler.loft(points, PackedVector2Array([Vector2(low.z, 1), Vector2(high.z, 1)]))

func _initialize() -> void:
	for name in DirAccess.get_files_at("res://data/lapidary/stones/"):
		if not name.ends_with(".tres"):
			continue
		var stone: GemStone = load("res://data/lapidary/stones/" + name).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		for grade in [stone.grade.cut, 0.4, 0.7, 1.0]:
			stone.condition.workmanship.azimuth_error_deg = 2.8 * (1.0 - grade)
			stone.condition.workmanship.polar_error_deg = 0.4 * (1.0 - grade)
			stone.condition.workmanship.inward_offset_mm = 0.004 * stone.size_mm * (1.0 - grade)
			stone.condition.workmanship.girdle_inward_mm = 0.006 * stone.size_mm * (1.0 - grade)
			var compiled := LapidaryStoneCompiler.compile(stone)
			var mesh := GemShapeCompiler.from_hull(compiled["planes"])
			check(mesh.validate().is_empty(), "%s q%.3f mesh closure: %s" % [name, grade, mesh.validate()])
	var boundaries := GemBoundarySet.new()
	check(boundaries.add(box(Vector3(-1, -1, -1), Vector3(1, 1, 1)), 0), "valid host")
	check(boundaries.add(box(Vector3(-0.8, -0.8, -0.5), Vector3(0.8, 0.8, 0.1)), -1), "first cavity")
	check(boundaries.add(box(Vector3(-0.7, -0.7, -0.1), Vector3(0.7, 0.7, 0.5)), -1), "overlapping cavity")
	var segments := boundaries.segments(Vector3(0, 0, 3), Vector3.FORWARD)
	var length := 0.0
	for segment in segments:
		length += segment["end"] - segment["begin"]
	check(absf(length - 1.0) < 0.0001, "void union removes one mm, not sum of overlaps")
	check(boundaries.add(box(Vector3(-0.5, -0.5, -0.2), Vector3(0.5, 0.5, 0.2)), 1), "finite filling")
	segments = boundaries.segments(Vector3(0, 0, 3), Vector3.FORWARD)
	var filling := 0.0
	for segment in segments:
		if segment["medium"] == 1:
			filling += segment["end"] - segment["begin"]
	check(absf(filling - 0.4) < 0.0001, "priority filling has correct optical thickness")
	# A void entirely outside the host has no optical or silhouette effect.
	check(boundaries.add(box(Vector3(-0.2, -0.2, 1.2), Vector3(0.2, 0.2, 1.8)), -1), "outside void")
	check(boundaries.medium({3: true}) == -1, "all material regions clipped to host")
	for kind in ["fracture", "chip", "crystal"]:
		for seed_value in 8:
			var defect := GemDefect.new()
			defect.kind = kind
			defect.seed = seed_value
			var surface := GemDefectCompiler.compile(defect, 4.0)
			check(surface.validate().is_empty(), "%s seed%d closed thin boundary" % [kind, seed_value])
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var original := stone.fingerprint()
	var defect := GemDefect.new()
	stone.condition.defects.append(defect)
	check(stone.fingerprint() != original, "physical condition participates in content identity")
	var realized := LapidaryStoneCompiler.compile(stone)
	check(realized.has("boundaries") and realized["boundaries"].materials.size() == 2, "condition compiles to finite medium boundaries")
	stone.condition.finish.alpha_u = 0.005
	defect.finish.alpha_u = 0.015
	defect.finish.alpha_v = 0.002
	original = stone.fingerprint()
	defect.finish.direction = Vector3.UP
	check(stone.fingerprint() != original, "boundary finish direction participates in identity")
	realized = LapidaryStoneCompiler.compile(stone)
	check(realized["surfaces"].size() == 2 and realized["surfaces"][0].alpha_u == 0.005 and realized["surfaces"][1].alpha_u == 0.015, "host and defect retain independent finishes")
	var invalid_finish := GemSurface.new()
	invalid_finish.alpha_u = NAN
	check(not invalid_finish.validate().is_empty(), "nonfinite surface finish rejected")
	var shape := Vector4(1.0, 0.8, 0.6, -0.04)
	for x in [-0.7, -0.3, 0.0, 0.5]:
		var hit := GemQuadric.intersect(shape, Vector3(x, 0, 3), Vector3.FORWARD)
		var expected := 3.0 - 0.6 * sqrt(1.0 - x * x)
		check(not hit.is_empty() and absf(hit["t"] - expected) < 0.000002, "analytic dome intersection")
	var cap_regions := GemBoundarySet.new()
	check(cap_regions.add_cabochon(shape, 0), "analytic host region")
	cap_regions.add(box(Vector3(-0.3, -0.3, 0.1), Vector3(0.3, 0.3, 0.3)), -1)
	length = 0.0
	for segment in cap_regions.segments(Vector3(0, 0, 3), Vector3.FORWARD):
		length += segment["end"] - segment["begin"]
	check(absf(length - 0.44) < 0.0001, "analytic host and mesh cavity share one medium state")
	var deep := box(Vector3(-1, -1, -12), Vector3(1, 1, 12))
	check(GemTracer._boundary_radius({"mesh": deep, "planes": PackedFloat32Array()}) > 12.0, "arbitrary-depth mesh bounds camera origins")
	print("Boundaries: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_boundaries"); quit(1 if failures else 0)
