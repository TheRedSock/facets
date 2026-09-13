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


static func compile(stone: GemStone, optimize_cleavage := true) -> Dictionary:
	assert(stone != null and stone.material.species != null)
	assert(stone.condition == null or stone.condition.validate_volume_fields().is_empty(), "Invalid spatial material condition")
	var bulk := GemMaterialCompiler.compile(stone.material)
	var fields:Array=stone.condition.volume_fields if stone.condition!=null else []
	var spatial:=GemMaterialCompiler.field_absorption(stone.material,fields)
	assert(not spatial.has("error"),str(spatial))
	var species := stone.material.species

	var geometry := compile_geometry(stone)
	var compiled := {
		"planes": geometry["planes"],
		"shape_recipe": stone.shape,
		"crystal_to_stone": stone.crystal_to_stone,
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
		"optic_axis": stone.resolved_optic_axis(),
		"dispersion_strong": dispersion_bg(species) >= 0.025,
		"fingerprint": stone.fingerprint(),
	}
	if geometry.has("compilation_error"):
		compiled["compilation_error"]=geometry.compilation_error
		return compiled
	if geometry.has("condition_report"):compiled["condition_report"]=geometry.condition_report
	if geometry.has("rounded_solid"):
		compiled["rounded_solid"] = geometry.rounded_solid
	if geometry.has("mesh"):
		compiled["mesh"] = geometry["mesh"]
	if geometry.has("analytic_shape"):
		compiled["analytic_shape"] = geometry["analytic_shape"]
	compiled["surfaces"] = [stone.condition.finish if stone.condition != null and stone.condition.finish != null else GemSurface.new()]
	compiled["volume_fields"] = fields
	compiled["field_absorption"] = spatial.spectra
	GemDefectCompiler.apply(compiled, stone.condition, stone.size_mm, optimize_cleavage)
	return compiled


static func dispersion_bg(species: GemSpecies) -> float:
	return species.ior_at(WL_F) - species.ior_at(WL_C)


# ------------------------------------------------------------------ cut

static func compile_geometry(stone: GemStone) -> Dictionary:
	var rounding:GemRounding=stone.condition.rounding if stone.condition!=null else null
	if rounding!=null:
		if not rounding.validate().is_empty():return {"planes":PackedFloat32Array(),"compilation_error":"; ".join(rounding.validate())}
		if rounding.radius_mm>0 and stone.shape.mode!="faceted":return {"planes":PackedFloat32Array(),"compilation_error":"Junction rounding currently requires a convex faceted host"}
	if stone.shape.mode == "cabochon" and stone.shape.outline in [&"round", &"oval"] and stone.shape.outline_points.is_empty():
		return {"planes": PackedFloat32Array(), "outline": GemShapeCompiler.outline(stone.shape),
			"analytic_shape": Vector4(1.0, 1.0 / stone.shape.aspect_ratio, stone.shape.dome_height, -0.04)}
	if stone.shape.mode != "faceted":
		var mesh := GemShapeCompiler.compile(stone.shape)
		var errors := mesh.validate()
		if not errors.is_empty():return {"planes":PackedFloat32Array(),"compilation_error":"Invalid procedural shape: %s" % errors}
		return {"planes": PackedFloat32Array(), "mesh": mesh, "outline": GemShapeCompiler.outline(stone.shape)}
	assert(ResourceLoader.exists(CUT_COMPILER_PATH),
		"LapidaryStoneCompiler: cut compiler missing at %s" % CUT_COMPILER_PATH)
	var compiler: GDScript = load(CUT_COMPILER_PATH)
	var tolerances := Vector4.ZERO
	if stone.condition != null and stone.condition.workmanship != null:
		tolerances = stone.condition.workmanship.normalized_tolerances(stone.size_mm)
	var geometry:Dictionary=compiler.call("compile", stone.cut, stone.shape, stone.seed, tolerances)
	if rounding!=null and rounding.radius_mm>0:
		var result:=GemRoundedSolid.compile(geometry.planes,geometry.get("facet_ids",PackedInt32Array()),stone.size_mm,rounding)
		if not result.error.is_empty():return {"planes":PackedFloat32Array(),"compilation_error":result.error}
		geometry["planes"]=PackedFloat32Array();geometry["rounded_solid"]=result
		geometry["condition_report"]={"rounding":result.report}
	return geometry
