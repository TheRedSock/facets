class_name GemConditionVariation
extends Resource
## Bounded physical variation. A shared channel_id couples quantiles deliberately.
## Targets are a fixed vocabulary, not arbitrary resource property paths.
const LIMITS := {
	"finish.alpha_u": [0.0, 1.0], "finish.alpha_v": [0.0, 1.0],
	"rounding.radius_mm": [0.0, 1000.0], "cleavage.depth_mm": [0.0, 1000.0],
	"workmanship.azimuth_error_deg": [0.0, 5.0], "workmanship.polar_error_deg": [0.0, 5.0],
	"workmanship.inward_offset_mm": [0.0, 1.0], "workmanship.girdle_inward_mm": [0.0, 1.0],
	"cut.pavilion_angle_deg": [10.0, 70.0], "cut.table_ratio": [0.05, 0.95],
	"material.scatter_per_mm": [0.0, 10000.0], "material.scatter_g": [-0.99, 0.99],
	"population.count": [0.0, 127.0]
}
@export var channel_id: StringName
@export_enum("finish.alpha_u", "finish.alpha_v", "rounding.radius_mm", "cleavage.depth_mm", "workmanship.azimuth_error_deg", "workmanship.polar_error_deg", "workmanship.inward_offset_mm", "workmanship.girdle_inward_mm", "cut.pavilion_angle_deg", "cut.table_ratio", "material.scatter_per_mm", "material.scatter_g", "population.count") var target := "finish.alpha_u"
@export var population_id: StringName
@export var minimum := 0.0
@export var maximum := 0.0
@export var logarithmic := false

func validate() -> String:
	if channel_id == &"" or not LIMITS.has(target): return "Variation needs a stable channel and supported target"
	var limits: Array = LIMITS[target]
	if not is_finite(minimum) or not is_finite(maximum) or minimum > maximum or minimum < limits[0] or maximum > limits[1]:
		return "Variation range is invalid for " + target
	if logarithmic and minimum <= 0: return "Logarithmic variation needs positive bounds"
	if target == "population.count":
		if population_id == &"" or minimum != floorf(minimum) or maximum != floorf(maximum) or logarithmic:
			return "Population counts need an ID and integer linear bounds"
	elif population_id != &"": return "Population ID is only meaningful for population.count"
	return ""

func target_key() -> String:
	return target + ":" + String(population_id)
