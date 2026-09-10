extends SceneTree
## Launched only inside the isolated project created by pipeline_cache_check.
func _initialize() -> void:
	var args := {}
	for value in OS.get_cmdline_user_args():
		var pair := value.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://manifest.json"))
	var old_key: String = manifest.jobs.keys()[0]
	var record: Dictionary = manifest.jobs[old_key]
	var job: GemFrameJob = load("res://" + record.path)
	var current_master := GemFramePlan.master_key(job)
	var current_display := GemFramePlan.display_key(job)
	var current_geometry := GemGeometryPlan.key(job, 1)
	var phase: String = args.phase
	var failures := 0
	if GemRenderIdentity.worker_digest() == manifest.engine:
		failures += 1
	if phase == "shared":
		if current_master == record.master or current_geometry == record.geometry or current_display == old_key:
			failures += 1
	else:
		if current_master != record.master or current_geometry != record.geometry:
			failures += 1
		if (current_display == old_key) != (phase == "crystal"):
			failures += 1
		var worker := GemFrameWorker.new(args.store)
		var master_before: Dictionary = worker.store.read(current_master).metadata
		if worker.run(job).is_empty() or worker.counters.rendered != 0:
			failures += 1
		if phase == "crystal" and (worker.counters.display_hits != 1 or worker.tracer != null):
			failures += 1
		if phase == "print" and (worker.counters.reprinted != 1 or not worker.tracer._print_only or not worker.compiled.is_empty()):
			failures += 1
		if phase == "print" and worker.store.read(current_display).payload == worker.store.read(old_key).payload:
			failures += 1 # The edited print must visibly change pixels, not just keys.
		if worker.store.read(current_master).metadata != master_before:
			failures += 1 # Retain original producer provenance; do not relabel a hit.
		print({"phase": phase, "optical": worker.counters})
		worker.release()
		var geometry := GemGeometryWorker.new(args.store)
		if geometry.run(job, 1).is_empty() or geometry.counters.cache_hits != 1 or geometry.tracer != null:
			failures += 1
		geometry.release()
		if phase == "crystal":
			var destination: String = args.store + "-merged"
			var store := GemArtifactStore.new(destination)
			if not store.initialize():
				failures += 1
			manifest.engine = GemRenderIdentity.worker_digest()
			var transfer := GemStoreTransfer.new()
			var result := transfer.merge(destination, PackedStringArray([args.store]), manifest, true)
			if result.is_empty() or result.get("recipes_to_import") != 3:
				printerr(transfer.last_error)
				failures += 1
	print("Pipeline cache probe %s: %d failures" % [phase, failures])
	quit(1 if failures else 0)
