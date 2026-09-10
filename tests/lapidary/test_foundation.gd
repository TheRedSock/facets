extends SceneTree
## Regression cases discovered by the engine audit. CPU only.

const Validator := preload("res://core/lapidary/cut/hull_validator.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_identity()
	_geometry()
	_cache()
	print("Foundation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _identity() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/ruby.tres").duplicate(true)
	var fingerprint := stone.fingerprint()
	check(fingerprint == (stone.duplicate(true) as GemStone).fingerprint(), "deep copy preserves content")
	stone.material.chromophore.concentration *= 1.01
	check(fingerprint != stone.fingerprint(), "chromophore content invalidates")
	fingerprint = stone.fingerprint()
	stone.material.species.sellmeier_b.x += 0.000001
	check(fingerprint != stone.fingerprint(), "species content invalidates")
	fingerprint = stone.fingerprint()
	stone.cut.table_ratio += 0.01
	check(fingerprint != stone.fingerprint(), "cut content invalidates")
	fingerprint = stone.fingerprint()
	stone.size_mm += 0.00001
	check(fingerprint != stone.fingerprint(), "small physical changes are not quantized away")
	var clip: GemClip = load("res://data/lapidary/clips/flash.tres").duplicate(true)
	fingerprint = clip.fingerprint()
	clip.effect_envelopes["exposure_pulse"].set_point_value(1, 1.6)
	check(fingerprint != clip.fingerprint(), "curve contents invalidate")
	check(GemContentIdentity.digest({"a": 1, "b": 2}) == GemContentIdentity.digest({"b": 2, "a": 1}), "dictionary insertion order is irrelevant")
	var context := GemRenderIdentity.context(GemRung.PREVIEW)
	fingerprint = GemContentIdentity.digest(context)
	context["rig"] = context["rig"].duplicate(true)
	context["rig"].lights[0].power *= 1.1
	check(fingerprint != GemContentIdentity.digest(context), "rig content invalidates render context")
	context = GemRenderIdentity.context(GemRung.PREVIEW)
	fingerprint = GemContentIdentity.digest(context)
	context["policy"]["spp"] += 1
	check(fingerprint != GemContentIdentity.digest(context), "policy content invalidates render context")

func _geometry() -> void:
	var cube := PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var n: Vector3 = axis * sign_value
			cube.append_array(PackedFloat32Array([n.x, n.y, n.z, 1, 0, 0, 0, 0]))
	check(Validator.check_bounded(cube), "closed cube is bounded")
	# Rotate an open cone: checking only 26 fixed directions missed these.
	for index in 64:
		var u := Vector3(sin(index * 1.13), cos(index * 0.71), 0.37).normalized()
		var a := u.cross(Vector3.UP).normalized()
		var b := u.cross(a)
		var planes := PackedFloat32Array()
		for k in 12:
			var angle := k * TAU / 12
			var n := (a * cos(angle) + b * sin(angle) - u * 0.03).normalized()
			planes.append_array(PackedFloat32Array([n.x, n.y, n.z, 1, 0, 0, 0, 0]))
		check(not Validator.check_bounded(planes), "open cone rotation %d" % index)
	var invalid := cube.duplicate()
	invalid[0] = NAN
	check(not Validator.check_bounded(invalid), "NaN normals rejected")

func _cache() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate(true)
	stone.seed = 994123
	var clip := GemClip.new()
	clip.clip_id = &"foundation_integrity"
	clip.fps = 1
	var frame := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	frame.fill(Color.WHITE)
	GemCache.invalidate(stone, clip, GemRung.INTERACT)
	check(GemCache.write(stone, clip, GemRung.INTERACT, [frame]), "write synthetic cache")
	check(GemCache.has(stone, clip, GemRung.INTERACT), "valid cache hit")
	var path := GemCache.strip_path(GemCache.USER_ROOT, stone, clip, GemRung.INTERACT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0, 1, 2, 3]))
	file.close()
	check(not GemCache.has(stone, clip, GemRung.INTERACT), "corrupt payload cannot suppress rebake")
	check(GemCache.write(stone, clip, GemRung.INTERACT, [frame]), "replace corrupt artifact atomically")
	check(GemCache.has(stone, clip, GemRung.INTERACT), "replacement readable")
	DirAccess.remove_absolute(path)
	check(not GemCache.has(stone, clip, GemRung.INTERACT), "orphaned sidecar is a miss")
	GemCache.invalidate(stone, clip, GemRung.INTERACT)
