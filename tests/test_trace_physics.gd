extends SceneTree

## Runs the native C++ physics validation tests embedded in GemTraceKernel.

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("\n=== Gem Trace Physics Tests ===\n")

	if not ClassDB.class_exists(&"GemTraceKernel"):
		print("  FAIL: GemTraceKernel not available (native extension not loaded)")
		quit(1)
		return

	var kernel = ClassDB.instantiate(&"GemTraceKernel")
	if not kernel.has_method("run_physics_tests"):
		print("  FAIL: run_physics_tests method not found on GemTraceKernel")
		quit(1)
		return

	var results: Dictionary = kernel.run_physics_tests()
	if results.is_empty():
		print("  FAIL: run_physics_tests returned empty results")
		quit(1)
		return

	var sorted_names: Array = results.keys()
	sorted_names.sort()

	for test_name in sorted_names:
		var test: Dictionary = results[test_name]
		if test.get("passed", false):
			_pass_count += 1
			print("  PASS: %s" % str(test_name))
		else:
			_fail_count += 1
			print("  FAIL: %s (expected %s, got %s)" % [
				str(test_name),
				str(test.get("expected", "?")),
				str(test.get("actual", "?"))
			])

	print("\n=== Results: %d passed, %d failed ===\n" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)
