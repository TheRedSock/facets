extends SceneTree
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func identities(hashes: Dictionary, jobs: Array[GemFrameJob]) -> Dictionary:
	GemRenderIdentity._digests.clear()
	GemGeometryPlan._source_digest = ""
	for domain in GemRenderIdentity.DOMAINS:
		GemRenderIdentity._digests[domain] = GemRenderIdentity.digest_inventory(domain, hashes, "fixed-test-engine")
	var result := {"worker": GemRenderIdentity.worker_digest(), "geometry": GemGeometryPlan.key(jobs[0], 4)}
	for i in jobs.size():
		var domain := GemRenderIdentity.transport_domain(jobs[i].quality)
		result[domain] = GemFramePlan.master_key(jobs[i])
		result[domain + "_display"] = GemFramePlan.display_key(jobs[i])
	return result

func _initialize() -> void:
	var inventory := GemRenderIdentity.inventory()
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres")
	var base := GemFramePlan.animation(stone, load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.REFERENCE)[0]
	var jobs: Array[GemFrameJob] = [base]
	for flag in ["polarization", "crystal_transport"]:
		var job: GemFrameJob = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		job.quality[flag] = true
		jobs.append(job)
	var baseline := identities(inventory, jobs)
	var cases := {
		"core/lapidary/tracer/shaders/gem_crystal.glsl": ["worker", "crystal", "crystal_display"],
		"core/lapidary/tracer/crystal_shader.gd": ["worker", "crystal", "crystal_display"],
		"core/lapidary/tracer/shaders/gem_print.glsl": ["worker", "scalar_display", "polarized_display", "crystal_display"],
		"resources/lapidary/gem_print.gd": ["worker", "scalar_display", "polarized_display", "crystal_display"],
		"core/lapidary/tracer/shaders/gem_volume.glsl": ["worker", "scalar", "polarized", "crystal", "scalar_display", "polarized_display", "crystal_display"],
		"core/lapidary/microsurface/smith_walk.glsl": ["worker", "scalar", "polarized", "crystal", "scalar_display", "polarized_display", "crystal_display"],
		"core/lapidary/tracer/shaders/gem_geometry_aov.glsl": ["worker", "geometry"],
		"core/lapidary/factory/frame_worker.gd": ["worker", "scalar", "polarized", "crystal", "scalar_display", "polarized_display", "crystal_display"],
		"core/lapidary/factory/frame_plan.gd": baseline.keys(),
		"core/lapidary/tracer/shaders/gem_mesh.glsl": baseline.keys(),
		"core/lapidary/tracer/gem_tracer.gd": baseline.keys(),
		"core/lapidary/render_identity.gd": baseline.keys(),
		"core/lapidary/tracer/new_unknown_pass.glsl": baseline.keys()
	}
	for path: String in cases:
		var edited := inventory.duplicate()
		edited[path] = "changed source".sha256_text()
		var after := identities(edited, jobs)
		for key: String in baseline:
			check((after[key] != baseline[key]) == cases[path].has(key), "%s -> %s dependency" % [path, key])
	var reordered := {}
	var paths := inventory.keys()
	paths.reverse()
	for path: String in paths:
		reordered[path] = inventory[path]
	check(identities(reordered, jobs) == baseline, "inventory enumeration order has no effect")
	for group: Array in GemRenderIdentity.EXCLUSIVE.values():
		for path: String in group:
			check(inventory.has(path), "classified dependency exists: " + path)
	for domain in GemRenderIdentity.DOMAINS:
		check(GemRenderIdentity.digest_inventory(domain, inventory, "other-engine") != GemRenderIdentity.digest_inventory(domain, inventory, "fixed-test-engine"), "compiler engine version changes " + domain)
	GemRenderIdentity._digests.clear()
	GemGeometryPlan._source_digest = ""
	print("Render dependencies: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
