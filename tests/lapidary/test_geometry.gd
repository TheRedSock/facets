extends SceneTree
const CutCompiler := preload("res://core/lapidary/cut/cut_compiler.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var ruby: GemStone = load("res://data/lapidary/stones/ruby.tres")
	check(ruby.shape.outline == &"marquise" and is_equal_approx(ruby.shape.aspect_ratio, 1.8), "authored shape schema roundtrips")
	var template: GemCutTemplate = load("res://data/lapidary/cuts/brilliant.tres")
	for kind in [&"round", &"square", &"triangle", &"oval", &"diamond", &"rectangle", &"marquise", &"pear"]:
		for grade in [0.6, 1.0]:
			var shape := GemShape.faceted_outline(kind)
			var selected: GemCutTemplate = load("res://data/lapidary/cuts/brilliant_triangle.tres") if kind == &"triangle" else template
			var compiled: Dictionary = CutCompiler.compile(selected, shape, 71, Vector4(2.8, 0.4, 0.004, 0.006) * (1.0 - grade))
			check(not compiled.has("compilation_error"), "%s q%.1f program admission: %s" % [kind, grade, compiled.get("compilation_error", "")])
			if compiled.has("compilation_error"): continue
			var mesh := GemShapeCompiler.from_hull(compiled["planes"], compiled["facet_ids"])
			var errors := mesh.validate()
			check(errors.is_empty(), "%s q%.1f closed oriented mesh: %s" % [kind, grade, errors])
			check(mesh.signed_volume() > 0.0, "positive gem volume")
			var bvh := GemBvh.build(mesh)
			check(bvh.pack_nodes().size() == bvh.nodes.size() * 48, "node binary contract")
			check(bvh.pack_triangles().size() == mesh.triangle_count() * 64, "triangle binary contract")
			_check_rays(mesh, bvh)
	var shape := GemShape.faceted_outline(&"oval")
	shape.mode = "cabochon"
	shape.radial_segments = 96
	shape.dome_rings = 32
	var dome := GemShapeCompiler.compile(shape)
	check(dome.validate().is_empty(), "procedural cabochon is closed and oriented")
	var expected := PI / shape.aspect_ratio * (2.0 * shape.dome_height / 3.0 + 0.04)
	check(absf(dome.signed_volume() / expected - 1.0) < 0.005, "cabochon converges to analytic ellipsoid-half volume")
	# Concave U cross-section, extruded: a ray exits then re-enters the SAME
	# specimen. Evaluating environment immediately on every exit is incorrect.
	var outline := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0.4, 1), Vector2(0.4, -0.2), Vector2(-0.4, -0.2), Vector2(-0.4, 1), Vector2(-1, 1)])
	var concave := GemShapeCompiler.loft(outline, PackedVector2Array([Vector2(-0.5, 1), Vector2(0.5, 1)]))
	check(concave.validate().is_empty(), "concave procedural solid is closed")
	var bvh := GemBvh.build(concave)
	var origin := Vector3(2, 0.5, 0)
	var positions := PackedFloat32Array()
	for index in 5:
		var hit := bvh.intersect(origin, Vector3.LEFT)
		if hit.is_empty():
			break
		origin += Vector3.LEFT * float(hit["t"])
		positions.append(origin.x)
		origin += Vector3.LEFT * 0.00001
	check(positions.size() == 4, "ray encounters four ordered boundaries, including external reentry")
	if positions.size() == 4:
		for i in 4:
			check(absf(positions[i] - [1.0, 0.4, -0.4, -1.0][i]) < 0.00001, "concave boundary position %d" % i)
	# Reversing one triangle must fail manifold winding validation.
	var temporary := concave.indices[0]
	concave.indices[0] = concave.indices[1]
	concave.indices[1] = temporary
	check(not concave.validate().is_empty(), "inverted triangle rejected")
	print("Geometry: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_geometry"); quit(1 if failures else 0)

func _check_rays(mesh: GemMesh, bvh: GemBvh) -> void:
	for index in 32:
		var origin := Vector3(sin(index * 1.37) * 1.3, cos(index * 0.79) * 1.3, 3)
		var direction := Vector3(0.02, 0.03, -1).normalized()
		var nearest := INF
		for triangle in mesh.triangle_count():
			var t := GemBvh.triangle_hit(mesh, triangle, origin, direction)
			if t > 0.000001:
				nearest = minf(nearest, t)
		var hit := bvh.intersect(origin, direction)
		check(hit.is_empty() if nearest == INF else not hit.is_empty() and absf(float(hit["t"]) - nearest) < 0.00001, "BVH equals independent exhaustive traversal")
