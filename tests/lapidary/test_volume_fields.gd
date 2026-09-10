extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var field := GemVolumeField.new()
	check(absf(field.column(Vector3(0, 0, -2), Vector3.BACK, 4.0) - 32.0 / 35.0) < 1e-7, "unit center chord has exact integral 32/35")
	check(field.column(Vector3(1.1, 0, -2), Vector3.BACK, 4.0) == 0.0, "miss has exactly zero density column")
	for index in 40:
		field.center_mm = Vector3(0.3, -0.15, 0.12)
		field.radius_mm = Vector3(0.2 + index * 0.02, 0.6, 1.3)
		field.orientation = Quaternion(Vector3(1, 2, 3).normalized(), index * 0.2)
		var origin := Vector3(sin(index * 0.7) * 0.5, 0.2, -1.3)
		var direction := Vector3(cos(index * 0.4) * 0.3, 0.1, 1).normalized()
		var length := 0.1 + index * 0.09
		var numerical := 0.0
		for sample_index in 4096:
			numerical += field.density(origin + direction * length * (sample_index + 0.5) / 4096.0)
		numerical *= length / 4096.0
		var exact := field.column(origin, direction, length)
		check(absf(exact - numerical) < 0.000003, "rotated anisotropic field matches independent quadrature")
		var a := field.column(origin, direction, length * 0.31)
		var b := field.column(origin + direction * length * 0.31, direction, length * 0.69)
		check(absf(exact - a - b) < 0.000003, "field optical depth composes")
		check(absf(exact - field.column(origin + direction * length, -direction, length)) < 0.000003, "field column is reciprocal")
	field.scatter_per_mm = -1
	check(not field.validate().is_empty(), "negative scattering is rejected")
	field.scatter_per_mm = 1
	field.radius_mm.x = 0
	check(not field.validate().is_empty(), "singular spatial transform is rejected")
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var fingerprint := stone.fingerprint()
	stone.condition.volume_fields.append(GemVolumeField.new())
	check(stone.fingerprint() != fingerprint, "spatial condition participates in specimen identity")
	check(LapidaryStoneCompiler.compile(stone)["volume_fields"].size() == 1, "spatial condition reaches transport compiler")
	print("Volume fields: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
