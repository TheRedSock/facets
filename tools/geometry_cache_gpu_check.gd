extends SceneTree
## Compare reusable packed/resident geometry against fresh packing and buffers.
var checks := 0
var failures := 0
var maximum_error := 0.0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	var warm := GemTracer.create(64,16)
	var cold := GemTracer.create(64,16)
	if warm == null or cold == null: print("CHECK_COMPLETE: geometry_cache_gpu_check"); quit(1); return
	cold._geometry_cache.entry_limit = 0
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition = GemCondition.new(); stone.material.scatter_per_mm = 0
	var base := LapidaryStoneCompiler.compile(stone)
	base["extraordinary_refraction"] = {}; base["size_mm"] = 1.0
	base["sellmeier_b"] = Vector3.ZERO; base["sellmeier_c"] = Vector3.ZERO; base["index_offset"] = .5
	base["absorption"].fill(.03); base["absorption_eray"] = PackedFloat32Array()
	var mesh := GemShapeCompiler.from_hull(base.planes, base.facet_ids)
	var original_planes: PackedFloat32Array = base.planes
	base["mesh"] = mesh; base["planes"] = PackedFloat32Array()
	var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"] = false; policy["denoise_passes"] = 0; policy["volume"] = false
	for mode in ["scalar", "polarized", "crystal"]:
		policy["polarization"] = mode == "polarized"; policy["crystal_transport"] = mode == "crystal"
		for scenario in 8:
			var instance := base.duplicate(true)
			instance["mesh"] = _clone(mesh)
			if scenario == 2: instance.absorption.fill(.2)
			if scenario == 3: instance.mesh.facet_ids.fill(-123456789)
			if scenario == 4:
				for vertex in instance.mesh.vertices.size(): instance.mesh.vertices[vertex] *= .8
			if scenario == 5:
				var first: int = instance.mesh.indices[0]
				instance.mesh.indices[0] = instance.mesh.indices[1]; instance.mesh.indices[1] = instance.mesh.indices[2]; instance.mesh.indices[2] = first
			if scenario == 6:
				var boundaries := GemBoundarySet.new()
				boundaries.add(instance.mesh, 0)
				var inner := _clone(mesh)
				for vertex in inner.vertices.size(): inner.vertices[vertex] *= .45
				boundaries.add(inner, 1)
				instance["boundaries"] = boundaries; instance["mesh"] = boundaries.mesh
				var material := base.duplicate(true)
				material.absorption.fill(.6)
				instance["region_materials"] = [material]
			if scenario == 7:
				instance.erase("mesh"); instance["planes"] = original_planes
			var instances: Array = [instance, base, instance, base] if scenario >= 4 else [instance]
			var grid := Vector2i(4,1) if scenario >= 4 else Vector2i.ONE
			var before := warm.geometry_cache_statistics()
			cold._free_scene_buffers()
			check(warm.configure_stones(instances, lighting, policy, grid), "%s case%d warm admission" % [mode,scenario])
			check(cold.configure_stones(instances, lighting, policy, grid), "%s case%d cold admission" % [mode,scenario])
			if not warm.configuration_error.is_empty() or not cold.configuration_error.is_empty(): continue
			if scenario == 1 or scenario == 2:
				var after := warm.geometry_cache_statistics()
				check(after.builds == before.builds and after.buffer_uploads == before.buffer_uploads, "pose/material change retains BVH and GPU geometry")
			var states := []
			for cell in grid.x:
				states.append({"quat": Quaternion(Vector3.UP,.17+cell*.07), "stone_index": cell if grid.x>1 else 0})
			warm.set_instances(states); cold.set_instances(states)
			var ga := warm.geometry_aov(2); var gb := cold.geometry_aov(2)
			check(ga != null and gb != null and ga.data == gb.data, "%s case%d exact primary geometry/identity" % [mode,scenario])
			warm.accumulate(16); cold.accumulate(16)
			check(warm.transport_error().is_empty() and cold.transport_error().is_empty(), "%s case%d valid optical paths" % [mode,scenario])
			var a := warm.read_xyz(); var b := cold.read_xyz()
			var error := 0.0
			for i in a.size(): error = maxf(error, absf(a[i]-b[i]))
			maximum_error = maxf(maximum_error,error)
			# Adaptive submission grouping can change float32 summation order.
			check(error < 2e-6, "%s case%d cold/warm radiance agreement: %s" % [mode,scenario,error])
	check(warm.geometry_cache_statistics().hits > 12 and warm.geometry_cache_statistics().buffer_reuses > 4, "regression exercised actual reuse")
	var boxes := load("res://tests/lapidary/test_boundaries.gd")
	var invalid := GemBoundarySet.new()
	invalid.add(boxes.box(Vector3(-1,-1,-1),Vector3(1,1,1)),0)
	invalid.add(boxes.box(Vector3(-1,-1,-.2),Vector3(1,1,.2)),0)
	var rejected := base.duplicate(true)
	rejected.erase("mesh"); rejected["boundaries"] = invalid
	check(not warm.configure_stone(rejected,lighting,policy) and "coincident" in warm.configuration_error, "boundary-only input cannot bypass combined-mesh admission")
	check(warm.configure_stone(base,lighting,policy), "valid configuration recovers after rejected geometry")
	warm.release(); cold.release()
	check(warm.geometry_cache_statistics().retained_bytes == 0, "tracer release frees CPU payload retention")
	print("Geometry cache GPU: %d checks, %d failures; maximum XYZA error %s" % [checks,failures,maximum_error])
	print("CHECK_COMPLETE: geometry_cache_gpu_check"); quit(1 if failures else 0)

func _clone(source: GemMesh) -> GemMesh:
	var result := GemMesh.new()
	result.vertices = source.vertices.duplicate(); result.indices = source.indices.duplicate()
	result.facet_ids = source.facet_ids.duplicate(); result.region_ids = source.region_ids.duplicate()
	return result
