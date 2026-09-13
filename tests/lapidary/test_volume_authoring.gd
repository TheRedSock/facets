extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	for file in DirAccess.get_files_at("res://data/lapidary/stones"):
		if file.get_extension() != "tres":
			continue
		var stone: GemStone = load("res://data/lapidary/stones/" + file).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		var before := LapidaryStoneCompiler.compile(stone)
		before.erase("fingerprint")
		stone.grade.cut = 0
		stone.grade.clarity = 0
		stone.grade.surface = 0
		stone.grade.crystal = 0
		var after := LapidaryStoneCompiler.compile(stone)
		after.erase("fingerprint")
		check(before == after, "grade labels cannot change realized optics: " + file)
		check(stone.material.scatter_per_mm >= 0 and stone.condition.banding.validate().is_empty(), "catalog has explicit valid physical volume inputs")
	var bands := GemBanding.new()
	bands.axis = Vector3(1, 2, 3)
	bands.period_mm = 0.7
	bands.contrast = 0.85
	bands.phase_radians = 0.8
	var start := Vector3(0.3, -0.2, 0.5)
	var direction := Vector3(2, -1, 3).normalized()
	var length_mm := 1.3
	var quadrature := 0.0
	for index in 4096:
		var point := start + direction * (length_mm * (index + 0.5) / 4096)
		quadrature += 1 + bands.contrast * sin(TAU * bands.axis.normalized().dot(point) / bands.period_mm + bands.phase_radians)
	quadrature *= length_mm / 4096
	for size_mm in [0.5, 1.0, 4.5, 20.0]:
		var packed := bands.normalized(size_mm)
		var column: float = GemOpticalDepth.zoning_column(start / size_mm, direction, length_mm / size_mm, packed.axis, packed.frequency, packed.contrast, packed.phase) * size_mm
		check(absf(column - quadrature) < 1e-6, "band optical depth retains physical millimeters across host scales")
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.banding = bands
	var original: Dictionary = LapidaryStoneCompiler.compile(stone).zoning
	stone.seed += 317
	check(LapidaryStoneCompiler.compile(stone).zoning == original, "realized band phase is independent of unrelated cut seed")
	var job := GemFrameJob.new()
	job.stone = stone
	job.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	job.print_style = GemPrint.load_house()
	var master := GemFramePlan.master_key(job)
	var authored_hash := stone.fingerprint()
	stone.grade.crystal = 0.1
	stone.stone_id = &"catalog_alias"
	check(GemFramePlan.master_key(job) == master and stone.fingerprint() != authored_hash, "labels preserve optical cache while retaining authored identity")
	bands.contrast = 0.5
	check(GemFramePlan.master_key(job) != master, "physical coefficient changes retire optical masters")
	for property: Dictionary in stone.get_property_list():
		var key: String = property.name
		if int(property.usage) & PROPERTY_USAGE_STORAGE == 0 or key in ["script", "resource_path", "resource_name", "resource_local_to_scene", "stone_id", "grade"] or key.begins_with("metadata/"):
			continue
		check(stone.transport_inputs().has(key), "every physical specimen property participates in transport identity: " + key)
	bands.period_mm = 0
	check(GemJobValidator.validate(job).contains("Banding period"), "invalid physical period rejected before rendering")
	bands.period_mm = 0.7
	bands.axis = Vector3.ZERO
	check(GemJobValidator.validate(job).contains("Banding needs"), "invalid band direction rejected before rendering")
	var document:=GemAuthoringDocument.new()
	var authored: GemStone = load("res://data/lapidary/stones/amethyst.tres")
	var original_identity := authored.fingerprint()
	document.create(authored)
	check(document.edit(["material","scatter_per_mm"],2.0).is_empty(),"Document edits explicit scattering")
	check(document.edit(["condition","banding","contrast"],1.0).is_empty(),"Document edits explicit band contrast")
	check(document.edit(["material","absorbers",0,"amount"],0.01).is_empty(),"Document edits absorber amount")
	check(authored.fingerprint() == original_identity, "Authoring edits cannot mutate shared external material resources")
	print("Volume authoring: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_volume_authoring"); quit(1 if failures else 0)
