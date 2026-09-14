extends SceneTree
## Shared assertion accounting. A completion marker is emitted only by finish().
var failures: Array[String] = []
var assertions := 0

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)

func finish(stage: String) -> void:
	print("%s: %d assertions, %d failures" % [stage, assertions, failures.size()])
	print("CHECK_COMPLETE: " + stage)
	quit(0 if failures.is_empty() else 1)
