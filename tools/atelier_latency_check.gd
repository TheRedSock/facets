extends SceneTree
## End-to-end scene-thread edit acknowledgement and production-worker latency.
## Run without another optical/GPU workload; timings include UI presentation.
const EDIT_BUDGET_MS := 100.0
const REPETITIONS := 5
var scene: Control
var failures: Array[String] = []
var records: Array[Dictionary] = []
var output := ""
var _operation_start := 0
var _first_image_ms := -1.0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	output = "res://artifacts/atelier-latency/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(output)
	var cold_start := Time.get_ticks_usec()
	scene = load("res://scenes/design/gem_atelier.tscn").instantiate()
	scene.set("auto_preview", false);root.add_child(scene)
	var client: GemPreviewClient = scene.get("client")
	client.updated.connect(func(_report: Dictionary, image: Image) -> void:
		if image != null and _first_image_ms < 0: _first_image_ms = (Time.get_ticks_usec()-_operation_start)/1000.0)
	var document: GemAuthoringDocument = scene.get("document")
	var request: GemAssetRequest = document.snapshot()
	request.rung = "preview";request.samples = 64
	request.resolution = Vector2i(224,224);request.output_size = Vector2i(112,112)
	request.stone.seed = int(Time.get_ticks_usec() & 0x7fffffff)
	request.presentation.orientation_mode = GemPresentation.OrientationMode.CUSTOM
	document.create(request);scene.call("_changed")
	await _measure("cold", [], null, cold_start)
	for kind in ["material", "geometry", "pose", "print"]:
		for index in REPETITIONS:
			if not failures.is_empty(): break
			var path: Array
			var value: Variant
			match kind:
				"material": path = ["stone","material","scatter_per_mm"];value = .005*(index+1)
				"geometry": path = ["stone","cut","parameters","table"];value = .54+.01*index
				"pose": path = ["presentation","orientation_deg"];value = Vector3(2.0*(index+1),0,0)
				"print": path = ["print_style","exposure"];value = 1.1+.05*index
			await _measure(kind, path, value, Time.get_ticks_usec())
	var summary := {}
	for kind in ["cold", "material", "geometry", "pose", "print"]:
		var group := records.filter(func(record: Dictionary) -> bool: return record.kind == kind)
		var metrics := {}
		for metric in ["acknowledgement_ms", "first_image_ms", "complete_ms", "submit_ms"]:
			var values: Array[float] = []
			for record: Dictionary in group: values.append(float(record[metric]))
			metrics[metric] = _percentiles(values)
		summary[kind] = metrics
	var frames: Array[float] = scene.get("_frame_times")
	var report := {"status":"passed" if failures.is_empty() else "failed", "failures":failures,
		"edit_acknowledgement_budget_ms":EDIT_BUDGET_MS, "records":records, "summary":summary,
		"ui_frame_ms":_percentiles(frames), "device":client.last_report.get("device",{}),
		"source_inventory":GemRenderIdentity.inventory(), "session":client.session,
		"measurement":"Actual document edit, immutable request submission and next UI draw. Preview completion is separate from the 100 ms acknowledgement budget. Cold includes scene/worker initialization; later cases retain the same worker. Run with the GPU otherwise idle."}
	var pid := client.worker_pid
	scene.free()
	var deadline := Time.get_ticks_msec()+15000
	while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline: await create_timer(.05).timeout
	if pid>0 and OS.is_process_running(pid): failures.append("Worker did not stop after benchmark")
	report.status = "passed" if failures.is_empty() else "failed"
	GemArtifactStore.atomic_write(output.path_join("report.json"),JSON.stringify(report,"\t").to_utf8_buffer())
	for why in failures: printerr("FAIL: "+why)
	print("Atelier latency report: ",output);print("CHECK_COMPLETE: atelier_latency_check")
	quit(1 if not failures.is_empty() else 0)
func _measure(kind: String, path: Array, value: Variant, started: int) -> void:
	var client: GemPreviewClient = scene.get("client")
	var before: Dictionary = client.last_report.get("counters",{}).duplicate()
	_operation_start = started;_first_image_ms = -1
	if not path.is_empty(): scene.call("edit_value",path,value)
	scene.call("_submit","preview")
	await process_frame;await RenderingServer.frame_post_draw
	var acknowledgement_ms := (Time.get_ticks_usec()-started)/1000.0
	if kind!="cold" and acknowledgement_ms>EDIT_BUDGET_MS:
		failures.append("%s edit acknowledgement %.2f ms exceeds %.1f ms"%[kind,acknowledgement_ms,EDIT_BUDGET_MS])
	var deadline := Time.get_ticks_msec()+120000
	while client.status not in ["complete","error"] and Time.get_ticks_msec()<deadline: await process_frame
	if client.status!="complete":failures.append("%s preview failed/timed out: %s"%[kind,client.last_report.get("error",client.status)])
	var after: Dictionary = client.last_report.get("counters",{})
	var delta := {}
	for key in after: delta[key] = int(after[key])-int(before.get(key,0))
	if kind=="print" and (int(delta.get("rendered",0))!=0 or int(delta.get("reprinted",0))!=1):
		failures.append("Print-only edit did not reuse its optical master")
	records.append({"kind":kind,"acknowledgement_ms":acknowledgement_ms,
		"first_image_ms":_first_image_ms,"complete_ms":(Time.get_ticks_usec()-started)/1000.0,
		"submit_ms":client.submit_ms,"counter_delta":delta,"worker":client.last_report.duplicate(true)})
	print("Atelier latency ",kind,": acknowledge ",acknowledgement_ms," ms; complete ",records.back().complete_ms," ms")
func _percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"samples":0}
	var sorted := values.duplicate();sorted.sort()
	return {"samples":sorted.size(),"p50":sorted[int(ceil(sorted.size()*.5))-1],
		"p95":sorted[int(ceil(sorted.size()*.95))-1],"max":sorted.back()}
