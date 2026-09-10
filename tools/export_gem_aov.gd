extends SceneTree
## Standalone geometry companions for evaluation/stylizer development.
## --stone=quartz --resolution=512 --angle-deg=20 --coverage=4
func _initialize() -> void:
	var options := {"stone": "quartz", "resolution": "512", "angle-deg": "20", "coverage": "4"}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2 or not options.has(pair[0]):
			printerr("Unknown AOV option: " + argument)
			quit(1)
			return
		options[pair[0]] = pair[1]
	if not options.stone.is_valid_filename() or not options.resolution.is_valid_int() or not options.coverage.is_valid_int() or not options["angle-deg"].is_valid_float():
		printerr("Invalid AOV request")
		quit(1)
		return
	var resolution := int(options.resolution)
	var coverage := int(options.coverage)
	var angle := float(options["angle-deg"])
	if resolution < 16 or resolution > 2048 or coverage not in [1, 2, 4, 8] or not is_finite(angle):
		printerr("AOV resolution must be 16..2048; coverage side is 1,2,4,8; angle must be finite")
		quit(1)
		return
	var path: String = "res://data/lapidary/stones/%s.tres" % options.stone
	if not ResourceLoader.exists(path):
		printerr("Unknown specimen: " + options.stone)
		quit(1)
		return
	var stone := load(path) as GemStone
	var tracer := GemTracer.create(resolution, resolution)
	if tracer == null:
		quit(1)
		return
	var orientation := Quaternion(Vector3.UP, deg_to_rad(angle))
	tracer.configure_stone(LapidaryStoneCompiler.compile(stone), GemLighting.analytic(PackedFloat32Array(), Vector4.ZERO), GemRung.policy(GemRung.PREVIEW))
	tracer.set_stone_orientation(orientation)
	var begin := Time.get_ticks_usec()
	var geometry := tracer.geometry_aov(coverage)
	var elapsed := (Time.get_ticks_usec() - begin) / 1000.0
	if geometry == null:
		tracer.release()
		quit(1)
		return
	var root: String = "res://artifacts/aov/" + options.stone
	var payload := geometry.encode()
	var written := GemArtifactStore.atomic_write(root + "/geometry.gao", payload)
	var metadata := {"schema": "primary_geometry_v1", "specimen": options.stone, "fingerprint": stone.fingerprint(),
		"width": resolution, "height": resolution, "coverage_side": coverage, "angle_degrees_y": angle,
		"orientation": [orientation.x, orientation.y, orientation.z, orientation.w], "ortho_half": 1.25,
		"raw_bytes": geometry.data.size(), "compressed_bytes": payload.size(), "geometry_wall_ms": elapsed,
		"optical_samples": tracer.samples_accumulated, "normal_space": "object_incident_facing", "position_depth_unit": "mm",
		"limitation": "Primary boundary only; not refracted inclusion visibility or an optical contribution layer"}
	written = written and GemArtifactStore.atomic_write(root + "/metadata.json", JSON.stringify(metadata, "\t").to_utf8_buffer())
	written = written and geometry.normal_image().save_png(root + "/normals.png") == OK
	tracer.release()
	print(JSON.stringify(metadata))
	quit(0 if written else 1)
