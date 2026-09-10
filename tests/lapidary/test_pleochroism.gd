extends SceneTree
## Pleochroism / optic-axis conventions (CPU only).
##
## GIA dichroism mixing for unpolarised light through a uniaxial stone:
##   Along the optic axis (θ = 0): transmission is pure o-ray (To).
##   At angle θ to the optic axis, the e-ray absorption is the projected mix
##     alpha_k = c²·α_o + s²·α_e    (c² = cos²θ, s² = sin²θ)
##   and unpolarised transmittance is
##     T = 0.5·To + 0.5·Tk
##   with To = exp(-α_o·path), Tk = exp(-alpha_k·path).
##
## Run: godot --headless --script tests/lapidary/test_pleochroism.gd

var _pass := 0
var _fail := 0


func _init() -> void:
	print("\n=== Pleochroism / optic-axis tests ===\n")
	_test_gia_mixing_math()
	_test_species_optic_axes()
	_test_ruby_compiler()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS %s" % name)
	else:
		_fail += 1
		printerr("  FAIL %s" % name)


## Pure-CPU helper: GIA unpolarised dichroism mix for one sample.
static func unpolarised_transmission(alpha_o: float, alpha_e: float,
		theta_rad: float, path_mm: float) -> Dictionary:
	var c2 := cos(theta_rad) * cos(theta_rad)
	var s2 := sin(theta_rad) * sin(theta_rad)
	var alpha_k := c2 * alpha_o + s2 * alpha_e
	var to := exp(-alpha_o * path_mm)
	var tk := exp(-alpha_k * path_mm)
	return {
		"alpha_k": alpha_k,
		"To": to,
		"Tk": tk,
		"T": 0.5 * to + 0.5 * tk,
	}


func _test_gia_mixing_math() -> void:
	print("[GIA mixing]")
	# Along axis: pure o-ray regardless of α_e.
	var along := unpolarised_transmission(0.5, 2.0, 0.0, 1.0)
	_check(is_equal_approx(along["alpha_k"], 0.5), "θ=0: alpha_k == alpha_o")
	_check(is_equal_approx(along["T"], along["To"]), "θ=0: T == To (pure o-ray)")

	# Perpendicular: alpha_k == alpha_e; T = 0.5 To + 0.5 Te.
	var perp := unpolarised_transmission(0.5, 2.0, PI * 0.5, 1.0)
	_check(is_equal_approx(perp["alpha_k"], 2.0), "θ=90°: alpha_k == alpha_e")
	var te := exp(-2.0)
	var to := exp(-0.5)
	_check(is_equal_approx(perp["T"], 0.5 * to + 0.5 * te),
		"θ=90°: T == 0.5 To + 0.5 Te")

	# Mid angle: alpha_k = 0.5 α_o + 0.5 α_e when θ = 45°.
	var mid := unpolarised_transmission(0.4, 1.2, deg_to_rad(45.0), 2.0)
	_check(absf(mid["alpha_k"] - 0.8) < 1e-6, "θ=45°: alpha_k = 0.5 ao + 0.5 ae")
	_check(mid["T"] > mid["Tk"] and mid["T"] < mid["To"],
		"θ=45°: T lies between Tk and To when ae > ao")


func _test_species_optic_axes() -> void:
	print("[species optic_axis_stone]")
	var corundum := load("res://data/lapidary/species/corundum.tres") as GemSpecies
	var elbaite := load("res://data/lapidary/species/elbaite.tres") as GemSpecies
	_check(corundum != null and elbaite != null, "corundum + elbaite load")
	if corundum == null or elbaite == null:
		return
	_check(corundum.optic_axis_stone.distance_to(Vector3(0, 0, 1)) < 1e-5,
		"corundum optic_axis_stone near +Z (table ⊥ c)")
	_check(elbaite.optic_axis_stone.distance_to(Vector3(1, 0, 0)) < 1e-5,
		"elbaite optic_axis_stone near +X (table ∥ c)")


func _test_ruby_compiler() -> void:
	print("[ruby compile]")
	var ruby := load("res://data/lapidary/stones/ruby.tres") as GemStone
	_check(ruby != null and ruby.species != null, "ruby stone loads")
	if ruby == null or ruby.species == null:
		return
	var inst := LapidaryStoneCompiler.compile(ruby)
	var optic: Vector3 = inst["optic_axis"]
	_check(optic.distance_to(ruby.species.optic_axis_stone.normalized()) < 1e-5,
		"compiled optic_axis matches species default")
	var dn: float = inst["birefringence"]
	_check(dn < 0.0 and is_equal_approx(dn, -ruby.species.birefringence),
		"ruby signed birefringence is negative (uniaxial−)")
