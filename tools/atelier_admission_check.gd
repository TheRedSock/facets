extends SceneTree
## Actual UI/process workflow: current images only, durable edits and clean shutdown.
var failures:=0
var scene:Control
var heartbeat:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+message)
func _wait_status(expected:String,timeout_ms:=30000)->bool:
	var deadline:=Time.get_ticks_msec()+timeout_ms
	while Time.get_ticks_msec()<deadline:
		heartbeat+=1
		if scene.get("client").status==expected:return true
		if scene.get("client").status=="error" and expected!="error":printerr(scene.get("client").last_report);return false
		await process_frame
	return false
func _run()->void:
	scene=load("res://scenes/design/gem_atelier.tscn").instantiate();scene.set("auto_preview",false);root.add_child(scene)
	await process_frame
	var document:GemAuthoringDocument=scene.get("document")
	var request:GemAssetRequest=document.snapshot();request.rung="interact";request.samples=8;request.resolution=Vector2i(64,64);request.output_size=Vector2i(32,32)
	request.stone.seed=int(Time.get_ticks_usec()&0x7fffffff);request.asset_id=&"atelier_authored";request.stone.stone_id=&"atelier_authored"
	request.stone.cut.cut_id=&"atelier_authored_cut"
	request.stone.cut.parameters["table"]=.49
	request.clips=[load("res://data/lapidary/clips/tilt_return.tres")]
	document.create(request);scene.call("_changed")
	var destination:="res://artifacts/atelier-workflow/%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(destination)
	check(document.save(destination.path_join("new gem and cut ø.tres")).is_empty(),"Save new specimen/cut request")
	check(document.open(document.path).is_empty(),"Reopen saved request")
	scene.call("_submit","preview")
	if not await _wait_status("complete"):check(false,"Admitted process preview completes");await _finish();return
	var initial:Image=scene.call("debug_get_preview_image")
	check(initial!=null and initial.get_size()==Vector2i(32,32),"Saved preview has requested output dimensions")
	check(heartbeat>1,"UI continued processing while worker rendered")
	var first_report:Dictionary=scene.get("client").last_report.duplicate(true)
	scene.call("edit_value",["stone","size_mm"],-1.0)
	check(scene.call("debug_get_preview_image")==null,"Edit immediately clears previous image")
	scene.call("_submit","preview")
	check(await _wait_status("error"),"Unsupported draft reports worker admission error")
	check("size" in str(scene.get("client").last_report.get("error","")),"Shared admission provides size reason")
	scene.call("_undo");scene.call("_submit","preview")
	check(await _wait_status("complete"),"Corrected request recovers")
	var restored:Image=scene.call("debug_get_preview_image")
	check(restored!=null and restored.get_data()==initial.get_data(),"Saved preview and reopened/cached output agree")
	# An old completion arriving after an edit must never replace current content.
	var client:GemPreviewClient=scene.get("client")
	client.invalidate();var stale_before:=client.stale_results
	GemArtifactStore.atomic_write(client.session.path_join("response.json"),JSON.stringify(first_report).to_utf8_buffer())
	await process_frame;await process_frame
	check(client.stale_results>stale_before and scene.call("debug_get_preview_image")==null,"Stale completion is rejected")
	# Cancel after actual partial sampling, then resume that immutable job.
	var saved_request:GemAssetRequest=document.snapshot()
	var interrupted:=saved_request.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemAssetRequest
	interrupted.samples=64;interrupted.stone.seed+=1
	document.create(interrupted);scene.call("_changed");scene.call("_submit","preview")
	check(await _wait_status("rendering"),"Worker publishes progress before completing a longer request")
	var partial_samples:=int(client.last_report.get("samples",0))
	check(partial_samples>0 and partial_samples<64,"Cancellation fixture has real unfinished samples")
	client.invalidate();check(scene.call("debug_get_preview_image")==null,"Cancel immediately removes partial image")
	var interrupted_plan:=GemAssetPlanner.plan(_batch(interrupted))
	var interrupted_job:GemFrameJob=interrupted_plan.jobs[0]
	var store:=GemArtifactStore.new("res://generated/atelier/store")
	var checkpoint_key:=GemContentIdentity.digest(["checkpoint-v1",GemFramePlan.master_key(interrupted_job)])
	check(not store.read(checkpoint_key).is_empty(),"Canceled work retains a resumable checkpoint")
	check(store.read(GemFramePlan.display_key(interrupted_job)).is_empty(),"Canceled partial render is not published as a complete display")
	scene.call("_submit","preview");check(await _wait_status("complete"),"Canceled request resumes to completion")
	check(int(client.last_report.get("counters",{}).get("resumed_samples",0))>=partial_samples,"Recovery consumes the saved estimator samples")
	document.create(saved_request);scene.call("_changed")
	scene.call("_submit","inspect")
	check(await _wait_status("inspected"),"Worker returns compiler-derived facet inspection")
	check(client.last_report.get("inspection",{}).get("facets",[]).size()>8,"Facet IDs/meet overlay has actual compiled faces")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination.path_join("cut-inspection.png"))
	scene.call("_submit","build")
	check(await _wait_status("complete"),"Saved selection builds delivery library")
	var library:=GemAssetLibrary.new()
	check(library.open(client.last_report.get("library","")),"Built library passes actual delivery admission")
	var planned:=GemAssetPlanner.plan(_batch(document.snapshot()))
	var job:GemFrameJob=planned.jobs[0]
	var expected_frames:=[]
	for planned_job:GemFrameJob in planned.jobs:expected_frames.append(GemFramePlan.display_key(planned_job))
	check(library.manifest.get("clips",{}).get("atelier_authored/tilt_return",{}).get("frames",[])==expected_frames,"Build resolves every saved generic-motion frame")
	check(expected_frames.size()==16 and expected_frames[0]==GemFramePlan.display_key(job),"Saved tilt is a full sequence with the exact selected preview frame")
	var controls:Dictionary=scene.get("_c")
	controls.details.text="Validated new gem/cut, invalidation/recovery, saved-preview/build parity, current-request-only results."
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination.path_join("atelier.png"))
	GemArtifactStore.atomic_write(destination.path_join("report.json"),JSON.stringify(scene.call("debug_get_render_state"),"\t").to_utf8_buffer())
	# Close during active work, rather than only proving idle process shutdown.
	interrupted.stone.seed+=1;document.create(interrupted);scene.call("_changed");scene.call("_submit","preview")
	check(await _wait_status("rendering"),"Close fixture reaches active partial rendering")
	await _finish()
func _batch(request:GemAssetRequest)->GemAssetBatch:
	var batch:=GemAssetBatch.new();batch.requests=[request];return batch
func _finish()->void:
	var client:GemPreviewClient=scene.get("client");var pid:=client.worker_pid;var session:=client.session
	scene.free()
	var deadline:=Time.get_ticks_msec()+10000
	while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	check(pid>0 and not OS.is_process_running(pid),"Close stops render owner after a bounded unit")
	check("ATELIER_WORKER_STOPPED" in FileAccess.get_file_as_string(session.path_join("worker.log")),"Worker released ownership and completed shutdown")
	print("Atelier workflow failures: ",failures);print("CHECK_COMPLETE: atelier_admission_check");quit(1 if failures else 0)
