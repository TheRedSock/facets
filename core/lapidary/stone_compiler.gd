class_name LapidaryStoneCompiler
extends RefCounted
## Compiles a GemStone's explicit physical inputs into the
## StoneInstance dictionary consumed by the GPU kernel (see KERNEL_CONTRACT.md).
## Grade labels never alter transport. Materials own homogeneous coefficients;
## condition owns realized banding, fields, boundaries and surface finish.

const CUT_COMPILER_PATH := "res://core/lapidary/cut/cut_compiler.gd"

## Fraunhofer lines for dispersion strength (B-G).
const WL_F := 486.1
const WL_C := 656.3


static func compile(stone: GemStone) -> Dictionary:
	assert(stone != null and stone.material.species != null)
	assert(stone.condition == null or stone.condition.validate_volume_fields().is_empty(), "Invalid spatial material condition")
	var bulk := GemMaterialCompiler.compile(stone.material)
	var species := stone.material.species

	var geometry := _compile_cut(stone)
	var compiled := {
		"planes": geometry["planes"],
		"facet_ids": geometry.get("facet_ids", PackedInt32Array()),
		"outline": geometry.get("outline", PackedVector2Array()),
		"absorption": bulk["absorption"],
		"absorption_eray": bulk["absorption_eray"],
		"sellmeier_b": bulk["sellmeier_b"],
		"sellmeier_c": bulk["sellmeier_c"],
		"size_mm": stone.size_mm,
		"seed": stone.seed,
		"scatter": bulk["scatter"],
		"zoning": stone.condition.banding.normalized(stone.size_mm) if stone.condition != null and stone.condition.banding != null else {},
		"index_offset": bulk["index_offset"],
		"extraordinary_refraction": bulk["extraordinary_refraction"],
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
	compiled["volume_fields"] = stone.condition.volume_fields if stone.condition != null else []
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

static func _compile_cut(stone: GemStone) -> Dictionary:
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
	var tolerances := Vector4.ZERO
	if stone.condition != null and stone.condition.workmanship != null:
		tolerances = stone.condition.workmanship.normalized_tolerances(stone.size_mm)
	return compiler.call("compile", stone.cut, stone.shape, stone.seed, tolerances)
