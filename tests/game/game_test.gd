extends SceneTree
## Shared assertion accounting. A completion marker is emitted only by finish().
var failures: Array[String] = []
var assertions := 0
var _report_root := ""

func report_path(filename: String) -> String:
	if _report_root.is_empty():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--report-root="): _report_root = arg.trim_prefix("--report-root=")
		if _report_root.is_empty(): _report_root = "res://artifacts/game/check-runs/%d-%d" % [Time.get_unix_time_from_system(),OS.get_process_id()]
		check(DirAccess.make_dir_recursive_absolute(_report_root) == OK,"report directory created")
	return _report_root.path_join(filename)

func write_report(filename: String, value: Variant, canonical: bool = false) -> void:
	var path := report_path(filename)
	check(not FileAccess.file_exists(path),"report never overwrites evidence: "+path)
	if FileAccess.file_exists(path): return
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"report writable: "+path)
	if file == null: return
	if canonical: file.store_buffer(CanonicalCodec.encode(value))
	else: file.store_string(JSON.stringify(value,"\t"))
	file.close()

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)

func finish(stage: String) -> void:
	print("%s: %d assertions, %d failures" % [stage, assertions, failures.size()])
	print("CHECK_COMPLETE: " + stage)
	quit(0 if failures.is_empty() else 1)
