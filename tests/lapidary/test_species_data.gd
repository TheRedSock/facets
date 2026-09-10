extends SceneTree

## Headless validation of the lapidary SPECIES / CHROMOPHORE / GRADE / STONE
## data layer (data/lapidary/). Run:
##   godot --headless --script tests/lapidary/test_species_data.gd
##
## Asserts: published n_D and gemological (B-G) dispersion per species, curve
## shape invariants (81 samples, non-negative, finite), grade ramp sanity,
## stone_id == TileRegistry tile_id, and fingerprint uniqueness + stability.

const DIR_SPECIES := "res://data/lapidary/species/"
const DIR_CHROMO := "res://data/lapidary/chromophores/"
const DIR_GRADES := "res://data/lapidary/grades/"
const DIR_STONES := "res://data/lapidary/stones/"

const WL_D := 589.3
const WL_F := 486.1
const WL_C := 656.3
const WL_B := 686.7
const WL_G := 430.8

## Published values (see docs/lapidary-spectra-sources.md for citations).
const ND_TARGETS := {
	&"quartz": 1.544,      # Ghosh 1999 alpha-quartz o-ray
	&"olivine": 1.654,     # gem peridot n_alpha (RI 1.654-1.690)
	&"topaz": 1.612,       # F-rich topaz (1.606-1.644)
	&"corundum": 1.768,    # Malitson & Dodge 1972 o-ray
	&"beryl": 1.577,       # natural emerald n_omega (1.575-1.600)
	&"diamond": 2.417,     # Peter 1923 (lit. n_D 2.41726)
	&"fluorite": 1.4338,   # Malitson 1963 CaF2
	&"chrysoberyl": 1.746, # GIA alexandrite RI 1.746-1.755
	&"garnet": 1.760,      # rhodolite pyralspite
	&"elbaite": 1.635,     # tourmaline n_omega 1.635-1.650
	&"painite": 1.80,      # n_omega 1.7875-1.8159
}
const ND_TOLERANCE := 0.012

const DISPERSION_BG_TARGETS := {
	&"quartz": 0.013, &"olivine": 0.020, &"topaz": 0.014,
	&"corundum": 0.018, &"beryl": 0.014, &"diamond": 0.044,
	&"fluorite": 0.007, &"chrysoberyl": 0.015, &"garnet": 0.026,
	&"elbaite": 0.018, &"painite": 0.018,
}
const DISPERSION_TOLERANCE := 0.005

const EXPECTED_SPECIES_COUNT := 11
const EXPECTED_CHROMOPHORE_COUNT := 14
const EXPECTED_STONE_COUNT := 16
const COLORLESS_STONES := [&"quartz", &"diamond"]
## T6 rectangle tier carries the step cut (emerald cut IS the step cut).
const STEP_CUT_STONES := [&"emerald", &"alexandrite"]

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("\n=== Lapidary Species Data Tests ===\n")

	var species := _load_dir(DIR_SPECIES)
	var chromophores := _load_dir(DIR_CHROMO)
	var grades := _load_dir(DIR_GRADES)
	var stones := _load_dir(DIR_STONES)

	_check(species.size() == EXPECTED_SPECIES_COUNT,
		"expected %d species, got %d" % [EXPECTED_SPECIES_COUNT, species.size()])
	_check(chromophores.size() == EXPECTED_CHROMOPHORE_COUNT,
		"expected %d chromophores, got %d" % [EXPECTED_CHROMOPHORE_COUNT, chromophores.size()])
	_check(grades.size() == 8, "expected 8 grades, got %d" % grades.size())
	_check(stones.size() == EXPECTED_STONE_COUNT, "expected %d stones, got %d" % [EXPECTED_STONE_COUNT, stones.size()])

	_test_species(species)
	_test_chromophores(chromophores)
	_test_grades(grades)
	_test_stones(stones)
	_test_compiler_consumption(stones)
	_print_dispersion_table(species)

	print("\n=== Results: %d passed, %d failed ===\n" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


# ------------------------------------------------------------------ species

func _test_species(species: Dictionary) -> void:
	for path: String in species:
		var sp: Resource = species[path]
		var label := path.get_file()
		var id: StringName = sp.get("species_id")
		_check(id != &"", "%s: species_id must be non-empty" % label)
		_check(ND_TARGETS.has(id), "%s: unexpected species_id '%s'" % [label, id])
		if not ND_TARGETS.has(id):
			continue

		var n_d: float = sp.ior_at(WL_D)
		var target: float = ND_TARGETS[id]
		_check(absf(n_d - target) <= ND_TOLERANCE,
			"%s: n_D %.4f differs from published %.4f by more than %.3f" % [label, n_d, target, ND_TOLERANCE])

		var disp_bg: float = sp.ior_at(WL_G) - sp.ior_at(WL_B)
		var disp_target: float = DISPERSION_BG_TARGETS[id]
		_check(absf(disp_bg - disp_target) <= DISPERSION_TOLERANCE,
			"%s: B-G dispersion %.4f differs from published %.4f" % [label, disp_bg, disp_target])

		_check(sp.ior_at(380.0) > sp.ior_at(780.0),
			"%s: normal dispersion requires n(380) > n(780)" % label)
		_check(sp.get("birefringence") >= 0.0, "%s: birefringence must be >= 0" % label)
		_check(sp.get("hardness_mohs") > 1.0 and sp.get("hardness_mohs") <= 10.0,
			"%s: hardness_mohs out of range" % label)
		_check(sp.get("source_note") != "", "%s: source_note (citation) required" % label)

		var inclusions: Array = sp.get("inclusions")
		_check(not inclusions.is_empty(), "%s: inclusion vocabulary must not be empty" % label)
		for arch: Resource in inclusions:
			var arch_label := "%s/%s" % [label, arch.get("archetype_id")]
			var size_range: Vector2 = arch.get("size_mm_range")
			_check(size_range.x > 0.0 and size_range.y >= size_range.x,
				"%s: size_mm_range invalid %s" % [arch_label, size_range])
			_check(arch.get("weight") > 0.0, "%s: weight must be > 0" % arch_label)
			_check(arch.get("scatter_density") > 0.0, "%s: scatter_density must be > 0" % arch_label)


# ------------------------------------------------------------------ chromophores

func _test_chromophores(chromophores: Dictionary) -> void:
	for path: String in chromophores:
		var chromo: Resource = chromophores[path]
		var label := path.get_file()
		_check(chromo.get("chromophore_id") != &"", "%s: chromophore_id must be non-empty" % label)
		_check(chromo.get("source_note") != "", "%s: source_note (citation) required" % label)
		_check(chromo.get("concentration") > 0.0, "%s: concentration must be > 0" % label)
		_check_curve(chromo.get("absorption_mm"), "%s absorption_mm" % label, false)
		_check_curve(chromo.get("absorption_eray_mm"), "%s absorption_eray_mm" % label, true)
		# Every shipped chromophore file exists to carry colour.
		_check(not chromo.get("absorption_mm").is_empty(),
			"%s: colored chromophore must have a non-empty o-ray curve" % label)


func _check_curve(curve: PackedFloat32Array, label: String, allow_empty: bool) -> void:
	if curve.is_empty():
		_check(allow_empty, "%s: curve must not be empty" % label)
		return
	_check(curve.size() == 81, "%s: expected 81 samples, got %d" % [label, curve.size()])
	var all_valid := true
	for i in curve.size():
		if is_nan(curve[i]) or is_inf(curve[i]) or curve[i] < 0.0:
			all_valid = false
			break
	_check(all_valid, "%s: samples must be finite and non-negative" % label)


# ------------------------------------------------------------------ grades

func _test_grades(grades: Dictionary) -> void:
	var by_tier := {}
	for path: String in grades:
		var grade: Resource = grades[path]
		var label := path.get_file()
		for axis in ["cut", "clarity", "surface", "crystal"]:
			var v: float = grade.get(axis)
			_check(v >= 0.0 and v <= 1.0, "%s: %s out of [0,1]" % [label, axis])
		var tier := label.trim_suffix(".tres").trim_prefix("t").to_int()
		by_tier[tier] = grade

	for tier in range(2, 9):
		if not (by_tier.has(tier) and by_tier.has(tier - 1)):
			continue
		for axis in ["cut", "clarity", "surface", "crystal"]:
			_check(by_tier[tier].get(axis) > by_tier[tier - 1].get(axis),
				"grade t%d.%s must rise above t%d" % [tier, axis, tier - 1])
	if by_tier.has(1):
		for axis in ["cut", "clarity", "surface", "crystal"]:
			var v: float = by_tier[1].get(axis)
			_check(v >= 0.52 and v <= 0.72, "t1 %s should be the compressed floor (0.52-0.72), got %.2f" % [axis, v])
	if by_tier.has(8):
		for axis in ["cut", "clarity", "surface", "crystal"]:
			_check(by_tier[8].get(axis) == 1.0, "t8 %s must be 1.0" % axis)


# ------------------------------------------------------------------ stones

func _test_stones(stones: Dictionary) -> void:
	var registry := _tile_registry()
	_check(registry != null and registry.has_definitions(),
		"TileRegistry must be available headless with loaded definitions")

	var fingerprints := {}
	var size_by_tier := {}
	for path: String in stones:
		var stone: GemStone = stones[path]
		var label := path.get_file()
		var stone_id: StringName = stone.get("stone_id")

		_check(stone.material.species != null, "%s: species must be set" % label)
		_check(stone.get("grade") != null, "%s: grade must be set" % label)
		var cut: Resource = stone.get("cut")
		_check(cut != null, "%s: cut template must be assigned" % label)
		if cut != null:
			var want_step := stone_id in STEP_CUT_STONES
			var is_step := cut.resource_path.get_file().begins_with("step")
			_check(is_step == want_step,
				"%s: expected %s cut, got %s" % [label, "step" if want_step else "brilliant", cut.resource_path.get_file()])
		_check(stone.shape != null and stone.shape.outline != &"", "%s: silhouette must be set" % label)
		var size_mm: float = stone.get("size_mm")
		_check(size_mm >= 4.4 and size_mm <= 5.6, "%s: size_mm %.2f outside 4.5-5.5 band" % [label, size_mm])
		if stone_id in COLORLESS_STONES:
			_check(stone.material.chromophore == null, "%s: must be colorless (null chromophore)" % label)
		else:
			_check(stone.material.chromophore != null, "%s: colored stone needs a chromophore" % label)

		# stone_id must be a real tile_id, and the filename must match it.
		_check(label.trim_suffix(".tres") == String(stone_id),
			"%s: filename must equal stone_id '%s'" % [label, stone_id])
		if registry != null:
			var definition = registry.get_definition(stone_id)
			_check(definition != null, "%s: stone_id '%s' is not a TileRegistry tile_id" % [label, stone_id])
			if definition != null:
				size_by_tier[definition.tier] = size_mm

		# Fingerprint: stable across two independent loads, unique across stones.
		var load_a: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var load_b: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(load_a != load_b, "%s: CACHE_MODE_IGNORE should produce distinct instances" % label)
		var fp_a: String = load_a.fingerprint()
		var fp_b: String = load_b.fingerprint()
		_check(fp_a == fp_b and fp_a != "", "%s: fingerprint must be stable across loads" % label)
		_check(not fingerprints.has(fp_a),
			"%s: fingerprint collides with %s" % [label, fingerprints.get(fp_a, "?")])
		fingerprints[fp_a] = label

	# size_mm rises with tier (T1 4.5 -> T8 5.5).
	var tiers := size_by_tier.keys()
	tiers.sort()
	for i in range(1, tiers.size()):
		_check(size_by_tier[tiers[i]] > size_by_tier[tiers[i - 1]],
			"size_mm must rise with tier (t%d %.2f <= t%d %.2f)" % [
				tiers[i], size_by_tier[tiers[i]], tiers[i - 1], size_by_tier[tiers[i - 1]]])


## The data layer exists to feed LapidaryStoneCompiler; a compile smoke proves
## the .tres round-trip (typed archetype arrays, curves, grade axes) end-to-end.
func _test_compiler_consumption(stones: Dictionary) -> void:
	for path: String in stones:
		var stone: GemStone = stones[path]
		var label := path.get_file()
		var instance: Dictionary = LapidaryStoneCompiler.compile(stone)
		_check(instance["planes"].size() > 0 and instance["planes"].size() % 8 == 0,
			"%s: compiled hull must have plane records (stride 8)" % label)
		_check(instance["absorption"].size() == 81, "%s: compiled absorption must be 81 samples" % label)
		_check(instance["fingerprint"] == stone.fingerprint(),
			"%s: compiled fingerprint must match the stone's" % label)
		var strong: bool = instance["dispersion_strong"]
		if stone.get("stone_id") == &"diamond":
			_check(strong, "diamond must flag dispersion_strong (F-C 0.0256 >= 0.025)")
		else:
			_check(not strong, "%s: only diamond crosses the dispersion_strong gate" % label)


func _tile_registry() -> Node:
	var registry := root.get_node_or_null("TileRegistry")
	if registry != null:
		return registry
	# --script runs normally provide autoloads; fall back to a manual instance
	# of the real autoload script if the engine ever changes that behaviour.
	print("  note: TileRegistry autoload absent, instantiating manually")
	registry = load("res://autoloads/tile_registry.gd").new()
	registry.name = "TileRegistry"
	root.add_child(registry)
	return registry


# ------------------------------------------------------------------ report

func _print_dispersion_table(species: Dictionary) -> void:
	print("\nspecies      n_D      n(486)   n(656)   n(486)-n(656)   B-G")
	var rows := []
	for path: String in species:
		rows.append(species[path])
	rows.sort_custom(func(a, b): return String(a.get("species_id")) < String(b.get("species_id")))
	for sp: Resource in rows:
		print("%-12s %.4f   %.4f   %.4f   %.4f          %.4f" % [
			sp.get("species_id"), sp.ior_at(WL_D), sp.ior_at(WL_F), sp.ior_at(WL_C),
			sp.ior_at(WL_F) - sp.ior_at(WL_C), sp.ior_at(WL_G) - sp.ior_at(WL_B)])


# ------------------------------------------------------------------ plumbing

func _load_dir(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_check(false, "cannot open %s" % dir_path)
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := dir_path + file_name
			var res := load(path)
			if res == null:
				_check(false, "failed to load %s" % path)
			else:
				out[path] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s" % message)
