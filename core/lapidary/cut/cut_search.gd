class_name GemCutSearch
extends RefCounted
## Bounded design-space exploration. The score is an explicit engineering
## objective under an illumination/view ensemble, never a gemological grade.

static func candidate(source: GemStone, pavilion_deg: float, table_ratio: float, crown_scale: float) -> GemStone:
	var stone := source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemStone
	stone.cut.pavilion_angle_deg = pavilion_deg
	stone.cut.table_ratio = table_ratio
	for row in stone.cut.crown_rows:
		row.angle_deg *= crown_scale
	return stone

static func evaluate(tracer: GemTracer, stone: GemStone, scenarios: Array[Dictionary], policy: Dictionary, samples: int) -> Dictionary:
	var instance := LapidaryStoneCompiler.compile(stone)
	if instance["planes"].is_empty():
		return {"error": "Candidate has no faceted geometry"}
	var values := PackedFloat64Array()
	for scenario in scenarios:
		tracer.configure_stone(instance, scenario["lighting"], policy)
		tracer.set_seed(17)
		tracer.set_clip_sample(scenario["orientation"], scenario.get("yaw", 0.0), Vector4.ONE, 1.4)
		tracer.accumulate(samples)
		var xyz := tracer.read_xyz()
		var luminance := 0.0
		var coverage := 0.0
		for pixel in xyz.size() / 4:
			luminance += xyz[pixel * 4 + 1]
			coverage += xyz[pixel * 4 + 3]
		values.append(luminance / maxf(coverage, 1e-12))
	if values.is_empty():
		return {"error": "No illumination scenarios"}
	var mean := 0.0
	for value in values:
		mean += value / values.size()
	var worst := values[0]
	for value in values:
		worst = minf(worst, value)
	return {"score": 0.75 * mean + 0.25 * worst, "mean_Y": mean, "worst_Y": worst, "views_Y": Array(values)}
