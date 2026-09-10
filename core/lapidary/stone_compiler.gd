class_name LapidaryStoneCompiler
extends RefCounted
## Compiles a GemStone (species + chromophore + cut + grade + seed) into the
## StoneInstance dictionary consumed by the GPU kernel (see KERNEL_CONTRACT.md).
## This file owns the GRADE -> PHYSICS mapping. All randomness is a private
## deterministic hash sequence from the stone seed (never gameplay SeededRng).
##
## Cut and crystal use legacy catalog recipes. Explicit GemCondition boundaries
## and GemSurface finishes provide physical condition. Automatic clarity and
## surface grade mappings remain unaccepted; the old primitive placer is removed.

const CUT_COMPILER_PATH := "res://core/lapidary/cut/cut_compiler.gd"

## Fraunhofer lines for dispersion strength (B-G).
const WL_F := 486.1
const WL_C := 656.3


static func compile(stone: GemStone, cut_quality_override := -1.0) -> Dictionary:
	assert(stone != null and stone.material.species != null)
	var bulk := GemMaterialCompiler.compile(stone.material)
	var species := stone.material.species
	var grade := stone.grade if stone.grade != null else GemGrade.new()
	var cut_q := grade.cut if cut_quality_override < 0.0 else cut_quality_override
	var n_d := species.ior_at(589.3)

	var geometry := _compile_cut(stone, n_d, cut_q)

	var rng_state := [int(stone.seed) * 2654435761 + 1013904223]
	
	var compiled := {
		"planes": geometry["planes"],
		"facet_ids": geometry.get("facet_ids", PackedInt32Array()),
		"outline": geometry.get("outline", PackedVector2Array()),
		"absorption": bulk["absorption"],
		"absorption_eray": bulk["absorption_eray"],
		"sellmeier_b": species.sellmeier_b,
		"sellmeier_c": species.sellmeier_c_um2,
		"size_mm": stone.size_mm,
		"seed": stone.seed,
		"scatter": bulk["scatter"] if stone.material.scatter_per_mm >= 0.0 else _crystal_to_scatter(species, grade),
		"zoning": _crystal_to_zoning(species, grade, rng_state),
		"birefringence": bulk["birefringence"],
		"optic_axis": _resolve_optic_axis(stone).normalized(),
		"fluorescence": _resolve_fluorescence(species, stone.material.chromophore),
		"dispersion_strong": dispersion_bg(species) >= 0.025,
		"fingerprint": stone.fingerprint(),
	}
	if geometry.has("mesh"):
		compiled["mesh"] = geometry["mesh"]
	if geometry.has("analytic_shape"):
		compiled["analytic_shape"] = geometry["analytic_shape"]
	compiled["surfaces"] = [stone.condition.finish if stone.condition != null and stone.condition.finish != null else GemSurface.new()]
	GemDefectCompiler.apply(compiled, stone.condition, stone.size_mm)
	return compiled


static func dispersion_bg(species: GemSpecies) -> float:
	return species.ior_at(WL_F) - species.ior_at(WL_C)


static func _resolve_optic_axis(stone: GemStone) -> Vector3:
	if stone.optic_axis_override != Vector3.ZERO:
		return stone.optic_axis_override
	return stone.material.species.optic_axis_stone


## Fluorescence is chromophore-gated: the glow comes from the coloring ion
## (Cr3+), and co-impurities quench it (Fe in blue sapphire).
static func _resolve_fluorescence(species: GemSpecies, chromo: GemChromophore) -> Dictionary:
	var nm := species.fluorescence_emission_nm
	var strength := species.fluorescence_strength
	if chromo != null:
		if chromo.fluorescence_strength_override >= 0.0:
			strength = chromo.fluorescence_strength_override
		if chromo.fluorescence_emission_nm_override > 0.0:
			nm = chromo.fluorescence_emission_nm_override
	return {"nm": nm, "strength": strength}


# ------------------------------------------------------------------ cut

static func _compile_cut(stone: GemStone, n_d: float, cut_q: float) -> Dictionary:
	if stone.shape.mode == "cabochon" and stone.shape.outline in [&"round", &"oval"] and stone.shape.outline_points.is_empty():
		return {"planes": PackedFloat32Array(), "outline": GemShapeCompiler.outline(stone.shape),
			"analytic_shape": Vector4(1.0, 1.0 / stone.shape.aspect_ratio, stone.shape.dome_height, -0.04)}
	if stone.shape.mode != "faceted":
		var mesh := GemShapeCompiler.compile(stone.shape)
		assert(mesh.validate().is_empty(), "Invalid procedural shape: %s" % mesh.validate())
		return {"planes": PackedFloat32Array(), "mesh": mesh, "outline": GemShapeCompiler.outline(stone.shape)}
	assert(ResourceLoader.exists(CUT_COMPILER_PATH),
		"LapidaryStoneCompiler: cut compiler missing at %s" % CUT_COMPILER_PATH)
	var compiler: GDScript = load(CUT_COMPILER_PATH)
	return compiler.call("compile", stone.cut, stone.shape.outline, n_d, cut_q, stone.seed, stone.shape)


## Pavilion law v2 (re-derived from the prototype's solver):
##   critical = asin(1/n); optimal = 45 - (n - 1) * 3 (empirical lapidary fit)
##   window target = critical - 6 deg (light leaks face-up), floored at 16 deg.
##   No hard [38,48] clamp: low-critical minerals (diamond) window weakly,
##   which is physically true — their grade must read via other axes too.
static func solve_pavilion_deg(n_d: float, cut_q: float) -> float:
	var critical_deg := rad_to_deg(asin(1.0 / maxf(n_d, 1.0001)))
	var optimal := 45.0 - (n_d - 1.0) * 3.0
	var windowed := maxf(critical_deg - 6.0, 16.0)
	return lerpf(windowed, optimal, clampf(cut_q, 0.0, 1.0))


# ------------------------------------------------------------------ grade axes

static func _crystal_to_scatter(species: GemSpecies, grade: GemGrade) -> Dictionary:
	# T1 crystal ~0.66: translucent, not milky-white. Mean free path stays
	# longer than the stone; windowing remains legible.
	var haze := pow(1.0 - grade.crystal, 1.6) * 0.40
	return {
		"sigma_per_mm": species.base_scatter_per_mm + haze,
		"g": species.scatter_anisotropy_g,
	}


static func _crystal_to_zoning(species: GemSpecies, grade: GemGrade, state: Array) -> Dictionary:
	return {
		"axis": species.zoning_axis.normalized(),
		"frequency": species.zoning_frequency,
		"contrast": species.zoning_contrast * (1.0 - grade.crystal),
		"phase": _rndf(state) * TAU,
	}


# ------------------------------------------------------------------ deterministic hash RNG

static func _rndf(state: Array) -> float:
	var s: int = (int(state[0]) * 747796405 + 2891336453) & 0xFFFFFFFF
	state[0] = s
	var word: int = (((s >> ((s >> 28) + 4)) ^ s) * 277803737) & 0xFFFFFFFF
	return float(((word >> 22) ^ word) & 0xFFFFF) / 1048576.0
