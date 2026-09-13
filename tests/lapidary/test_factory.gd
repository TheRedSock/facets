extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var clip: GemClip = load("res://data/lapidary/clips/flash.tres")
	var jobs := GemFramePlan.animation(stone, clip, rig, GemPrint.load_house(), GemRung.CLIP_BAKE)
	var estimate := GemFramePlan.estimate(jobs)
	check(estimate["unique_masters"] == 1 and estimate["requested_frames"] == 6, "exposure-only animation shares one optical master")
	var job: GemFrameJob = jobs[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var key := GemFramePlan.master_key(job)
	var display := GemFramePlan.display_key(job)
	job.exposure *= 1.5
	check(GemFramePlan.master_key(job) == key and GemFramePlan.display_key(job) != display, "exposure changes reprint only")
	job.output_size = Vector2i(64, 64)
	check(GemFramePlan.master_key(job) == key, "delivery resolution reuses the optical master")
	job.quality["batch"] = 3
	check(GemFramePlan.master_key(job) == key, "batch partition is a scheduling choice")
	job.orientation = job.orientation * Quaternion(Vector3.UP, TAU)
	check(GemFramePlan.master_key(job) == key, "equivalent full-turn pose deduplicates")
	job.orientation = Quaternion(Vector3.UP, 0.1)
	check(GemFramePlan.master_key(job) != key, "actual rotation changes optics")
	var out := "res://artifacts/factory-tests/"
	DirAccess.make_dir_recursive_absolute(out)
	var error := GemResourceBundle.save(job, out + "job.tres")
	check(error == OK, "portable job serializes")
	var loaded: GemFrameJob = load(out + "job.tres")
	check(loaded != null and GemFramePlan.master_key(loaded) == GemFramePlan.master_key(job), "bundled resource job retains identity")
	check(not FileAccess.get_file_as_string(out + "job.tres").contains('[ext_resource type="Resource"'), "job bundles all authored resource dependencies")
	for i in jobs.size():
		var path := out + "exact%d.res" % i
		check(GemResourceBundle.save(jobs[i], path) == OK, "binary job saves")
		var binary: GemFrameJob = load(path)
		check(GemFramePlan.display_key(binary) == GemFramePlan.display_key(jobs[i]), "binary job preserves all exposure bits")
	var store := GemArtifactStore.new(out + "store")
	var payload := "first version".to_utf8_buffer()
	check(store.publish(key, payload, {"kind": "test"}), "publish content blob and record")
	check(store.read(key).get("payload") == payload, "checksum-verified roundtrip")
	payload = "second version".to_utf8_buffer()
	check(store.publish(key, payload, {"kind": "test"}) and store.read(key).get("payload") == payload, "atomic recipe replacement for resumable checkpoints")
	var record: Dictionary = store.read(key)["metadata"]
	FileAccess.open(store.root.path_join(record["object"]), FileAccess.WRITE).store_string("corrupt")
	check(store.read(key).is_empty(), "corrupted content is a cache miss")
	check(store.publish(key, payload, {"kind": "test"}) and not store.read(key).is_empty(), "corrupt object can be repaired")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBAF)
	image.fill(Color(2.5, 0.7, 1.1, 0.4))
	var restored := GemArtifactStore.decode_linear(GemArtifactStore.encode_linear(image))
	check(restored != null and restored.get_data() == image.get_data(), "linear XYZ/coverage compression is bit-exact above display range")
	check(store.read("../invalid").is_empty(), "artifact keys cannot escape the store")
	print("Factory: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_factory"); quit(1 if failures else 0)
