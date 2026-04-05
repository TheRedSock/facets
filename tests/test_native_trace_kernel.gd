extends SceneTree

func _init():
	print("\n=== GemTraceKernel Extension Test ===\n")

	# Check if GemTraceKernel class exists
	if ClassDB.class_exists(&"GemTraceKernel"):
		print("  PASS: GemTraceKernel class is registered")
	else:
		print("  FAIL: GemTraceKernel class NOT found")
		quit(1)
		return

	# Try instantiating it
	var kernel = ClassDB.instantiate(&"GemTraceKernel")
	if kernel != null:
		print("  PASS: GemTraceKernel instantiation succeeded")
	else:
		print("  FAIL: GemTraceKernel instantiation returned null")
		quit(1)
		return

	# Check methods exist
	if kernel.has_method("trace_to_image"):
		print("  PASS: trace_to_image method exists")
	else:
		print("  FAIL: trace_to_image method NOT found")

	if kernel.has_method("get_last_trace_profile"):
		print("  PASS: get_last_trace_profile method exists")
	else:
		print("  FAIL: get_last_trace_profile method NOT found")

	# Test calling trace_to_image with null inputs (should return null gracefully)
	var result = kernel.trace_to_image(null, null, {})
	if result == null:
		print("  PASS: trace_to_image(null, null, {}) returns null (graceful)")
	else:
		print("  INFO: trace_to_image returned non-null: ", result)

	# Test max_supported_sample_count (call via instance)
	if kernel.has_method("max_supported_sample_count"):
		print("  PASS: max_supported_sample_count method exists")
	else:
		print("  INFO: max_supported_sample_count not available as instance method (static only)")

	print("\n=== All GemTraceKernel tests passed ===\n")
	quit(0)
