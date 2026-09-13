extends SceneTree
## Headless test for the Lapidary cut compiler (pure CPU, no RenderingDevice).
## Run:
##   godot --headless --path . --script res://tests/lapidary/test_cut_compiler.gd
##
## Battery: 8 silhouettes x brilliant x quality {0.15, 0.6, 1.0} plus
## {square, rectangle} x step x same qualities. Asserts: bounded hull, sane
## plane count, convex outline (rounded k-gon: k flats + symmetric corner
## arcs at q=1; X-mirror for smooth silhouettes), solved pavilion angle within 0.5 deg
## of the explicit template angle, exact regularity at q = 1
## (zero jitter), determinism (same seed -> identical output; different seed
## -> different jitter), and admitted construction. Planes with exactly-empty
## faces are PRUNED by the compiler (sliver facets erased by meeting error,
## fan facets that cannot fit a pointed silhouette); the hull girdle count may
## drop at tips (knife-edge) while the 2D outline keeps every girdle line.

const CutCompiler := preload("res://core/lapidary/cut/cut_compiler.gd")
const SilhouetteLib := preload("res://core/lapidary/cut/silhouettes.gd")

const SEED_A := 1234
const SEED_B := 907351
const QUALITIES: Array[float] = [0.15, 0.6, 1.0]
const SILHOUETTES: Array[StringName] = [
	&"round", &"square", &"triangle", &"oval",
	&"diamond", &"rectangle", &"marquise", &"pear",
]
const STEP_SILHOUETTES: Array[StringName] = [&"square", &"rectangle"]

var _pass_count := 0
var _fail_count := 0
var _failed_cases: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	print("\n=== Lapidary Cut Compiler Test ===")
	var brilliant: Resource = load("res://data/lapidary/cuts/brilliant.tres")
	var step: Resource = load("res://data/lapidary/cuts/step.tres")
	if brilliant == null or step == null:
		print("FAIL: could not load cut templates from data/lapidary/cuts/")
		print("CHECK_COMPLETE: test_cut_compiler"); quit(1)
		return
	for sil in SILHOUETTES:
		for q in QUALITIES:
			_exercise(brilliant, "brilliant", sil, q)
	for sil in STEP_SILHOUETTES:
		for q in QUALITIES:
			_exercise(step, "step", sil, q)

	print("\n%d checks passed, %d failed" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("Failed cases:")
		for c in _failed_cases:
			print("  " + c)
		print("CUT COMPILER TESTS FAILED")
	else:
		print("CUT COMPILER TESTS PASSED")
	print("CHECK_COMPLETE: test_cut_compiler"); quit(1 if _fail_count > 0 else 0)


func _exercise(template: Resource, template_name: String, silhouette: StringName, q: float) -> void:
	if silhouette == &"triangle": template = load("res://data/lapidary/cuts/" + template_name + "_triangle.tres")
	var label := "%s/%s q=%.2f" % [template_name, silhouette, q]
	var fails := PackedStringArray()
	var result: Dictionary = CutCompiler.compile(template, GemShape.faceted_outline(silhouette), SEED_A, Vector4(2.8, 0.4, 0.004, 0.006) * (1.0 - q))
	var planes: PackedFloat32Array = result["planes"]
	var outline: PackedVector2Array = result["outline"]
	var plane_count := planes.size() / 8

	if planes.is_empty() or planes.size() % 8 != 0:
		fails.append("planes empty/malformed")
	if plane_count < 16 or plane_count > 140:
		fails.append("plane count %d out of [16, 140]" % plane_count)
	if not _is_bounded(planes):
		fails.append("hull unbounded")
	if outline.size() < 3:
		fails.append("outline too small (%d)" % outline.size())
	elif not _is_convex(outline):
		fails.append("outline not convex")
	if is_equal_approx(q, 1.0):
		_check_silhouette_outline(silhouette, outline, fails)

	var zones := _zone_histogram(planes)
	if zones.get(0, 0) != 1:
		fails.append("expected 1 table plane, got %d" % zones.get(0, 0))
	if zones.get(6, 0) != 1:
		fails.append("expected 1 culet plane, got %d" % zones.get(6, 0))
	# Hull girdle planes: pruning may thin tips to knife-edge at low quality,
	# but a recognizable girdle band must survive. Outline fidelity is gated
	# separately (outline keeps all girdle lines regardless of pruning).
	var girdle_count: int = zones.get(3, 0)
	if girdle_count < 3 or girdle_count > 48:
		fails.append("girdle count %d out of [3, 48]" % girdle_count)

	# Actual pavilion angle vs explicit design.
	var solved: float = template.parameters.pavilion
	var pav_angles := _pavilion_angles(planes, 4 if template_name == "brilliant" else 7)
	if pav_angles.is_empty():
		fails.append("no pavilion planes found")
	elif template_name == "brilliant":
		for a in pav_angles:
			if absf(a - solved) > 0.5:
				fails.append("pavilion main %.2f deg vs authored %.2f (>0.5)" % [a, solved])
				break
	else:
		var deepest := _min_of(pav_angles)
		if absf(deepest - solved) > 0.5:
			fails.append("deepest step row %.2f deg vs authored %.2f (>0.5)" % [deepest, solved])

	# Determinism: same seed -> byte-identical output.
	var again: Dictionary = CutCompiler.compile(template, GemShape.faceted_outline(silhouette), SEED_A, Vector4(2.8, 0.4, 0.004, 0.006) * (1.0 - q))
	if planes != again["planes"] or outline != again["outline"]:
		fails.append("same seed produced different output")

	var other: Dictionary = CutCompiler.compile(template, GemShape.faceted_outline(silhouette), SEED_B, Vector4(2.8, 0.4, 0.004, 0.006) * (1.0 - q))
	if is_equal_approx(q, 1.0):
		# q = 1: zero jitter -> output independent of seed, planes exactly regular.
		if planes != other["planes"]:
			fails.append("q=1 output depends on seed (jitter not zero)")
		if not _angles_regular(pav_angles, solved, template_name):
			fails.append("q=1 pavilion angles not exactly regular")
	elif q < 0.99:
		if planes == other["planes"]:
			fails.append("different seed produced identical jitter")

	var mean_pav := _mean_of(pav_angles)
	if fails.is_empty():
		_pass_count += 1
		print("  PASS %-26s planes=%3d girdle=%2d pav=%5.2f (authored %5.2f)" % [
			label, plane_count, girdle_count, mean_pav, solved])
	else:
		_fail_count += 1
		_failed_cases.append(label)
		print("  FAIL %-26s planes=%3d girdle=%2d pav=%5.2f (authored %5.2f)" % [
			label, plane_count, girdle_count, mean_pav, solved])
		for f in fails:
			print("       - " + f)


# ------------------------------------------------------------------ checks

func _is_bounded(planes: PackedFloat32Array) -> bool:
	var count := planes.size() / 8
	if count < 4:
		return false
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and y == 0 and z == 0:
					continue
				var u := Vector3(x, y, z).normalized()
				var best := -1.0
				for i in count:
					var dot := planes[i * 8] * u.x + planes[i * 8 + 1] * u.y + planes[i * 8 + 2] * u.z
					best = maxf(best, dot)
				if best < 0.02:
					return false
	return true


func _is_convex(outline: PackedVector2Array) -> bool:
	var n := outline.size()
	if n < 3:
		return false
	for i in n:
		var e0 := outline[(i + 1) % n] - outline[i]
		var e1 := outline[(i + 2) % n] - outline[(i + 1) % n]
		if e0.length() < 1.0e-9 or e1.length() < 1.0e-9:
			continue
		if e0.normalized().cross(e1.normalized()) < -1.0e-4:
			return false
	return true


## q=1 polygon outlines: k long flats plus symmetric Minkowski corner arcs.
## Smooth silhouettes are mirror-symmetric across X (half-offset support ring).
func _check_silhouette_outline(silhouette: StringName, outline: PackedVector2Array,
		fails: PackedStringArray) -> void:
	match silhouette:
		&"square", &"rectangle":
			var expect := 4 * (1 + SilhouetteLib.CORNER_ARC_SAMPLES)
			if outline.size() != expect:
				fails.append("%s outline %d verts, expected %d (4 edges + arcs)" % [
					silhouette, outline.size(), expect])
				return
			if _count_long_axis_flats(outline) != 4:
				fails.append("%s missing 4 long axis-aligned flats" % silhouette)
			if not _mirror_x(outline) or not _mirror_y(outline):
				fails.append("%s outline is not axis-mirror symmetric" % silhouette)
		&"diamond":
			var expect := 4 * (1 + SilhouetteLib.CORNER_ARC_SAMPLES)
			if outline.size() != expect:
				fails.append("diamond outline %d verts, expected %d" % [outline.size(), expect])
				return
			if not _mirror_x(outline) or not _mirror_y(outline):
				fails.append("diamond outline is not axis-mirror symmetric")
		&"triangle":
			var expect := 3 * (1 + SilhouetteLib.CORNER_ARC_SAMPLES)
			if outline.size() != expect:
				fails.append("triangle outline %d verts, expected %d" % [outline.size(), expect])
			elif not _mirror_x(outline):
				fails.append("triangle outline is not mirror-symmetric across X")
		&"pear", &"oval", &"marquise", &"round":
			if not _mirror_x(outline):
				fails.append("%s outline is not mirror-symmetric across X" % silhouette)


func _count_long_axis_flats(outline: PackedVector2Array) -> int:
	var n := outline.size()
	var flats := 0
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		if a.distance_to(b) < 0.25:
			continue
		if absf(a.x - b.x) < 1.0e-3 or absf(a.y - b.y) < 1.0e-3:
			flats += 1
	return flats


func _mirror_x(outline: PackedVector2Array) -> bool:
	return _has_mirrors(outline, true, false)


func _mirror_y(outline: PackedVector2Array) -> bool:
	return _has_mirrors(outline, false, true)


func _has_mirrors(outline: PackedVector2Array, flip_y: bool, flip_x: bool) -> bool:
	for p in outline:
		var want := Vector2(-p.x if flip_x else p.x, -p.y if flip_y else p.y)
		var found := false
		for q in outline:
			if q.distance_to(want) < 0.02:
				found = true
				break
		if not found:
			return false
	return true


func _zone_histogram(planes: PackedFloat32Array) -> Dictionary:
	var zones := {}
	for i in planes.size() / 8:
		var z := int(planes[i * 8 + 4])
		zones[z] = zones.get(z, 0) + 1
	return zones


## Angles (deg from the girdle plane) of downward-facing planes in a zone.
func _pavilion_angles(planes: PackedFloat32Array, zone: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in planes.size() / 8:
		if int(planes[i * 8 + 4]) != zone:
			continue
		var nz := planes[i * 8 + 2]
		if nz >= 0.0:
			continue
		var lateral := Vector2(planes[i * 8], planes[i * 8 + 1]).length()
		out.append(rad_to_deg(atan2(lateral, -nz)))
	return out


## q = 1 regularity: brilliant mains all exactly at the authored angle; step
## pavilion angles exactly on one of the row values (authored + k * delta).
func _angles_regular(angles: PackedFloat32Array, solved: float, template_name: String) -> bool:
	if template_name == "brilliant":
		for a in angles:
			if absf(a - solved) > 1.0e-3:
				return false
		return true
	for a in angles:
		var on_row := false
		for k in 4:
			if absf(a - (solved + 7.0 * float(k))) <= 1.0e-3:
				on_row = true
				break
		if not on_row:
			return false
	return true


func _min_of(values: PackedFloat32Array) -> float:
	var m := INF
	for v in values:
		m = minf(m, v)
	return m


func _mean_of(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / float(values.size())
