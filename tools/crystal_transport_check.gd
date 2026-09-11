extends SceneTree
var failures := 0
func _initialize() -> void:
	var tracer := GemTracer.create(16, 16)
	if tracer == null:
		quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm = 0
	stone.condition = GemCondition.new()
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["size_mm"] = 1.0
	inst["absorption"].fill(0.0)
	inst["absorption_eray"] = PackedFloat32Array()
	var planes := PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var normal: Vector3 = axis * sign_value
			planes.append_array(PackedFloat32Array([normal.x, normal.y, normal.z, 1.0 if axis.z != 0 else 100.0, 0, 0, 0, 0]))
	inst["planes"] = planes
	var lighting := GemLighting.analytic(PackedFloat32Array(), Vector4(1, 1, 1, 0))
	var policy := GemRung.policy(GemRung.REFERENCE)
	policy["crystal_transport"] = true
	policy["volume"] = false
	# Same spectral sample pattern removes finite-sample CIE quadrature error
	# from this transport check (not an empirical brightness correction).
	inst["sellmeier_b"] = Vector3.ZERO
	inst["sellmeier_c"] = Vector3.ZERO
	inst["extraordinary_refraction"] = {}
	tracer.configure_stone(inst, lighting, policy)
	tracer.accumulate(128)
	var unit := tracer.read_linear_master().get_data().to_float32_array()[(8 * 16 + 8) * 4 + 1]
	for anisotropic in [false, true]:
		inst["sellmeier_b"] = Vector3(1.56, 0, 0) # n_o=1.6
		inst["sellmeier_c"] = Vector3.ZERO
		inst["extraordinary_refraction"] = {"b": Vector3(2.24, 0, 0), "c": Vector3.ZERO, "offset": 0.0} if anisotropic else {}
		inst["optic_axis"] = Vector3(0.6, 0, 0.8)
		for angle in [0.0, 0.6, 1.2]:
			if not tracer.configure_stone(inst, lighting, policy):
				printerr(tracer.configuration_error)
				tracer.release()
				quit(1)
				return
			tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
			tracer.accumulate(128)
			var pixels := tracer.read_linear_master().get_data().to_float32_array()
			var actual := pixels[(8 * 16 + 8) * 4 + 1] / unit
			var diagnostics := tracer.crystal_diagnostics()
			print({"anisotropic": anisotropic, "angle": angle, "Y": actual, "diagnostics": diagnostics, "profile": tracer.profile()})
			if absf(actual - 1.0) > 0.0005 or diagnostics.invalid_interfaces != 0:
				failures += 1
	# Optic axis perpendicular to the incidence plane: extraordinary s and
	# ordinary p are independent scalar channels with different true indices.
	inst["optic_axis"] = Vector3.UP
	inst["absorption"].fill(0.2)
	inst["absorption_eray"].resize(401)
	inst["absorption_eray"].fill(0.7)
	for angle in [0.0, 0.6, 1.2]:
		tracer.configure_stone(inst, lighting, policy)
		tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
		tracer.accumulate(128)
		var actual := tracer.read_linear_master().get_data().to_float32_array()[(8 * 16 + 8) * 4 + 1] / unit
		var expected := 0.0
		for channel in 2:
			var n := 1.8 if channel == 0 else 1.6
			var alpha := 0.7 if channel == 0 else 0.2
			var ci := cos(angle)
			var ct := sqrt(1.0 - pow(sin(angle) / n, 2))
			var reflection := pow((ci - n * ct) / (ci + n * ct), 2) if channel == 0 else pow((n * ci - ct) / (n * ci + ct), 2)
			var transmission := exp(-alpha * 2.0 / ct)
			expected += 0.5 * (reflection + pow(1.0 - reflection, 2) * transmission / (1.0 - reflection * transmission))
		print({"absorbing_anisotropic_slab": angle, "actual": actual, "expected": expected, "diagnostics": tracer.crystal_diagnostics()})
		if absf(actual - expected) > 0.0001 or not tracer.transport_error().is_empty():
			failures += 1
	tracer.release()
	_geometry_and_resume(stone, lighting, policy)
	_compare_isotropic(stone, policy)
	print("Crystal transport failures: ", failures)
	quit(1 if failures else 0)

func _geometry_and_resume(stone: GemStone, lighting: GemLighting, policy: Dictionary) -> void:
	var tracer := GemTracer.create(16, 16)
	# Finite-sample wavelength integral is measured with the same sample pattern.
	# Coverage divides out the silhouette; every covered ray sees unit radiance.
	for kind in ["faceted", "cabochon", "loft", "nested"]:
		stone.shape = GemShape.faceted_outline(&"oval")
		stone.condition = GemCondition.new()
		if kind == "cabochon":
			stone.shape = GemShape.cabochon_outline(&"oval")
		elif kind == "loft":
			stone.shape.mode = "loft"
		elif kind == "nested":
			var cavity := GemDefect.new()
			cavity.kind = "crystal"
			cavity.crystal_habit = GemCrystalHabit.prism(6,.6,.45)
			cavity.irregularity = 0.1
			stone.condition.defects.append(cavity)
			var filling: GemDefect = cavity.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
			filling.crystal_scale = 0.6
			filling.filling = stone.material.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
			stone.condition.defects.append(filling)
		var instance := LapidaryStoneCompiler.compile(stone)
		instance.absorption.fill(0.0)
		instance.absorption_eray = PackedFloat32Array()
		if instance.has("region_materials"):
			for material: Dictionary in instance.region_materials:
				material.absorption.fill(0.0)
				material.absorption_eray = PackedFloat32Array()
		var unit_instance := instance.duplicate(true)
		unit_instance.sellmeier_b = Vector3.ZERO
		unit_instance.sellmeier_c = Vector3.ZERO
		unit_instance.extraordinary_refraction = {}
		for material: Dictionary in unit_instance.get("region_materials", []):
			material.sellmeier_b = Vector3.ZERO
			material.sellmeier_c = Vector3.ZERO
			material.extraordinary_refraction = {}
		tracer.configure_stone(unit_instance, lighting, policy)
		tracer.set_stone_orientation(Quaternion(Vector3.UP, 0.31) * Quaternion(Vector3.RIGHT, -0.23))
		tracer.accumulate(8)
		var unit := tracer.read_linear_master().get_data().to_float32_array()
		if not tracer.configure_stone(instance, lighting, policy):
			printerr(tracer.configuration_error)
			failures += 1
			continue
		tracer.set_stone_orientation(Quaternion(Vector3.UP, 0.31) * Quaternion(Vector3.RIGHT, -0.23))
		tracer.accumulate(3)
		var checkpoint := tracer.checkpoint()
		tracer.accumulate(5)
		var uninterrupted := tracer.read_linear_master().get_data().to_float32_array()
		var diagnostics := tracer.crystal_diagnostics()
		var error := tracer.transport_error()
		if not tracer.restore_checkpoint(checkpoint):
			failures += 1
		tracer.accumulate(5)
		var resumed := tracer.read_linear_master().get_data().to_float32_array()
		var maximum := 0.0
		var furnace_error := 0.0
		for i in resumed.size():
			maximum = maxf(maximum, absf(resumed[i] - uninterrupted[i]))
			if i % 4 == 1:
				furnace_error = maxf(furnace_error, absf(resumed[i] - unit[i]))
		print({"geometry": kind, "resume_error": maximum, "furnace_error": furnace_error, "diagnostics": diagnostics})
		if maximum > 1e-5 or furnace_error > 0.002 or not error.is_empty() or not tracer.transport_error().is_empty():
			failures += 1
		# Reject corrupted diagnostic data before changing accumulation buffers.
		checkpoint.crystal_stats.encode_u32(0, 1)
		if tracer.restore_checkpoint(checkpoint):
			failures += 1
	tracer.release()

func _compare_isotropic(stone: GemStone, policy: Dictionary) -> void:
	stone.shape = GemShape.faceted_outline(&"oval")
	stone.condition = GemCondition.new()
	var instance := LapidaryStoneCompiler.compile(stone)
	instance.sellmeier_b = Vector3(1.56, 0, 0)
	instance.sellmeier_c = Vector3.ZERO
	instance.extraordinary_refraction = {}
	instance.absorption.fill(0.15)
	instance.absorption_eray = PackedFloat32Array()
	var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var tracer := GemTracer.create(16, 16)
	var images: Array[PackedFloat32Array] = []
	for crystal in [false, true]:
		var selected := policy.duplicate()
		selected.crystal_transport = crystal
		selected.polarization = not crystal
		if not tracer.configure_stone(instance, lighting, selected):
			printerr(tracer.configuration_error)
			failures += 1
			continue
		tracer.set_stone_orientation(Quaternion(Vector3.UP, 0.31) * Quaternion(Vector3.RIGHT, -0.23))
		tracer.accumulate(64)
		images.append(tracer.read_linear_master().get_data().to_float32_array())
		if not tracer.transport_error().is_empty():
			failures += 1
	var maximum := 0.0
	if images.size() == 2:
		for i in images[0].size():
			maximum = maxf(maximum, absf(images[0][i] - images[1][i]))
		if maximum > 0.002:
			failures += 1
	print({"isotropic_mueller_comparison_maximum_XYZ": maximum})
	tracer.release()
