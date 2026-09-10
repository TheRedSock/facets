extends SceneTree
## Windowed worker, including inside a generated standalone job bundle.
## --manifest=... --output=... --shard=0 --shards=1 --sample-limit=0
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var manifest_path: String = args.get("manifest", "res://manifest.json")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or manifest.get("schema") != 1:
		printerr("Invalid job manifest")
		quit(1)
		return
	var base := manifest_path.get_base_dir()
	for relative: String in manifest["source_sha256"]:
		if FileAccess.get_sha256(base.path_join(relative)) != manifest["source_sha256"][relative]:
			printerr("Worker source mismatch: " + relative)
			quit(1)
			return
	if GemRenderIdentity.optical_digest() != manifest["engine"]:
		printerr("Worker optical engine/version differs from the job bundle")
		quit(1)
		return
	var shard := int(args.get("shard", 0))
	var shards := int(args.get("shards", 1))
	if shards < 1 or shard < 0 or shard >= shards:
		printerr("Invalid shard selection")
		quit(1)
		return
	var worker := GemFrameWorker.new(args.get("output", "res://output"))
	var keys: Array = manifest["jobs"].keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ma: String = manifest["jobs"][a]["master"]
		var mb: String = manifest["jobs"][b]["master"]
		return ma < mb if ma != mb else a < b)
	var failures := 0
	for key: String in keys:
		var record: Dictionary = manifest["jobs"][key]
		var master: String = record["master"]
		# Keep all prints from one master on the same worker.
		if master.left(8).hex_to_int() % shards != shard:
			continue
		var path := base.path_join(record["path"])
		if FileAccess.get_sha256(path) != record["sha256"]:
			printerr("Job input checksum mismatch: " + key)
			failures += 1
			continue
		var job: GemFrameJob = load(path)
		if job == null or GemFramePlan.display_key(job) != key:
			printerr("Job identity mismatch: " + key)
			failures += 1
			continue
		var result := worker.run(job, int(args.get("sample-limit", 0)))
		if result.is_empty():
			failures += 1
		else:
			print(JSON.stringify({"job": key, "status": result.get("status", "complete"), "counters": worker.counters}))
	worker.release()
	quit(1 if failures else 0)
