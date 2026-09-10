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
	var untouched := tracer.read_xyz()
	tracer.set_reconstruction(3)
	var reconstructed := tracer.read_reconstructed_xyz()
	check(untouched == tracer.read_xyz(), "reconstruction preserves reference master")
	var alpha_equal := true
	for i in untouched.size() / 4:
		alpha_equal = alpha_equal and untouched[i * 4 + 3] == reconstructed[i * 4 + 3]
	check(alpha_equal, "reconstruction preserves coverage exactly")
	_analytic_interfaces(tracer, inst, lights, policy)
	_mesh_checks(tracer, inst, lights, policy)
	_boundary_checks(tracer, inst, lights, policy)
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

func _analytic_interfaces(tracer: GemTracer, instance: Dictionary, lights: PackedFloat32Array, policy: Dictionary) -> void:
	var inst := instance.duplicate(true)
	var cube := PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var normal: Vector3 = axis * sign_value
			cube.append_array(PackedFloat32Array([normal.x, normal.y, normal.z, 1, 0, 0, 0, 0]))
	inst["planes"] = cube
	inst["size_mm"] = 1.0
	inst["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	inst["sellmeier_b"] = Vector3(1.25, 0, 0) # exact wavelength-independent n=1.5
	inst["sellmeier_c"] = Vector3.ZERO
	inst["absorption"].fill(50.0)
	for angle in [0.0, 0.3, 0.6]:
		tracer.configure_stone(inst, lights, policy)
		tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
		tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
		tracer.accumulate(1024)
		var ci := cos(angle)
		var eta := 1.0 / 1.5
		var ct := sqrt(1.0 - eta * eta * (1.0 - ci * ci))
		var rs := pow((eta * ci - ct) / (eta * ci + ct), 2)
		var rp := pow((ci - eta * ct) / (ci + eta * ct), 2)
		var expected := (rs + rp) * 0.5
		check(absf(_center_y(tracer) - expected) < 0.0003, "Fresnel at %.1frad matches analytic R=%.6f" % [angle, expected])
	inst["absorption"].fill(0.2)
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(1024)
	var t := exp(-0.2 * 2.0)
	var expected := 0.04 + 0.96 * 0.96 * t / (1.0 - 0.04 * t)
	check(absf(_center_y(tracer) - expected) < 0.001, "absorbing slab includes both Fresnel boundaries and internal returns")
	var unfiltered := tracer.read_xyz()
	tracer.set_reconstruction(3)
	var filtered := tracer.read_reconstructed_xyz()
	check(unfiltered == filtered, "zero-scatter reflections and transmission remain bit-identical")

func _center_y(tracer: GemTracer) -> float:
	var values := tracer.read_xyz()
	var total := 0.0
	for y in range(14, 18):
		for x in range(14, 18):
			total += values[(y * 32 + x) * 4 + 1]
	return total / 16.0

func _mesh_checks(tracer: GemTracer, instance: Dictionary, lights: PackedFloat32Array, policy: Dictionary) -> void:
	var inst := instance.duplicate(true)
	inst["size_mm"] = 1.0
	inst["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	inst["absorption"].fill(0.2)
	inst["sellmeier_b"] = Vector3(1.25, 0, 0)
	inst["sellmeier_c"] = Vector3.ZERO
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(512)
	var planes := tracer.read_xyz()
	inst["mesh"] = GemShapeCompiler.from_hull(inst["planes"])
	inst["planes"] = PackedFloat32Array()
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(512)
	var triangles := tracer.read_xyz()
	var squared := 0.0
	var count := 0
	for i in planes.size() / 4:
		if planes[i * 4 + 3] > 0.99 and triangles[i * 4 + 3] > 0.99:
			squared += pow(planes[i * 4 + 1] - triangles[i * 4 + 1], 2)
			count += 1
	check(count > 50 and sqrt(squared / maxf(count, 1)) < 0.002, "mesh and convex backends agree for the same physical solid")
	var outline := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0.4, 1), Vector2(0.4, -0.2), Vector2(-0.4, -0.2), Vector2(-0.4, 1), Vector2(-1, 1)])
	inst["mesh"] = GemShapeCompiler.loft(outline, PackedVector2Array([Vector2(-0.5, 1), Vector2(0.5, 1)]))
	inst["sellmeier_b"] = Vector3.ZERO # n=1; analytic two-chord Beer-Lambert
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.set_stone_orientation(Quaternion(Vector3.UP, PI * 0.5))
	tracer.accumulate(1024)
	var xyz := tracer.read_xyz()
	var actual := 0.0
	for y in range(8, 12):
		for x in range(14, 18):
			actual += xyz[(y * 32 + x) * 4 + 1] / 16.0
	var expected := exp(-0.2 * (0.6 + 0.6))
	check(absf(actual - expected) < 0.001, "concave reentry includes both absorbing chords: %.6f vs %.6f" % [actual, expected])

func _boundary_checks(tracer: GemTracer, instance: Dictionary, lights: PackedFloat32Array, policy: Dictionary) -> void:
	var boxes := load("res://tests/lapidary/test_boundaries.gd")
	var inst := instance.duplicate(true)
	inst["planes"] = PackedFloat32Array()
	inst["size_mm"] = 1.0
	inst["sellmeier_b"] = Vector3.ZERO
	inst["sellmeier_c"] = Vector3.ZERO
	inst["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	inst["absorption"].fill(0.2)
	var boundaries := GemBoundarySet.new()
	check(boundaries.add(boxes.box(Vector3(-1, -1, -1), Vector3(1, 1, 1)), 0), "boundary host validates")
	boundaries.add(boxes.box(Vector3(-0.8, -0.8, -0.5), Vector3(0.8, 0.8, 0.1)), -1)
	boundaries.add(boxes.box(Vector3(-0.7, -0.7, -0.1), Vector3(0.7, 0.7, 0.5)), -1)
	inst["boundaries"] = boundaries
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(1024)
	check(absf(_center_y(tracer) - exp(-0.2)) < 0.001, "overlapping cavities subtract union, with true entry and exit")
	boundaries.add(boxes.box(Vector3(-0.5, -0.5, -0.2), Vector3(0.5, 0.5, 0.2)), 1)
	var filling := instance.duplicate(true)
	filling["sellmeier_b"] = Vector3.ZERO
	filling["sellmeier_c"] = Vector3.ZERO
	filling["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	filling["absorption"].fill(0.4)
	inst["region_materials"] = [filling]
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(1024)
	check(absf(_center_y(tracer) - exp(-0.2 - 0.4 * 0.4)) < 0.001, "nested filling uses its own absorption and physical thickness")
	# A through-void removes primary coverage. Its mathematical surface above
	# the host is not a visible floating primitive.
	boundaries.add(boxes.box(Vector3(-0.3, -0.3, -1.2), Vector3(0.3, 0.3, 1.2)), -1)
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(128)
	var xyz := tracer.read_xyz()
	var coverage := 0.0
	for y in range(14, 18):
		for x in range(14, 18):
			coverage += xyz[(y * 32 + x) * 4 + 3]
	check(coverage == 0.0, "subtracted material changes silhouette and coverage")
	# Clear nested dielectrics in isotropic illumination preserve equilibrium.
	boundaries = GemBoundarySet.new()
	boundaries.add(boxes.box(Vector3(-1, -1, -1), Vector3(1, 1, 1)), 0)
	boundaries.add(boxes.box(Vector3(-0.7, -0.7, -0.4), Vector3(0.7, 0.7, 0.4)), 1)
	inst["boundaries"] = boundaries
	inst["sellmeier_b"] = Vector3(1.25, 0, 0)
	inst["absorption"].fill(0.0)
	filling["sellmeier_b"] = Vector3(0.7689, 0, 0) # n=1.33
	filling["absorption"].fill(0.0)
	tracer.configure_stone(inst, lights, policy)
	tracer.set_environment({"bg": Vector4(1, 1, 1, 0)})
	tracer.accumulate(1024)
	check(absf(_center_y(tracer) - 1.0) < 0.001, "air/host/filling dielectric interfaces preserve equilibrium")

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
