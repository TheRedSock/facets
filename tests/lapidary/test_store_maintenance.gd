extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hold-root="):
			call_deferred("_hold", argument.trim_prefix("--hold-root="))
			return
	call_deferred("_run")

func _hold(root: String) -> void:
	var guard := GemStoreGuard.enter(root, "cross-process-test")
	if guard == null:
		quit(1)
		return
	GemArtifactStore.atomic_write(root.path_join("child-ready"), "ready".to_utf8_buffer())
	await create_timer(2.0).timeout
	guard.release()
	quit()

func _run() -> void:
	var root := "res://artifacts/store-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store := GemArtifactStore.new(root)
	var master_a := "master-a".sha256_text()
	var master_b := "master-b".sha256_text()
	var display_a := "display-a".sha256_text()
	var display_b := "display-b".sha256_text()
	var pending := "pending-master".sha256_text()
	var pending_display := "pending-display".sha256_text()
	var completed_checkpoint := GemContentIdentity.digest(["checkpoint-v1", master_a])
	var pending_checkpoint := GemContentIdentity.digest(["checkpoint-v1", pending])
	var master_bytes := "shared physical master".to_utf8_buffer()
	check(store.publish(master_a, master_bytes, {"kind": "linear_master"}), "publish first master")
	check(store.publish(master_b, master_bytes, {"kind": "linear_master"}), "publish deduplicated second master")
	check(store.publish(display_a, "display a".to_utf8_buffer(), {"kind": "display", "master": master_a}), "publish required display")
	store.publish(display_b, "display b".to_utf8_buffer(), {"kind": "display", "master": master_b})
	store.publish(completed_checkpoint, "obsolete checkpoint".to_utf8_buffer(), {"kind": "checkpoint"})
	store.publish(pending_checkpoint, "partial checkpoint".to_utf8_buffer(), {"kind": "checkpoint"})
	var overwrite := "overwritten".sha256_text()
	store.publish(overwrite, "old orphan".to_utf8_buffer(), {"kind": "test"})
	store.publish(overwrite, "new orphan".to_utf8_buffer(), {"kind": "test"})
	GemArtifactStore.atomic_write(root.path_join("keep.txt"), "unrelated".to_utf8_buffer())
	GemArtifactStore.atomic_write(root.path_join("objects/aa/notes.txt"), "not a blob".to_utf8_buffer())
	var partial := "partial".sha256_text()
	var partial_path := root.path_join("objects/%s/%s.blob.123.456.tmp" % [partial.left(2), partial])
	GemArtifactStore.atomic_write(partial_path, "interrupted write".to_utf8_buffer())
	var manifest := {"schema": 1, "jobs": {display_a: {"master": master_a}, pending_display: {"master": pending}}}
	var maintenance := GemStoreMaintenance.new()
	var guard := GemStoreGuard.enter(root)
	check(maintenance.collect(root, [manifest], 0).is_empty(), "active reader prevents collection")
	guard.release()
	_scoped_activity(root)
	var exclusive := GemStoreGuard.exclusive(root)
	check(exclusive != null and GemStoreGuard.enter(root) == null, "maintenance prevents new workers")
	check(GemStoreGuard.exclusive(root) == null, "maintenance lock is exclusive")
	check(not store.publish("blocked".sha256_text(), "x".to_utf8_buffer(), {}), "publication cannot race maintenance")
	exclusive.release()
	var preview := maintenance.collect(root, [manifest], 0)
	check(not preview.is_empty() and preview["kept_recipes"] == 3 and preview["kept_objects"] == 3, "pins keep master, display and incomplete checkpoint only")
	check(preview.get("over_budget_bytes", 0) > 0, "required assets survive an undersized budget")
	check(not store.read(master_b).is_empty(), "dry-run leaves files intact")
	var applied := maintenance.collect(root, [manifest], 0, true)
	check(applied.get("removed_bytes", 0) == preview.get("removed_bytes", -1), "apply matches the locked inventory")
	check(store.read(master_a).get("payload") == master_bytes, "shared blob survives removal of its other recipe")
	check(not store.read(display_a).is_empty() and not store.read(pending_checkpoint).is_empty(), "required display and resume point survive")
	check(store.read(master_b).is_empty() and store.read(completed_checkpoint).is_empty(), "unneeded recipe and completed checkpoint removed")
	check(FileAccess.file_exists(root.path_join("keep.txt")) and FileAccess.file_exists(root.path_join("objects/aa/notes.txt")), "unrelated files are never collected")
	check(not FileAccess.file_exists(partial_path), "interrupted cache-owned temporary is collected")
	check(maintenance.collect(root, [manifest], 0).get("files_to_remove", -1) == 0, "collection is idempotent")
	store.publish(master_b, "optional master".to_utf8_buffer(), {"kind": "linear_master"})
	check(maintenance.collect(root, [manifest], 1024 * 1024).get("kept_recipes", 0) == 4, "spare budget retains optical masters")
	# A corrupt completed master must not discard the only resumable checkpoint.
	store.publish(pending, "broken master".to_utf8_buffer(), {"kind": "linear_master"})
	var record: Dictionary = store.read(pending)["metadata"]
	GemArtifactStore.atomic_write(root.path_join(record["object"]), "xxxxxx xxxxxx".to_utf8_buffer())
	var retained := maintenance.collect(root, [manifest], 0)
	check(retained.get("kept_recipes", 0) == 4, "checksum corruption preserves the pending checkpoint")
	var other_root := root.path_join("unmarked")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(other_root))
	check(maintenance.collect(other_root, [], 0, true).is_empty(), "unmarked directory is not a cache")
	var child := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/lapidary/test_store_maintenance.gd", "--", "--hold-root=" + root]), false)
	var deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(root.path_join("child-ready")) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(child > 0 and FileAccess.file_exists(root.path_join("child-ready")), "second process registers cache activity")
	check(maintenance.collect(root, [manifest], 0).is_empty(), "another process prevents collection")
	while child > 0 and OS.is_process_running(child) and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(not maintenance.collect(root, [manifest], 0).is_empty(), "collection resumes after worker releases activity")
	print("Store maintenance: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _scoped_activity(root: String) -> void:
	var guard := GemStoreGuard.enter(root, "scope-exit-test")
	check(guard != null, "scope guard created; normal destruction releases its token")
