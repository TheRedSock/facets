extends SceneTree
## Physical finish checks + reference/noise sweep. No catalog grades are changed.
## --showcase renders clear/polished/frosted comparisons under the authored rig.
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var out := "res://artifacts/surface"
	DirAccess.make_dir_recursive_absolute(out)
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.grade.cut = 1.0
	stone.grade.crystal = 1.0
	stone.material.scatter_per_mm = 0.0
	var base := LapidaryStoneCompiler.compile(stone)
	base["absorption"].fill(0.0)
	base["absorption_eray"] = PackedFloat32Array()
	base["birefringence"] = 0.0
	base["zoning"] = {}
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"] = false
	policy["max_bounces"] = 256
	policy["denoise_passes"] = 0
	var dark_lights := PackedFloat32Array([0, 0, 1, 0.5, 5600, 0, 0.9, 0])
	var tracer := GemTracer.create(48, 48)
	if tracer == null:
		quit(1)
		return
	var measurements := []
	for alpha in [0.0, 0.001, 0.005, 0.02, 0.1, 0.3]:
		var finish := GemSurface.new()
		finish.alpha_u = alpha
		finish.alpha_v = alpha
		base["surfaces"] = [finish]
		tracer.configure_stone(base, GemLighting.analytic(dark_lights, Vector4(1, 1, 1, 0)), policy)
		var ms := tracer.accumulate(256)
		var values := tracer.read_xyz()
		var y := mean_y(values)
		measurements.append({"alpha": alpha, "furnace_Y": y, "trace_ms": ms})
		check(is_finite(y) and y > 0.0 and y < 1.005, "rough boundary stays finite and does not create energy")
		if alpha <= 0.005:
			check(absf(y - 1.0) < 0.015, "light polish meets furnace energy budget")
		var matched := base.duplicate()
		matched["sellmeier_b"] = Vector3.ZERO
		matched["sellmeier_c"] = Vector3.ZERO
		tracer.configure_stone(matched, GemLighting.analytic(dark_lights, Vector4(1, 1, 1, 0)), policy)
		tracer.accumulate(8)
		check(absf(mean_y(tracer.read_xyz()) - 1.0) < 0.005, "index-matched rough boundary is invisible")
	tracer.set_lighting(GemLighting.analytic(dark_lights))
	tracer.reset_accumulation()
	tracer.accumulate(8)
	check(mean_y(tracer.read_xyz()) == 0.0, "rough boundary cannot emit in darkness")
	_anisotropy(tracer, base, policy)
	tracer.release()
	GemArtifactStore.atomic_write(out + "/furnace.json", JSON.stringify(measurements, "\t").to_utf8_buffer())
	print(JSON.stringify(measurements))
	if "--showcase" in OS.get_cmdline_user_args():
		_showcase(stone, out)
	print("Surface: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _anisotropy(tracer: GemTracer, input: Dictionary, policy: Dictionary) -> void:
	var specimen := input.duplicate(true)
	specimen["planes"] = PackedFloat32Array()
	specimen["analytic_shape"] = Vector4(1.0, 1.0, 0.8, -0.04)
	specimen["sellmeier_b"] = Vector3(1.25, 0, 0)
	specimen["sellmeier_c"] = Vector3.ZERO
	specimen["absorption"].fill(100.0) # Isolate the front-surface reflection.
	var finish := GemSurface.new()
	finish.alpha_u = 0.1
	finish.alpha_v = 0.01
	specimen["surfaces"] = [finish]
	var moments := []
	for axis in [Vector3.RIGHT, Vector3.UP]:
		finish.direction = axis
		tracer.configure_stone(specimen, GemLighting.analytic(PackedFloat32Array([0, 0, 1, cos(0.04), 5600, 1, cos(0.02), 0])), policy)
		tracer.set_clip_sample(Quaternion.IDENTITY, 0.0, Vector4.ONE, 1.25)
		tracer.accumulate(512)
		var values := tracer.read_xyz()
		var second := Vector2.ZERO
		for y in tracer.height:
			for x in tracer.width:
				var p := Vector2(x + 0.5 - tracer.width * 0.5, y + 0.5 - tracer.height * 0.5)
				second += p * p * values[(y * tracer.width + x) * 4 + 1]
		moments.append(second.x / maxf(second.y, 1e-9))
	check(moments[0] > 1.5 and moments[1] < 0.67, "polish direction rotates the anisotropic highlight: %s" % str(moments))
	print("Directional polish moment ratios: ", moments)

func _showcase(stone: GemStone, out: String) -> void:
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var lights := GemRigCompiler.compile(rig)
	var policy := GemRung.policy(GemRung.PREVIEW)
	var tracer := GemTracer.create(256, 256)
	var sheet := Image.create(256 * 4, 256 * 2, false, Image.FORMAT_RGBA8)
	var metrics := []
	for column in 4:
		stone.condition.finish.alpha_u = [0.0, 0.005, 0.02, 0.15][column]
		stone.condition.finish.alpha_v = stone.condition.finish.alpha_u
		tracer.configure_stone(LapidaryStoneCompiler.compile(stone), lights, policy)
		tracer.set_clip_sample(Quaternion(Vector3.RIGHT, deg_to_rad(-12.0)), 0.0, Vector4.ONE, 1.25)
		var time_low := tracer.accumulate(128)
		var low := tracer.finalize_print(GemPrint.load_house())
		var low_raw := tracer.finalize_print(GemPrint.load_house(), false, 1.0, Vector2i.ZERO, false)
		var time_high := tracer.accumulate(2048 - 128)
		var reference := tracer.finalize_print(GemPrint.load_house(), false, 1.0, Vector2i.ZERO, false)
		sheet.blit_rect(low, Rect2i(0, 0, 256, 256), Vector2i(column * 256, 0))
		sheet.blit_rect(reference, Rect2i(0, 0, 256, 256), Vector2i(column * 256, 256))
		metrics.append({"alpha": stone.condition.finish.alpha_u, "low_spp": 128, "reference_spp": 2048,
			"low_trace_ms": time_low, "reference_additional_ms": time_high,
			"filtered_error": GemPagePacker.compression_error(reference.get_data(), low.get_data()),
			"raw_error": GemPagePacker.compression_error(reference.get_data(), low_raw.get_data())})
	tracer.release()
	sheet.save_png(out + "/polish.png")
	GemArtifactStore.atomic_write(out + "/polish.json", JSON.stringify(metrics, "\t").to_utf8_buffer())
	print("Polish showcase: ", JSON.stringify(metrics))

static func mean_y(values: PackedFloat32Array) -> float:
	var sum_y := 0.0
	var coverage := 0.0
	for i in values.size() / 4:
		sum_y += values[i * 4 + 1]
		coverage += values[i * 4 + 3]
	return sum_y / maxf(coverage, 1e-10)
