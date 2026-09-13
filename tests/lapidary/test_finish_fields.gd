extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var field := GemFinishField.new()
	field.center_mm = Vector3(1,2,3)
	field.radius_mm = Vector3(2,1,0.1)
	field.orientation = Quaternion(Vector3.UP, 0.7)
	field.strength = 0.8
	field.alpha_u = 0.3
	field.alpha_v = 0.02
	check(field.validate().is_empty(), "physical field admitted")
	check(absf(field.weight(field.center_mm)-0.8)<1e-7, "center reaches authored strength")
	var along := field.orientation*Vector3(1,0,0)
	check(absf(field.weight(field.center_mm+along)-0.8*pow(0.75,3))<1e-6, "millimeter footprint and rotated cross section")
	check(field.weight(field.center_mm+3*along)==0, "compact support outside the footprint")
	var scaled: GemFinishField = field.duplicate()
	scaled.center_mm *= 5
	scaled.radius_mm *= 5
	check(absf(scaled.weight((field.center_mm+along)*5)-field.weight(field.center_mm+along))<1e-6, "physical scale covariance")
	var finish := GemSurface.new()
	finish.multiple_scattering = true
	finish.fields = [field]
	check(finish.has_roughness() and finish.validate().is_empty(), "rough field selects boundary transport on a smooth base")
	field.strength = 0
	check(not finish.has_roughness(), "zero-strength field does not require rough transport")
	field.strength = 0.8
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var job := GemFramePlan.animation(stone, load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.PREVIEW)[0]
	var master := GemFramePlan.master_key(job)
	var geometry := GemGeometryPlan.key(job,4)
	stone.condition.finish = finish
	check(GemFramePlan.master_key(job)!=master, "local finish changes optical recipe")
	check(GemGeometryPlan.key(job,4)==geometry, "local finish does not change primary geometry recipe")
	check(not GemCrystalAdmission.stone_error(stone).is_empty(), "crystal admission rejects rough fields on a smooth base")
	var compiled := LapidaryStoneCompiler.compile(stone)
	check(compiled.surfaces[0].fields.size()==1, "field survives specimen compilation")
	var path := "res://artifacts/finish-fields/typed-job.res"
	DirAccess.make_dir_recursive_absolute("res://artifacts/finish-fields")
	check(GemResourceBundle.save(job,path)==OK,"binary job serializes typed finish fields")
	var restored: GemFrameJob=load(path)
	check(restored!=null and restored.stone.condition.finish.fields.size()==1 and GemFramePlan.master_key(restored)==GemFramePlan.master_key(job),"binary job preserves physical finish identity")
	var bad: GemFinishField = field.duplicate()
	for property in ["strength","alpha_u","alpha_v"]:
		bad.set(property, NAN)
		check(not bad.validate().is_empty(), "nonfinite " + property + " rejected")
		bad.set(property, 0.3)
	bad.radius_mm = Vector3(1,1,0)
	check(not bad.validate().is_empty(), "zero field thickness rejected")
	bad.radius_mm = Vector3.ONE
	bad.orientation = Quaternion(0,0,0,0)
	check(not bad.validate().is_empty(), "invalid coordinate frame rejected")
	finish.fields = [null]
	check(not finish.validate().is_empty(), "missing field rejected")
	finish.fields.clear()
	for i in 17: finish.fields.append(field)
	check(not finish.validate().is_empty(), "bounded shader field count enforced")
	print("Finish fields: %d checks, %d failures" % [checks,failures])
	print("CHECK_COMPLETE: test_finish_fields"); quit(1 if failures else 0)
