extends SceneTree
## Headless test for the Lapidary cut compiler (pure CPU, no RenderingDevice).
## Run:
##   godot --headless --path . --script res://tests/lapidary/test_cut_compiler.gd
##
## Battery: 8 silhouettes x brilliant x quality {0.15, 0.6, 1.0} plus
## {square, rectangle} x step x same qualities. Asserts: bounded hull, sane
## plane count, non-empty convex outline, solved pavilion angle within 0.5 deg
## of LapidaryStoneCompiler.solve_pavilion_deg, exact regularity at q = 1
## (zero jitter), determinism (same seed -> identical output; different seed
## -> different jitter), and zero compiler warnings. Planes with exactly-empty
## faces are PRUNED by the compiler (sliver facets erased by meeting error,
## fan facets that cannot fit a pointed silhouette); the hull girdle count may
## drop at tips (knife-edge) while the 2D outline keeps every girdle line.

const CutCompiler := preload("res://core/lapidary/cut/cut_compiler.gd")
const StoneCompilerScript := preload("res://core/lapidary/stone_compiler.gd")

const IOR := 1.76
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
		quit(1)
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
	quit(1 if _fail_count > 0 else 0)


func _exercise(template: Resource, template_name: String, silhouette: StringName, q: float) -> void:
	var label := "%s/%s q=%.2f" % [template_name, silhouette, q]
	var fails := PackedStringArray()
	var result: Dictionary = CutCompiler.compile(template, silhouette, IOR, q, SEED_A)
	var planes: PackedFloat32Array = result["planes"]
	var outline: PackedVector2Array = result["outline"]
	var plane_count := planes.size() / 8

	if planes.is_empty() or planes.size() % 8 != 0:
		fails.append("planes empty/malformed")
	if plane_count < 20 or plane_count > 140:
		fails.append("plane count %d out of [20, 140]" % plane_count)
	if not _is_bounded(planes):
		fails.append("hull unbounded")
	if outline.size() < 8:
		fails.append("outline too small (%d)" % outline.size())
	elif not _is_convex(outline):
		fails.append("outline not convex")
	if not result.get("warnings", PackedStringArray()).is_empty():
		fails.append("compiler warnings: %s" % ", ".join(result["warnings"]))

	var zones := _zone_histogram(planes)
	if zones.get(0, 0) != 1:
		fails.append("expected 1 table plane, got %d" % zones.get(0, 0))
	if zones.get(6, 0) != 1:
		fails.append("expected 1 culet plane, got %d" % zones.get(6, 0))
	# Hull girdle planes: pruning may thin tips to knife-edge at low quality,
	# but a recognizable girdle band must survive. Outline fidelity is gated
	# separately (outline keeps all girdle lines regardless of pruning).
	var girdle_count: int = zones.get(3, 0)
	if girdle_count < 6 or girdle_count > 48:
		fails.append("girdle count %d out of [6, 48]" % girdle_count)

	# Solved pavilion angle vs the solver law.
	var solved: float = StoneCompilerScript.solve_pavilion_deg(IOR, q)
	var pav_angles := _pavilion_angles(planes, 4 if template_name == "brilliant" else 7)
	if pav_angles.is_empty():
		fails.append("no pavilion planes found")
	elif template_name == "brilliant":
		for a in pav_angles:
			if absf(a - solved) > 0.5:
				fails.append("pavilion main %.2f deg vs solver %.2f (>0.5)" % [a, solved])
				break
	else:
		var deepest := _min_of(pav_angles)
		if absf(deepest - solved) > 0.5:
			fails.append("deepest step row %.2f deg vs solver %.2f (>0.5)" % [deepest, solved])

	# Determinism: same seed -> byte-identical output.
	var again: Dictionary = CutCompiler.compile(template, silhouette, IOR, q, SEED_A)
	if planes != again["planes"] or outline != again["outline"]:
		fails.append("same seed produced different output")

	var other: Dictionary = CutCompiler.compile(template, silhouette, IOR, q, SEED_B)
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
		print("  PASS %-26s planes=%3d girdle=%2d pav=%5.2f (solver %5.2f)" % [
			label, plane_count, girdle_count, mean_pav, solved])
	else:
		_fail_count += 1
		_failed_cases.append(label)
		print("  FAIL %-26s planes=%3d girdle=%2d pav=%5.2f (solver %5.2f)" % [
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


## q = 1 regularity: brilliant mains all exactly at the solver angle; step
## pavilion angles exactly on one of the row values (solver + k * delta).
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
