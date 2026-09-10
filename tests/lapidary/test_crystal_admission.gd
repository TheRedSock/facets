extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/ruby.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var job := GemFramePlan.animation(stone, load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.REFERENCE)[0]
	job.quality["crystal_transport"] = true
	check(GemJobValidator.validate(job).contains("scattering"), "catalog scattering is not silently discarded")
	stone.material.scatter_per_mm = 0
	stone.condition = GemCondition.new()
	check(GemJobValidator.validate(job).is_empty(), "clear crystal with weak dichroism admitted")
	var key := GemFramePlan.master_key(job)
	job.quality["crystal_transport"] = false
	check(GemFramePlan.master_key(job) != key, "crystal transport has distinct master identity")
	job.quality["crystal_transport"] = true
	job.quality["polarization"] = true
	check(not GemJobValidator.validate(job).is_empty(), "incompatible backends rejected")
	job.quality["polarization"] = false
	stone.condition.finish.alpha_u = 0.02
	check(GemJobValidator.validate(job).contains("rough"), "rough boundary deferred explicitly")
	stone.condition.finish.alpha_u = 0
	var field := GemVolumeField.new()
	field.absorption_concentration = 2
	stone.condition.volume_fields.append(field)
	check(GemJobValidator.validate(job).is_empty(), "spatial weak absorption admitted")
	field.scatter_per_mm = 0.1
	check(GemJobValidator.validate(job).contains("scattering"), "spatial scattering rejected")
	stone.condition.volume_fields[0] = null
	check(not GemJobValidator.validate(job).is_empty(), "malformed field fails before crystal model access")
	stone.condition.volume_fields.clear()
	stone.material.absorbers[0].amount = 1e6
	check(GemJobValidator.validate(job).contains("weak-loss"), "strong complex-index absorption is outside the model")
	stone.material.absorbers[0].amount = 1
	var defect := GemDefect.new()
	defect.filling = stone.material.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	defect.filling.scatter_per_mm = 0.1
	stone.condition.defects.append(defect)
	check(GemJobValidator.validate(job).contains("scattering"), "nested filling follows same capability gate")
	print("Crystal admission: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
