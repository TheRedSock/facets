extends SceneTree
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var nominal := LapidaryStoneCompiler.compile(stone)["planes"] as PackedFloat32Array
	stone.grade.cut = 0
	check(LapidaryStoneCompiler.compile(stone)["planes"] == nominal, "cut grade label cannot rewrite the design")
	stone.material = load("res://data/lapidary/stones/diamond.tres").material
	check(LapidaryStoneCompiler.compile(stone)["planes"] == nominal, "material IOR cannot rewrite geometry")
	stone.seed += 100
	check(LapidaryStoneCompiler.compile(stone)["planes"] == nominal, "zero manufacturing tolerance is seed-independent")
	stone.cut.pavilion_angle_deg = 35
	check(LapidaryStoneCompiler.compile(stone)["planes"] != nominal, "explicit pavilion angle changes geometry")
	stone.cut.pavilion_angle_deg = 41
	var workmanship := stone.condition.workmanship
	workmanship.polar_error_deg = 0.2
	var perturbed: PackedFloat32Array = LapidaryStoneCompiler.compile(stone)["planes"]
	check(perturbed != nominal and perturbed == LapidaryStoneCompiler.compile(stone)["planes"], "angular manufacturing deviation is deterministic")
	for index in perturbed.size() / 8:
		if int(perturbed[index * 8 + 4]) != 4:
			continue
		var angle := rad_to_deg(acos(absf(perturbed[index * 8 + 2])))
		check(absf(angle - 41) <= 0.2001, "pavilion error stays within explicit angular tolerance")
	workmanship.polar_error_deg = 0
	workmanship.inward_offset_mm = 0.01
	workmanship.girdle_inward_mm = 0.02
	var small: PackedFloat32Array = LapidaryStoneCompiler.compile(stone)["planes"]
	stone.size_mm *= 2
	workmanship.inward_offset_mm *= 2
	workmanship.girdle_inward_mm *= 2
	check(LapidaryStoneCompiler.compile(stone)["planes"] == small, "physical scale and millimeter tolerances scale together")
	workmanship.inward_offset_mm = NAN
	check(not workmanship.validate().is_empty(), "nonfinite manufacturing input rejected")
	print("Cut design: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
