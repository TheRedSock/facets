extends SceneTree
## Measure noise reduction and reconstruction bias against the same transport
## at high SPP. --hero uses 512px; default quick check is 128px.
const OUT := "res://artifacts/reconstruction/"

func _initialize() -> void:
	var res := 512 if OS.get_cmdline_user_args().has("--hero") else 128
	DirAccess.make_dir_recursive_absolute(OUT)
	var tracer := GemTracer.create(res, res)
	if tracer == null:
		quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate(true)
	stone.grade.cut = 1.0
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["birefringence"] = 0.0
	inst["absorption_eray"] = PackedFloat32Array()
	inst["absorption"].fill(0.01)
	inst["zoning"] = {}
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var lights := GemRigCompiler.pack(rig)
	var policy := GemRung.policy(GemRung.HERO)
	policy["birefringence"] = false
	policy["dispersion"] = false
	policy["spectral_geometry"] = "selective" # controlled scalar geometry comparison
	policy["max_bounces"] = 256
	policy["env_filter_rad"] = 0.0
	policy["field_exits"] = 0
	var report := []
	for density in ([0.5] if OS.get_cmdline_user_args().has("--dense") else [0.0, 0.075, 0.5]):
		inst["scatter"] = {"sigma_per_mm": density, "g": 0.6}
		tracer.configure_stone(inst, lights, policy)
		tracer.set_environment(GemRigCompiler.environment(rig))
		tracer.set_reconstruction(0)
		var start := Time.get_ticks_usec()
		for batch in 64:
			tracer.accumulate(64)
		var reference_ms := (Time.get_ticks_usec() - start) / 1000.0
		var reference := tracer.read_xyz()
		var reference_image := tracer.finalize_print(GemPrint.load_house())
		var prefix := "%d_%.3f_" % [res, density]
		reference_image.save_png(OUT + prefix + "reference.png")
		print("volume %.3f %dpx reference 4096spp %.1fms" % [density, res, reference_ms])
		for spp in [64, 256]:
			tracer.reset_accumulation()
			tracer.accumulate(spp)
			for reconstruction in [Vector2(0, 2), Vector2(3, 2), Vector2(3, 4)]:
				tracer.set_reconstruction(int(reconstruction.x), reconstruction.y)
				var candidate := tracer.read_reconstructed_xyz()
				var image := tracer.finalize_print(GemPrint.load_house())
				image.save_png(OUT + prefix + "%d_%d_%.0f.png" % [spp, reconstruction.x, reconstruction.y])
				var record := metrics(reference, candidate, reference_image, image)
				record.merge({"sigma": density, "spp": spp, "passes": reconstruction.x, "phi": reconstruction.y,
					"resolution": res, "reference_ms": reference_ms, "profile": tracer.profile()})
				report.append(record)
				print(JSON.stringify(record))
				FileAccess.open(OUT + "results_%d.json" % res, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	tracer.release()
	quit()

static func metrics(reference: PackedFloat32Array, candidate: PackedFloat32Array, a: Image, b: Image) -> Dictionary:
	var sum_ref := 0.0
	var sum_test := 0.0
	var square_error := 0.0
	var print_error := 0.0
	var pixels := 0
	var res := a.get_width()
	for i in candidate.size() / 4:
		if reference[i * 4 + 3] < 0.99 or candidate[i * 4 + 3] < 0.99:
			continue
		sum_ref += reference[i * 4 + 1]
		sum_test += candidate[i * 4 + 1]
		square_error += pow(candidate[i * 4 + 1] - reference[i * 4 + 1], 2)
		var x := i % res
		var y := i / res
		var ca := a.get_pixel(x, y)
		var cb := b.get_pixel(x, y)
		print_error += pow(ca.r - cb.r, 2) + pow(ca.g - cb.g, 2) + pow(ca.b - cb.b, 2)
		pixels += 1
	return {"mean_ratio": sum_test / sum_ref,
		"relative_Y_RMSE": sqrt(square_error / pixels) / (sum_ref / pixels),
		"display_RMSE_LSB": 255.0 * sqrt(print_error / (pixels * 3))}
