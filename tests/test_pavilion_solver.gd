extends SceneTree

## Headless tests for the pavilion automation pipeline.
## Run: godot --headless --script tests/test_pavilion_solver.gd
##
## Covers: GemPavilionSolver math, GemPavilionBuilder construction,
## IOR-driven compilation across all 32 cut specs, flat culet geometry,
## and per-gem geometry signature variation.

const GemPavilionSolverScript = preload("res://core/visuals/gem_pavilion_solver.gd")
const GemCutSpecLibrary = preload("res://core/visuals/gem_cut_spec_library.gd")
const GemCutCompiler3DScript = preload("res://core/visuals/gem_cut_compiler_3d.gd")
const GemGeometryValidatorScript = preload("res://core/visuals/gem_geometry_validator.gd")

const ALL_SPEC_IDS: Array[StringName] = [
	&"classic_round", &"old_european_round", &"simple_octagon_step",
	&"cushion", &"opal_cushion", &"patterned_cushion",
	&"heart_brilliant", &"trillion", &"straight_trillion",
	&"princess_square", &"lozenge", &"lozenge_radiant",
	&"kite_brilliant", &"shield_brilliant", &"radiant_square",
	&"radiant_octagon", &"hex_brilliant", &"hexagon_step",
	&"pentagon_brilliant", &"emerald_step", &"asscher_step",
	&"octagon_step", &"baguette_step", &"tapered_baguette_step",
	&"oval_brilliant", &"antique_oval", &"marquise_brilliant",
	&"pear_brilliant", &"rose_round", &"half_dutch_rose_hex",
	&"double_rose", &"cross_rose",
]

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	print("\n=== Pavilion Solver & Builder Tests ===\n")

	# Solver math tests
	test_critical_angle_known_values()
	test_pavilion_angle_known_gems()
	test_angle_to_depth_round_trip()
	test_solver_resolve_defaults()
	test_solver_respects_overrides()
	test_solver_crown_height_clamping()

	# Optical validation tests
	test_optics_validation_pass()
	test_optics_validation_fail()

	# Per-gem IOR variation
	test_ior_produces_different_signatures()

	# Full pipeline: compile every spec with default IOR
	test_compile_all_specs_default_ior()

	# Flat culet
	test_flat_culet_old_european()

	# Proportion validation
	test_proportion_validation()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


# ---- Solver Math ----


func test_critical_angle_known_values() -> void:
	# Diamond: IOR 2.42 -> theta_c ~24.4 degrees
	var diamond_angle := rad_to_deg(GemPavilionSolverScript.compute_critical_angle(2.42))
	assert_range(diamond_angle, 24.0, 25.0, "Diamond critical angle should be ~24.4")

	# Quartz: IOR 1.544 -> theta_c ~40.4 degrees
	var quartz_angle := rad_to_deg(GemPavilionSolverScript.compute_critical_angle(1.544))
	assert_range(quartz_angle, 40.0, 41.0, "Quartz critical angle should be ~40.4")

	# IOR = 1.0 -> theta_c = 90 degrees (no TIR)
	var air_angle := rad_to_deg(GemPavilionSolverScript.compute_critical_angle(1.0))
	assert_range(air_angle, 89.0, 91.0, "IOR 1.0 critical angle should be ~90")


func test_pavilion_angle_known_gems() -> void:
	# Diamond (2.42) -> ~40.7 degrees
	var diamond := GemPavilionSolverScript.compute_target_pavilion_angle_deg(2.42)
	assert_range(diamond, 40.0, 42.0, "Diamond pavilion angle should be ~40.7")

	# Quartz (1.544) -> ~43.4 degrees
	var quartz := GemPavilionSolverScript.compute_target_pavilion_angle_deg(1.544)
	assert_range(quartz, 42.5, 44.5, "Quartz pavilion angle should be ~43.4")

	# Sapphire (1.76) -> ~42.7 degrees
	var sapphire := GemPavilionSolverScript.compute_target_pavilion_angle_deg(1.76)
	assert_range(sapphire, 42.0, 43.5, "Sapphire pavilion angle should be ~42.7")

	# Low IOR should be steeper, high IOR shallower
	var low := GemPavilionSolverScript.compute_target_pavilion_angle_deg(1.43)
	var high := GemPavilionSolverScript.compute_target_pavilion_angle_deg(2.42)
	assert_true(low > high, "Lower IOR should produce steeper pavilion angle")


func test_angle_to_depth_round_trip() -> void:
	var angle := 42.0
	var radius := 0.43
	var depth := GemPavilionSolverScript.angle_to_depth(angle, radius)
	var recovered := GemPavilionSolverScript.depth_to_angle_deg(depth, radius)
	assert_range(recovered, angle - 0.1, angle + 0.1, "Angle->depth->angle round trip")


func test_solver_resolve_defaults() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"classic_round")
	assert_true(spec != null, "classic_round spec should load")
	if spec == null:
		return

	var params := GemPavilionSolverScript.resolve(spec, 1.62)
	assert_true(params.has("pavilion_depth"), "Params should have pavilion_depth")
	assert_true(params.has("crown_height"), "Params should have crown_height")
	assert_true(params.has("culet_style"), "Params should have culet_style")
	assert_eq(params["culet_style"], "point", "Default culet should be point")

	var depth: float = params["pavilion_depth"]
	assert_range(depth, 0.2, 0.6, "Pavilion depth should be reasonable")

	var crown: float = params["crown_height"]
	assert_range(crown, 0.06, 0.32, "Crown height should be within clamps")


func test_solver_respects_overrides() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"classic_round")
	if spec == null:
		return
	# Override depth explicitly
	spec.pavilion["auto_depth"] = false
	spec.pavilion["depth"] = 0.5
	var params := GemPavilionSolverScript.resolve(spec, 2.42)
	var depth: float = params["pavilion_depth"]
	assert_range(depth, 0.49, 0.51, "Explicit depth override should be honored")


func test_solver_crown_height_clamping() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"classic_round")
	if spec == null:
		return
	# Very low IOR = very steep pavilion = compressed crown
	var params := GemPavilionSolverScript.resolve(spec, 1.2)
	var crown: float = params["crown_height"]
	assert_range(crown, GemPavilionSolverScript.MIN_CROWN_HEIGHT, GemPavilionSolverScript.MAX_CROWN_HEIGHT,
		"Crown height should be within solver clamps")


# ---- Optical Validation ----


func test_optics_validation_pass() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"classic_round")
	if spec == null:
		return
	var params := GemPavilionSolverScript.resolve(spec, 2.42)
	var report := GemPavilionSolverScript.validate_optics(params, 2.42)
	var errors: PackedStringArray = report.get("errors", PackedStringArray())
	assert_eq(errors.size(), 0, "Diamond pavilion should pass optical validation")


func test_optics_validation_fail() -> void:
	# Construct artificially shallow pavilion for low-IOR gem
	var params := {
		"effective_pavilion_angle_deg": 30.0,
		"pavilion_depth": 0.2,
		"crown_height": 0.18,
		"girdle_thickness": 0.012,
	}
	var report := GemPavilionSolverScript.validate_optics(params, 1.544)
	var errors: PackedStringArray = report.get("errors", PackedStringArray())
	assert_true(errors.size() > 0, "Shallow pavilion should fail optical validation for quartz")


# ---- IOR Variation ----


func test_ior_produces_different_signatures() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"classic_round")
	if spec == null:
		return

	var params_quartz := GemPavilionSolverScript.resolve(spec, 1.544)
	var params_diamond := GemPavilionSolverScript.resolve(spec, 2.42)

	# Different IOR should produce different pavilion depth
	var depth_q: float = params_quartz["pavilion_depth"]
	var depth_d: float = params_diamond["pavilion_depth"]
	assert_true(absf(depth_q - depth_d) > 0.01,
		"Different IOR should produce different pavilion depths (q=%.3f, d=%.3f)" % [depth_q, depth_d])

	# Build geometry signatures
	var spec_q = spec.duplicate_spec()
	spec_q.apply_pavilion_resolution(params_quartz)
	var spec_d = spec.duplicate_spec()
	spec_d.apply_pavilion_resolution(params_diamond)

	var sig_q = spec_q.build_geometry_signature()
	var sig_d = spec_d.build_geometry_signature()
	assert_true(sig_q != sig_d,
		"Different IOR should produce different geometry signatures")


# ---- Full Pipeline Compilation ----


func test_compile_all_specs_default_ior() -> void:
	var lib := GemCutSpecLibrary.new()
	var ior := 1.62
	for spec_id in ALL_SPEC_IDS:
		var spec = lib.get_spec(spec_id)
		if spec == null:
			_fail_count += 1
			print("  FAIL: Spec '%s' not found" % str(spec_id))
			continue
		var params := GemPavilionSolverScript.resolve(spec, ior)
		var resolved_spec = spec.duplicate_spec()
		resolved_spec.apply_pavilion_resolution(params)
		var model = GemCutCompiler3DScript.compile_spec(resolved_spec, params)
		if model == null:
			_fail_count += 1
			print("  FAIL: '%s' failed to compile with auto-pavilion" % str(spec_id))
		else:
			var facet_count: int = model.facet_count()
			if facet_count < 10:
				_fail_count += 1
				print("  FAIL: '%s' compiled but has only %d facets" % [str(spec_id), facet_count])
			else:
				_pass_count += 1
				print("  PASS: '%s' compiled OK (%d facets, depth=%.3f, crown=%.3f)" % [
					str(spec_id), facet_count, model.pavilion_depth, model.crown_height])


# ---- Flat Culet ----


func test_flat_culet_old_european() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"old_european_round")
	if spec == null:
		_fail_count += 1
		print("  FAIL: old_european_round spec not found")
		return

	assert_eq(spec.get_culet_style(), "flat", "OEC culet style should be 'flat'")

	var params := GemPavilionSolverScript.resolve(spec, 1.62)
	assert_eq(params["culet_style"], "flat", "Solver should preserve flat culet style")
	assert_true(int(params["culet_flat_sides"]) >= 3, "Flat culet should have >= 3 sides")

	var resolved_spec = spec.duplicate_spec()
	resolved_spec.apply_pavilion_resolution(params)
	var model = GemCutCompiler3DScript.compile_spec(resolved_spec, params)
	assert_true(model != null, "OEC should compile with flat culet")
	if model == null:
		return

	# Check that culet zone facets exist
	var culet_facets := 0
	for i in model.facet_count():
		if model.facet_zones[i] == &"culet":
			culet_facets += 1
	assert_true(culet_facets > 0, "OEC model should have culet-zone facets")

	# Flat culet should have at least one polygon facet (the flat face)
	# plus connecting facets. Standard point culet has only triangles.
	# For flat culet, the flat face polygon has >= 3 vertices.
	var found_flat_face := false
	for i in model.facet_count():
		if model.facet_zones[i] == &"culet":
			var verts: PackedVector3Array = model.facet_vertices[i]
			# The flat culet polygon has all vertices at the same Z
			if verts.size() >= 3:
				var z_min := verts[0].z
				var z_max := verts[0].z
				for v in verts:
					z_min = minf(z_min, v.z)
					z_max = maxf(z_max, v.z)
				if z_max - z_min < 0.001:
					found_flat_face = true
					break
	assert_true(found_flat_face, "OEC should have a flat culet face (coplanar polygon)")


# ---- Proportion Validation ----


func test_proportion_validation() -> void:
	var lib := GemCutSpecLibrary.new()
	var spec = lib.get_spec(&"classic_round")
	if spec == null:
		return
	var params := GemPavilionSolverScript.resolve(spec, 1.62)
	var resolved_spec = spec.duplicate_spec()
	resolved_spec.apply_pavilion_resolution(params)
	var model = GemCutCompiler3DScript.compile_spec(resolved_spec, params)
	if model == null:
		return
	var report := GemGeometryValidatorScript.validate_proportions(model)
	var warnings: PackedStringArray = report.get("warnings", PackedStringArray())
	# Default IOR with classic_round should produce reasonable proportions
	for warning in warnings:
		print("    Proportion warning: %s" % warning)
	# Not asserting zero warnings — just checking it doesn't crash.
	_pass_count += 1
	print("  PASS: Proportion validation completed for classic_round")


# ---- Assertion Helpers ----


func assert_true(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s" % msg)


func assert_false(condition: bool, msg: String) -> void:
	assert_true(not condition, msg)


func assert_eq(a: Variant, b: Variant, msg: String) -> void:
	if a == b:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s (got %s, expected %s)" % [msg, str(a), str(b)])


func assert_range(value: float, min_val: float, max_val: float, msg: String) -> void:
	if value >= min_val and value <= max_val:
		_pass_count += 1
		print("  PASS: %s (%.4f)" % [msg, value])
	else:
		_fail_count += 1
		print("  FAIL: %s (got %.4f, expected [%.4f, %.4f])" % [msg, value, min_val, max_val])
