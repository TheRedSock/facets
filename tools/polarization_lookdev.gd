extends SceneTree
## Scalar/persistent-polarization comparison for supported isotropic specimens.
func _initialize() -> void:
	var dichroic := "--dichroic" in OS.get_cmdline_user_args()
	var root := "res://artifacts/polarization/dichroic/" if dichroic else "res://artifacts/polarization/"
	DirAccess.make_dir_recursive_absolute(root)
	var tracer := GemTracer.create(256, 256)
	if tracer == null:
		quit(1)
		return
	var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy := GemRung.policy(GemRung.HERO)
	policy["denoise_passes"] = 0
	var report := []
	for id in (["fluorite"] if dichroic else ["diamond", "fluorite"]):
		var stone: GemStone = load("res://data/lapidary/stones/" + id + ".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material.scatter_per_mm = 0.0
		if dichroic:
			# Synthetic absorption tensor: a diagnostic, not measured fluorite.
			stone.material.absorbers = [GemAbsorber.relative(GemChromophore.new())]
			stone.material.absorbers[0].chromophore.source_note = "Synthetic two-band axial absorption diagnostic, not mineral data"
			stone.material.species.optic_axis_stone = Vector3(1, 0.3, 0.4).normalized()
			for sample in 81:
				var wavelength := 380.0 + sample * 5
				stone.material.absorbers[0].chromophore.absorption_mm.append(0.01 + 0.7 * exp(-pow((wavelength - 450) / 50, 2)))
				stone.material.absorbers[0].chromophore.absorption_eray_mm.append(0.01 + 0.7 * exp(-pow((wavelength - 610) / 65, 2)))
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
				var record := {"stone": id, "synthetic_dichroism": dichroic, "angle": angle, "polarized": polarized, "profile": tracer.profile()}
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
