extends SceneTree
## Scalar/persistent-polarization comparison for supported isotropic specimens.
func _initialize() -> void:
	var root := "res://artifacts/polarization/"
	DirAccess.make_dir_recursive_absolute(root)
	var tracer := GemTracer.create(256, 256)
	if tracer == null:
		quit(1)
		return
	var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy := GemRung.policy(GemRung.HERO)
	policy["denoise_passes"] = 0
	var report := []
	for id in ["diamond", "fluorite"]:
		var stone: GemStone = load("res://data/lapidary/stones/" + id + ".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material.scatter_per_mm = 0.0
		var instance := LapidaryStoneCompiler.compile(stone)
		for angle in [0.0, 0.3]:
			var scalar_xyz := PackedFloat32Array()
			var scalar_image: Image
			for polarized in [false, true]:
				policy["polarization"] = polarized
				tracer.configure_stone(instance, lighting, policy)
				tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
				tracer.accumulate(128)
				var xyz := tracer.read_xyz()
				var image := tracer.finalize_print(GemPrint.load_house())
				image.save_png(root + "%s_%.1f_%s.png" % [id, angle, polarized])
				var record := {"stone": id, "angle": angle, "polarized": polarized, "profile": tracer.profile()}
				if polarized:
					record["difference_from_scalar"] = load("res://tools/reconstruction_check.gd").metrics(scalar_xyz, xyz, scalar_image, image)
				else:
					scalar_xyz = xyz
					scalar_image = image
				report.append(record)
				print(JSON.stringify(record))
	FileAccess.open(root + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	tracer.release()
	quit()
