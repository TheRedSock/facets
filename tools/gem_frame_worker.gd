extends SceneTree
## Windowed worker, including inside a generated standalone job bundle.
## --manifest=... --output=... --shard=0 --shards=1 --sample-limit=0
## --outputs=all|optical|geometry (geometry companions must be requested in bundle)
## Exit 2 means retryable claimed work remains; exit 1 means an actual failure.
## --initialize-only=true creates the shared store once before parallel dispatch.
var _busy := 0
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
	if GemRenderIdentity.worker_digest() != manifest["engine"]:
		printerr("Worker optical engine/version differs from the job bundle")
		quit(1)
		return
	var shard := int(args.get("shard", 0))
	if args.get("initialize-only","")=="true":
		var store:=GemArtifactStore.new(args.get("output","res://output"))
		if not store.initialize():printerr("Cannot initialize artifact store");quit(1);return
		print("Artifact store initialized: "+store.root);quit();return
	var shards := int(args.get("shards", 1))
	var outputs: String = args.get("outputs", "all")
	var geometry: Variant = manifest.get("geometry", {})
	var geometry_error := GemGeometryPlan.references_error(manifest)
	if outputs not in ["all", "optical", "geometry"] or not geometry_error.is_empty() or (outputs == "geometry" and geometry.is_empty()):
		printerr("Invalid output selection or missing/invalid geometry requests: " + geometry_error)
		quit(1)
		return
	if shards < 1 or shard < 0 or shard >= shards:
		printerr("Invalid shard selection")
		quit(1)
		return
	var worker := GemFrameWorker.new(args.get("output", "res://output"))
	var keys: Array = manifest["jobs"].keys()
	if outputs == "geometry":
		keys.clear()
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
		var admission_error := GemJobValidator.validate(job)
		if not admission_error.is_empty():
			printerr("Job rejected before identity evaluation: " + admission_error)
			failures += 1
			continue
		if record.get("engine") != GemFramePlan.master_engine(job) or record.get("display_engine") != GemFramePlan.display_engine(job):
			printerr("Job pipeline identity differs from request: " + key)
			failures += 1
			continue
		if GemFramePlan.display_key(job) != key:
			printerr("Job identity mismatch: " + key)
			failures += 1
			continue
		var result := worker.run(job, int(args.get("sample-limit", 0)))
		if result.is_empty():
			failures += 1
		else:
			if result.get("status")=="busy":_busy+=1
			print(JSON.stringify({"job": key, "status": result.get("status", "complete"), "counters": worker.counters}))
	worker.release()
	if outputs != "optical":
		failures += _geometry(geometry, base, args.get("output", "res://output"), shard, shards)
	quit(1 if failures else (2 if _busy else 0))

func _geometry(records: Dictionary, base: String, output: String, shard: int, shards: int) -> int:
	var worker := GemGeometryWorker.new(output)
	var failures := 0
	var keys := records.keys()
	keys.sort()
	for key: String in keys:
		if key.left(8).hex_to_int() % shards != shard:
			continue
		var record: Dictionary = records[key]
		var relative := str(record.get("path", ""))
		if relative != "jobs/" + relative.get_file() or relative.get_extension() != "res" or not GemArtifactStore.valid_key(relative.get_file().get_basename()):
			printerr("Invalid geometry job path")
			failures += 1
			continue
		var path := base.path_join(relative)
		if FileAccess.get_sha256(path) != record.get("sha256"):
			printerr("Geometry input checksum mismatch")
			failures += 1
			continue
		var job := load(path) as GemFrameJob
		var side := int(record.coverage_side)
		if not GemGeometryPlan.validate(job, side).is_empty() or record.engine != GemGeometryPlan.source_digest() or job.resolution != Vector2i(int(record.width), int(record.height)) or GemGeometryPlan.key(job, side) != key:
			printerr("Geometry request or identity mismatch")
			failures += 1
			continue
		var result := worker.run(job, side)
		if result.is_empty():
			printerr(worker.last_error)
			failures += 1
		else:
			if result.get("status")=="busy":_busy+=1
			print(JSON.stringify({"geometry": key, "status": result.status, "counters": worker.counters}))
	worker.release()
	return failures
