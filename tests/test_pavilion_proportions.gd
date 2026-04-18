extends SceneTree

## Measures crown vs pavilion depth share from GemPavilionSolver (auto crown path).
## Run: godot --headless --script tests/test_pavilion_proportions.gd
##
## The auto solver should preserve a materially visible crown for typical cuts
## instead of collapsing toward a shallow ~1/6 profile.

const GemPavilionSolver = preload("res://core/visuals/gem_pavilion_solver.gd")

const CUT_IDS: Array[StringName] = [
	&"classic_round",
	&"old_european_round",
	&"princess_square",
	&"oval_brilliant",
	&"emerald_step",
	&"cushion",
]

const IOR := 1.62

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("\n=== Pavilion proportion audit (GemPavilionSolver) ===\n")

	var ratios: Array[float] = []
	var shallow_warn := 0

	var spec_library = load("res://core/visuals/gem_cut_spec_library.gd").new()
	for cut_id in CUT_IDS:
		var spec = spec_library.get_spec(cut_id)
		if spec == null:
			_fail_count += 1
			push_error("No spec for %s" % str(cut_id))
			continue
		var params = GemPavilionSolver.resolve(spec, IOR)
		var crown: float = float(params.get("crown_height", 0.0))
		var girdle: float = float(params.get("girdle_thickness", 0.0))
		var depth: float = float(params.get("pavilion_depth", 0.0))
		var total: float = crown + girdle + depth
		var ratio: float = crown / total if total > 1e-6 else 0.0
		ratios.append(ratio)
		var report = GemPavilionSolver.validate_optics(params, IOR)
		for w in report.get("warnings", []):
			if String(w).find("unusually flat") != -1:
				shallow_warn += 1
		print(
			"  %s  crown/total=%.3f  (c=%.4f g=%.4f p=%.4f)  pav°=%.1f"
			% [str(cut_id), ratio, crown, girdle, depth, float(params.get("effective_pavilion_angle_deg", 0.0))]
		)

	ratios.sort()
	var median: float = ratios[ratios.size() / 2] if not ratios.is_empty() else 0.0
	var sum := 0.0
	for r in ratios:
		sum += r
	var mean: float = sum / float(ratios.size()) if not ratios.is_empty() else 0.0

	print("\n  cuts=%d  median_crown_ratio=%.3f  mean_crown_ratio=%.3f  shallow_crown_warnings=%d\n" % [
		CUT_IDS.size(), median, mean, shallow_warn,
	])

	# Regression guard: the auto solver should stay meaningfully above the shallow-crown
	# warning band for representative cuts while still remaining in a plausible range.
	assert_true(not ratios.is_empty(), "ratios collected")
	assert_true(median > 0.20 and median < 0.40, "median crown ratio stays above shallow-compression band")
	assert_true(mean > 0.20 and mean < 0.40, "mean crown ratio stays above shallow-compression band")
	assert_true(shallow_warn == 0, "representative cuts should avoid shallow-crown warnings")

	print("=== Results: %d passed, %d failed ===\n" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func assert_true(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % msg)
