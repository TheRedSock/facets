extends SceneTree
var checks := 0
var failures := 0
var engine_id := "test-engine".sha256_text()
var print_id := "test-print".sha256_text()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func store(root: String) -> GemArtifactStore:
	var result := GemArtifactStore.new(root)
	check(result.initialize(), "initialize an empty store")
	return result

func master(output: GemArtifactStore, key: String, value: float) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBAF)
	image.fill(Color(value, value, value, 1))
	check(output.publish(key, GemArtifactStore.encode_linear(image), {"kind": "linear_master", "engine": engine_id,
		"space": "associated_XYZ_CIE1931_2deg", "width": 2, "height": 2, "samples": 16}), "publish master fixture")

func display(output: GemArtifactStore, key: String, dependency: String) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.5, 0.6, 1))
	check(output.publish(key, image.save_webp_to_buffer(false), {"kind": "display", "master": dependency, "engine": print_id,
		"space": "srgb_straight_alpha", "width": 2, "height": 2, "codec": "webp_lossless", "status": "complete"}), "publish display fixture")

func _initialize() -> void:
	var root := "res://artifacts/transfer-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var destination := store(root + "/destination")
	var first := store(root + "/first")
	var second := store(root + "/second")
	var m1 := "master1".sha256_text()
	var m2 := "master2".sha256_text()
	var d1 := "display1".sha256_text()
	var d2 := "display2".sha256_text()
	master(first, m1, 0.2)
	display(first, d1, m1)
	master(second, m2, 0.3)
	display(second, d2, m2)
	master(second, m1, 0.2)
	var unrelated := "unrelated".sha256_text()
	first.publish(unrelated, "not requested".to_utf8_buffer(), {"kind": "test"})
	var manifest := {"schema": 1, "engine": "worker-build".sha256_text(), "jobs": {
		d1: {"master": m1, "engine": engine_id, "display_engine": print_id},
		d2: {"master": m2, "engine": engine_id, "display_engine": print_id}}}
	var transfer := GemStoreTransfer.new()
	var inputs := PackedStringArray([first.root, second.root])
	var preview := transfer.merge(destination.root, inputs, manifest)
	check(preview.get("recipes_to_import") == 4 and preview.get("duplicates") == 1 and preview.get("missing", [0]).is_empty(), "partial shards consolidate and deduplicate")
	check(destination.read(d1).is_empty(), "dry run preserves destination")
	var applied := transfer.merge(destination.root, inputs, manifest, true)
	check(applied.get("recipes_to_import") == 4, "apply imports the validated inventory")
	check(destination.read(m1).get("payload") == first.read(m1).get("payload") and not destination.read(d2).is_empty(), "masters and displays retain exact bytes")
	check(destination.read(unrelated).is_empty(), "unrequested recipes are excluded")
	check(transfer.merge(destination.root, inputs, manifest, true).get("recipes_to_import") == 0, "repeat transfer is idempotent")
	master(second, m1, 0.7)
	var prior: PackedByteArray = destination.read(m1).payload
	check(transfer.merge(destination.root, inputs, manifest, true).is_empty() and transfer.last_error.contains("Conflicting"), "conflicting physical masters reject the whole inventory")
	check(not transfer.last_report.get("conflicts", []).is_empty(), "conflict evidence identifies both payload hashes")
	check(destination.read(m1).payload == prior, "conflict rejection preserves existing bytes")
	var keep := transfer.merge(destination.root, inputs, manifest, true, "keep_existing")
	check(not keep.is_empty() and keep.conflicts.size() == 1 and destination.read(m1).payload == prior, "explicit precedence preserves destination")
	var guard := GemStoreGuard.enter(first.root)
	check(transfer.merge(destination.root, inputs, manifest).is_empty() and transfer.last_error.contains("active"), "running source refuses consolidation")
	guard.release()
	check(transfer.merge(destination.root, PackedStringArray([destination.root]), manifest).is_empty(), "same-store transfer rejected")
	check(transfer.merge(destination.root, PackedStringArray([destination.root + "/child"]), manifest).is_empty(), "nested-store transfer rejected")
	var wrong := manifest.duplicate(true)
	wrong.engine = "other-engine".sha256_text()
	check(not transfer.merge(destination.root, inputs, wrong, false, "keep_existing").is_empty(), "different worker build may reuse matching result pipelines")
	wrong.jobs[d1].engine = "incompatible-pipeline".sha256_text()
	check(transfer.merge(destination.root, inputs, wrong).is_empty() and transfer.last_error.contains("engine"), "wrong optical pipeline rejected")
	wrong = manifest.duplicate(true)
	wrong.jobs[d1].display_engine = "incompatible-print".sha256_text()
	check(transfer.merge(destination.root, inputs, wrong).is_empty() and transfer.last_error.contains("engine"), "wrong print pipeline rejected")
	var corrupt: Dictionary = first.read(d1).metadata
	GemArtifactStore.atomic_write(first.root.path_join(corrupt.object), "truncated".to_utf8_buffer())
	check(transfer.merge(destination.root, inputs, manifest).is_empty() and transfer.last_error.contains("Corrupt"), "corrupt source fails before importing")
	check(destination.read(m1).payload == prior, "failed transfer preserves existing destination")
	var empty := store(root + "/empty")
	var missing := transfer.merge(empty.root, PackedStringArray([second.root]), manifest)
	check(missing.get("missing", []).has(d1), "incomplete farm return reports missing frames")
	print("Store transfer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
