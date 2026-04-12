extends SceneTree

## Validates all GemMineralTemplate .tres files in data/minerals/.

const MINERAL_DATA_PATH := "res://data/minerals/"

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("\n=== Mineral Template Validation Tests ===\n")

	var templates := _load_all_templates()
	if templates.is_empty():
		_fail("No mineral templates found in %s" % MINERAL_DATA_PATH)
		_print_summary()
		quit(1 if _fail_count > 0 else 0)
		return

	for path in templates:
		var tmpl: Resource = templates[path]
		var label := String(path).get_file()

		# 1. Non-empty mineral_id
		var mineral_id: StringName = tmpl.get("mineral_id")
		_assert(mineral_id != &"", "%s: mineral_id should be non-empty" % label)

		# 2. Reasonable IOR at 589nm (1.0 < n < 3.0)
		var ior_589 := _sellmeier_ior(tmpl, 589.0)
		_assert(ior_589 > 1.0 and ior_589 < 3.0,
			"%s: IOR at 589nm should be in (1.0, 3.0), got %.4f" % [label, ior_589])

		# 3. Normal dispersion: IOR at 380nm > IOR at 780nm
		var ior_380 := _sellmeier_ior(tmpl, 380.0)
		var ior_780 := _sellmeier_ior(tmpl, 780.0)
		_assert(ior_380 > ior_780,
			"%s: normal dispersion requires IOR(380nm)=%.4f > IOR(780nm)=%.4f" % [label, ior_380, ior_780])

		# 4. Absorption spectrum is either empty or exactly 81 entries
		var absorption: PackedFloat32Array = tmpl.get("absorption_spectrum")
		_assert(absorption.size() == 0 or absorption.size() == 81,
			"%s: absorption_spectrum size should be 0 or 81, got %d" % [label, absorption.size()])

		# 5. All absorption entries non-negative
		if absorption.size() > 0:
			var all_non_negative := true
			for i in absorption.size():
				if absorption[i] < 0.0:
					all_non_negative = false
					break
			_assert(all_non_negative, "%s: absorption_spectrum entries must be non-negative" % label)

		# 6. birefringence_delta_n >= 0
		var delta_n: float = tmpl.get("birefringence_delta_n")
		_assert(delta_n >= 0.0, "%s: birefringence_delta_n should be >= 0, got %.4f" % [label, delta_n])

		# 7. scattering_coefficient >= 0
		var sigma_s: float = tmpl.get("scattering_coefficient")
		_assert(sigma_s >= 0.0, "%s: scattering_coefficient should be >= 0, got %.4f" % [label, sigma_s])

		# 8. fluorescence_quantum_yield in [0, 1]
		var qy: float = tmpl.get("fluorescence_quantum_yield")
		_assert(qy >= 0.0 and qy <= 1.0,
			"%s: fluorescence_quantum_yield should be in [0, 1], got %.4f" % [label, qy])

		# 9. If fluorescent, emission center in visible range
		if qy > 0.0:
			var emission_center: float = tmpl.get("fluorescence_emission_center_nm")
			_assert(emission_center >= 380.0 and emission_center <= 780.0,
				"%s: fluorescence emission center should be in [380, 780], got %.1f" % [label, emission_center])

	_print_summary()
	quit(1 if _fail_count > 0 else 0)


func _load_all_templates() -> Dictionary:
	var result := {}
	var dir := DirAccess.open(MINERAL_DATA_PATH)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var full_path := MINERAL_DATA_PATH + file_name
			var resource := load(full_path)
			if resource != null:
				result[full_path] = resource
		file_name = dir.get_next()
	return result


func _sellmeier_ior(tmpl: Resource, lambda_nm: float) -> float:
	var b: Vector3 = tmpl.get("sellmeier_b")
	var c: Vector3 = tmpl.get("sellmeier_c")
	var l := lambda_nm * 0.001
	var l2 := l * l
	var n2 := 1.0 \
		+ b.x * l2 / (l2 - c.x) \
		+ b.y * l2 / (l2 - c.y) \
		+ b.z * l2 / (l2 - c.z)
	return sqrt(max(n2, 1.0))


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s" % message)


func _fail(message: String) -> void:
	_fail_count += 1
	print("  FAIL: %s" % message)


func _print_summary() -> void:
	print("\n=== Results: %d passed, %d failed ===\n" % [_pass_count, _fail_count])
