extends SceneTree
## Windowed GPU regression gate. Returns nonzero on a failed assertion.
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var tracer := GemTracer.create(32, 32)
	if tracer == null:
		quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/ruby.tres")
	var inst := LapidaryStoneCompiler.compile(stone)
	var lights := PackedFloat32Array([0, 0, 1, 0.5, 5600, 0, 0.9, 0])
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["field_exits"] = 0
	policy["fluorescence"] = true
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4.ZERO})
	tracer.accumulate(32)
	var xyz := tracer.read_xyz()
	var max_y := 0.0
	for i in xyz.size() / 4:
		max_y = maxf(max_y, xyz[i * 4 + 1])
	check(max_y == 0.0, "no light is generated in darkness")
	_print_checks(tracer)
	# Constant isotropic environment, nonabsorbing heterogeneous path lengths:
	# equilibrium radiance is one, regardless of repeated elastic scattering.
	inst["absorption"].fill(0.0)
	inst["absorption_eray"] = PackedFloat32Array()
	inst["birefringence"] = 0.0
	inst["zoning"] = {}
	inst["scatter"] = {"sigma_per_mm": 0.6, "g": 0.0}
	policy["max_bounces"] = 512
	policy["birefringence"] = false
	policy["env_filter_rad"] = 0.0
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(32)
	var whole := tracer.read_xyz()
	tracer.reset_accumulation()
	for count in [3, 11, 5, 13]:
		tracer.accumulate(count)
	var partitioned := tracer.read_xyz()
	var max_difference := 0.0
	var total_y := 0.0
	var coverage := 0.0
	for i in whole.size():
		max_difference = maxf(max_difference, absf(whole[i] - partitioned[i]))
	for i in whole.size() / 4:
		total_y += whole[i * 4 + 1]
		coverage += whole[i * 4 + 3]
	check(max_difference < 0.000002, "sample partition invariant: %.8f" % max_difference)
	check(absf(total_y / coverage - 1.0) < 0.015, "multiple-scatter equilibrium Y=%.6f" % (total_y / coverage))
	# Changes to framing or print white balance cannot invalidate volume light.
	policy["field_exits"] = 4
	policy["field_grid"] = 4
	policy["field_dirs"] = 64
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(1)
	var builds := tracer.field_build_count
	tracer.set_clip_sample(Quaternion.IDENTITY, 0.0, Vector4.ONE, 1.4)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0), "white_kelvin": 6500.0})
	tracer.reset_accumulation()
	tracer.accumulate(1)
	check(tracer.field_build_count == builds, "framing and print changes reuse volume field")
	tracer.set_stone_orientation(Quaternion(Vector3.UP, 0.2))
	tracer.reset_accumulation()
	tracer.accumulate(1)
	check(tracer.field_build_count == builds + 1, "orientation rebuilds volume field")
	check(tracer.last_accumulate_ms >= tracer.last_field_ms, "timing includes field build")
	print("GPU foundation: %d checks, %d failures; partition error %.8f; equilibrium Y %.6f" % [checks, failures, max_difference, total_y / coverage])
	tracer.release()
	quit(1 if failures else 0)

func _print_checks(tracer: GemTracer) -> void:
	var values := PackedFloat32Array()
	values.resize(32 * 32 * 4)
	for i in 32 * 32:
		var cov := 1.0 if i % 32 < 16 else 0.5
		values[i * 4] = 0.95047 * cov
		values[i * 4 + 1] = cov
		values[i * 4 + 2] = 1.08883 * cov
		values[i * 4 + 3] = cov
	var rd: RenderingDevice = tracer.get("_rd")
	var buffers: Dictionary = tracer.get("_bufs")
	rd.buffer_update(buffers["accum"], 0, values.to_byte_array().size(), values.to_byte_array())
	tracer.samples_accumulated = 1
	for raw in [false, true]:
		var image := tracer.finalize_print(GemPrint.load_house(), raw)
		var a := image.get_pixel(5, 5)
		var b := image.get_pixel(25, 5)
		check(absf(a.r - b.r) < 0.005 and absf(a.g - b.g) < 0.005 and absf(a.b - b.b) < 0.005, "straight RGB independent of coverage, raw=%s" % raw)
		check(a.a == 1.0 and absf(b.a - 0.5) < 0.005, "coverage preserved")
	# Reduce a mix of opaque black and opaque white before the print.
	for i in 32 * 32:
		var power := float(i % 2)
		values[i * 4] = 0.95047 * power
		values[i * 4 + 1] = power
		values[i * 4 + 2] = 1.08883 * power
		values[i * 4 + 3] = 1.0
	rd.buffer_update(buffers["accum"], 0, values.to_byte_array().size(), values.to_byte_array())
	var reduced := tracer.finalize_print(null, true, 1.0, Vector2i(16, 16))
	var pixel := reduced.get_pixel(5, 5)
	var expected := Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0).linear_to_srgb()
	check(absf(pixel.r - expected.r) < 0.006, "linear resolve precedes nonlinear print")
	var master := tracer.read_linear_master()
	check(master.get_format() == Image.FORMAT_RGBAF and master.get_pixel(1, 1).b > 1.08, "linear master retains out-of-display-range XYZ")
