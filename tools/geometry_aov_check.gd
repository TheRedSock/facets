extends SceneTree
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var tracer := GemTracer.create(64, 64)
	if tracer == null:
		print("CHECK_COMPLETE: geometry_aov_check"); quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["size_mm"] = 2.0
	inst["extraordinary_refraction"] = {}
	var lighting := GemLighting.analytic(PackedFloat32Array(), Vector4(1, 1, 1, 0))
	var policy := GemRung.policy(GemRung.PREVIEW)
	var planes := PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var normal: Vector3 = axis * sign_value
			planes.append_array(PackedFloat32Array([normal.x, normal.y, normal.z, 1, 0, 0, 0, 0]))
	inst["planes"] = planes
	inst["facet_ids"] = PackedInt32Array([10, 11, 12, 13, 14, 200000001])
	tracer.configure_stone(inst, lighting, policy)
	var geometry := tracer.geometry_aov()
	check(geometry != null and geometry.data.size() == 64 * 64 * 48, "geometry pass returns its exact typed layout")
	if geometry == null:
		tracer.release()
		print("CHECK_COMPLETE: geometry_aov_check"); quit(1)
		return
	var center := geometry.record(32, 32)
	check(absf(center.position_mm.z - 2) < 1e-5 and center.normal_object.distance_to(Vector3.BACK) < 1e-6, "front point and object normal are physical")
	check(center.facet == 200000001 and center.region == 0 and center.material == 0 and center.coverage == 1, "full integer facet and medium IDs survive plane packing")
	check(geometry.record(0, 0).coverage == 0 and geometry.record(0, 0).instance == -1, "misses have zero coverage and invalid IDs")
	check(tracer.samples_accumulated == 0, "AOV generation does not run optical sampling")
	var again := tracer.geometry_aov()
	check(again.data == geometry.data, "geometry sampling is bit-stable across repeated requests")
	tracer.accumulate(8)
	var before := tracer.read_xyz().to_byte_array()
	again = tracer.geometry_aov()
	check(tracer.samples_accumulated == 8 and before == tracer.read_xyz().to_byte_array(), "AOV pass does not mutate the optical film")
	check(again.data == geometry.data, "geometry is independent of optical SPP")
	var decoded := GemGeometryAov.decode(geometry.encode())
	check(decoded != null and decoded.data == geometry.data, "lossless typed AOV payload round-trips")
	var invalid := geometry.encode()
	invalid.encode_u32(16, 0xffffffff)
	check(GemGeometryAov.decode(invalid) == null, "oversized decompression header is rejected")
	var saved_data := geometry.data.duplicate()
	geometry.data.encode_float((32 * 64 + 32) * 48, NAN)
	check(GemGeometryAov.decode(geometry.encode()) == null, "nonfinite geometry payload is rejected")
	geometry.data = saved_data
	# A void crossing the front face exposes its back wall. The original host
	# surface is not the first physical boundary in this ray.
	var box_tool := load("res://tests/lapidary/test_boundaries.gd")
	var boundaries := GemBoundarySet.new()
	boundaries.add(box_tool.box(Vector3(-1, -1, -1), Vector3(1, 1, 1)), 0)
	boundaries.add(box_tool.box(Vector3(-0.5, -0.5, 0.5), Vector3(0.5, 0.5, 1.5)), -1)
	inst["boundaries"] = boundaries
	tracer.configure_stone(inst, lighting, policy)
	geometry = tracer.geometry_aov()
	center = geometry.record(32, 32)
	check(absf(center.position_mm.z - 1) < 1e-5 and center.region == 1 and center.material == 0, "exposed cavity wall replaces the clipped-away host face")
	check(center.normal_object.z > 0.99, "cavity wall normal faces the incident medium")
	inst.erase("boundaries")
	tracer.configure_stones([inst, inst], lighting, policy, Vector2i(2, 1))
	geometry = tracer.geometry_aov()
	check(geometry.record(16, 32).instance == 0 and geometry.record(48, 32).instance == 1, "batch cells retain distinct instance IDs")
	check(geometry.record(48, 32).material == 1, "batch material IDs use the packed material table")
	inst["planes"] = PackedFloat32Array()
	inst["analytic_shape"] = Vector4(1, 0.8, 0.6, -0.04)
	tracer.configure_stone(inst, lighting, policy)
	geometry = tracer.geometry_aov()
	center = geometry.record(32, 32)
	check(absf(center.position_mm.z - 1.2) < 0.001 and center.facet == -1, "analytic cabochon preserves its curved surface patch ID")
	# Authored faceted specimen for visual review.
	tracer.configure_stone(LapidaryStoneCompiler.compile(stone), lighting, policy)
	tracer.set_stone_orientation(Quaternion(Vector3.UP, 0.3))
	geometry = tracer.geometry_aov()
	GemArtifactStore.atomic_write("res://artifacts/aov/quartz.gao", geometry.encode())
	geometry.normal_image().save_png("res://artifacts/aov/quartz_normals.png")
	tracer.release()
	print("Geometry AOV: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: geometry_aov_check"); quit(1 if failures else 0)
