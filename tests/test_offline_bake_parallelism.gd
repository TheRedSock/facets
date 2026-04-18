extends SceneTree

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Offline Bake Parallelism Tests ===\n")
	await process_frame
	test_auto_parallel_plan_uses_multiple_workers()
	test_explicit_variant_workers_share_cpu_budget()
	test_trace_thread_heuristic_avoids_overthreading_small_images()
	test_trace_thread_heuristic_scales_for_larger_images()
	test_environment_override_wins_over_default_environment()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_auto_parallel_plan_uses_multiple_workers() -> void:
	var job = OfflineGemBakeJobScript.new()
	var plan: Dictionary = job._resolve_parallel_execution_plan(8, {"processor_count_override": 13})
	assert_eq(plan.get("variant_worker_count", 0), 2, "Auto plan should open two variant workers on a 12-core budget")
	assert_eq(plan.get("trace_thread_budget", 0), 6, "Auto plan should split the CPU budget across the variant workers")
	assert_true(bool(plan.get("pipeline_enabled", false)), "Auto plan should enable the trace pipeline when multiple workers are active")


func test_explicit_variant_workers_share_cpu_budget() -> void:
	var job = OfflineGemBakeJobScript.new()
	var plan: Dictionary = job._resolve_parallel_execution_plan(6, {
		"processor_count_override": 13,
		"variant_worker_count": 3,
	})
	assert_eq(plan.get("variant_worker_count", 0), 3, "Explicit variant worker override should be respected when budget allows it")
	assert_eq(plan.get("trace_thread_budget", 0), 4, "Per-trace thread budget should shrink to fit the requested worker count")


func test_trace_thread_heuristic_avoids_overthreading_small_images() -> void:
	var thread_count := OfflineGemBakeJobScript.resolve_trace_thread_count(
		{"thread_budget": 8},
		Vector2i(48, 48),
		1,
		3
	)
	assert_eq(thread_count, 1, "Tiny preview traces should stay single-threaded")


func test_trace_thread_heuristic_scales_for_larger_images() -> void:
	var thread_count := OfflineGemBakeJobScript.resolve_trace_thread_count(
		{"thread_budget": 8},
		Vector2i(128, 128),
		2,
		7
	)
	assert_true(thread_count > 1 and thread_count <= 8, "Larger traced bakes should use multiple threads within the requested budget")


func test_environment_override_wins_over_default_environment() -> void:
	var job = OfflineGemBakeJobScript.new()
	var warm_env = load("res://data/environments/neutral_warm_reference.tres")
	var visual: GemVisualResource = load("res://data/visuals/ruby.tres")
	assert_true(warm_env != null and warm_env.has_method("to_trace_dict"), "Warm reference environment should load")
	assert_true(visual != null, "Ruby visual should load for environment override test")
	if warm_env == null or visual == null:
		return

	var requests: Array = job._enrich_request_list(
		[{
			"visual": visual,
			"tile_id": &"ruby",
			"variant_key": "ruby@rot_01",
		}],
		1,
		{"environment_override": warm_env}
	)
	assert_true(requests.size() == 1, "Environment override test should enrich one request")
	if requests.is_empty():
		return

	var profile: Dictionary = requests[0].get("environment_profile", {})
	assert_eq(
		profile.get("sky_low"),
		warm_env.to_trace_dict().get("sky_low"),
		"Environment override should replace the default gameplay environment"
	)


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)


func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])
