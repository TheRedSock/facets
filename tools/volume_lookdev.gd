extends SceneTree
## Spatial volume acceptance: raw/filtered low-SPP against the same high-SPP model.
## --hero selects 512px; --quick selects 128px/512spp reference.
const OUT := "res://artifacts/spatial-volume/"

func _initialize() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var resolution := 512 if OS.get_cmdline_user_args().has("--hero") else (128 if quick else 256)
	var reference_spp := 512 if quick else 2048
	DirAccess.make_dir_recursive_absolute(OUT)
	var tracer := GemTracer.create(resolution, resolution)
	if tracer == null:
		quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.grade.cut = 1.0
	stone.material.scatter_per_mm = 0.0
	var layer := GemVolumeField.new()
	layer.center_mm = Vector3(0.3, 0.0, -0.6)
	layer.radius_mm = Vector3(5.5, 3.8, 1.1)
	layer.orientation = Quaternion(Vector3.RIGHT, 0.35)
	layer.scatter_per_mm = 2.0
	stone.condition.volume_fields.append(layer)
	var secondary := GemVolumeField.new()
	secondary.center_mm = Vector3(-0.6, 0.3, 0.0)
	secondary.radius_mm = Vector3(2.8, 4.0, 0.7)
	secondary.orientation = Quaternion(Vector3.RIGHT, 0.35)
	secondary.scatter_per_mm = 0.6
	stone.condition.volume_fields.append(secondary)
	var instance := LapidaryStoneCompiler.compile(stone)
	instance["absorption"].fill(0.01)
	instance["absorption_eray"] = PackedFloat32Array()
	instance["extraordinary_refraction"] = {}
	instance["zoning"] = {}
	var policy := GemRung.policy(GemRung.HERO)
	policy["birefringence"] = false
	var rig := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var report := []
	for angle in ([0.0] if OS.get_cmdline_user_args().has("--single") else [0.0, 0.35]):
		tracer.configure_stone(instance, rig, policy)
		tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
		tracer.set_reconstruction(0)
		var start := Time.get_ticks_usec()
		for batch in reference_spp / 64:
			tracer.accumulate(64)
		var reference_ms := (Time.get_ticks_usec() - start) / 1000.0
		var reference := tracer.read_xyz()
		var reference_image := tracer.finalize_print(GemPrint.load_house())
		var prefix := "%d_%.2f_" % [resolution, angle]
		reference_image.save_png(OUT + prefix + "reference.png")
		print("spatial volume %dpx angle %.2f reference %dspp %.1fms" % [resolution, angle, reference_spp, reference_ms])
		for spp in [64, 128]:
			tracer.set_seed(74119)
			tracer.reset_accumulation()
			tracer.accumulate(spp)
			for passes in [0, 3]:
				tracer.set_reconstruction(passes)
				var values := tracer.read_reconstructed_xyz()
				var image := tracer.finalize_print(GemPrint.load_house())
				image.save_png(OUT + prefix + "%d_%d.png" % [spp, passes])
				var record: Dictionary = load("res://tools/reconstruction_check.gd").metrics(reference, values, reference_image, image)
				record.merge({"angle": angle, "spp": spp, "passes": passes, "resolution": resolution, "reference_ms": reference_ms, "profile": tracer.profile()})
				report.append(record)
				print(JSON.stringify(record))
				FileAccess.open(OUT + "report_%d.json" % resolution, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	tracer.release()
	quit()
