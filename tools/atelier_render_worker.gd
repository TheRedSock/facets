extends SceneTree
## The Atelier process owns one production GemFrameWorker and all GPU calls.
var session := ""
var worker: GemFrameWorker
var generation := -1
var _heartbeat := ""
var _heartbeat_at := 0
var _sequence := 0
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var store := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--session="):session=arg.trim_prefix("--session=")
		elif arg.begins_with("--store="):store=arg.trim_prefix("--store=")
		else:printerr("Invalid worker argument");quit(1);return
	if session.is_empty() or store.is_empty() or not DirAccess.dir_exists_absolute(session):quit(1);return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	worker=GemFrameWorker.new(store);_heartbeat_at=Time.get_ticks_msec()
	while not _abandoned():
		var message:=_message()
		if message.get("action")=="stop":break
		if int(message.get("generation",-1))>generation:
			generation=int(message.generation)
			if message.get("action")!="cancel":await _request(message)
			var cleanup_error := GemAtelierSessionFiles.collect(session, generation)
			if not cleanup_error.is_empty(): _error(cleanup_error)
		await create_timer(.02).timeout
	worker.release();print("ATELIER_WORKER_STOPPED");quit()
func _request(message:Dictionary)->void:
	var start:=Time.get_ticks_usec()
	var relative:=str(message.get("request",""))
	if relative!="request-%d.res"%generation or FileAccess.get_sha256(session.path_join(relative))!=message.get("sha256"):_error("Request checksum/path mismatch");return
	var request:=ResourceLoader.load(session.path_join(relative),"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GemAssetRequest
	var batch:=GemAssetBatch.new();batch.requests=[request]
	var plan:=GemAssetPlanner.plan(batch)
	if not plan.error.is_empty():_error(plan.error);return
	if not _current():return
	var mode:=str(message.get("action",""))
	if mode not in ["preview","build","plan","inspect"]:_error("Unknown worker action");return
	var jobs:Array[GemFrameJob]=plan.jobs
	var selected_clip:=int(message.get("clip",0));var selected_frame:=int(message.get("frame",0))
	if selected_clip<0 or selected_clip>=request.clips.size() or selected_frame<0 or selected_frame>=request.clips[selected_clip].frame_count():_error("Preview clip/frame is outside its authored range");return
	var clip_key:=String(request.asset_id)+"/"+String(request.clips[selected_clip].clip_id)
	var selected_key:String=plan.clips[clip_key].frames[selected_frame]
	var selected:GemFrameJob=null
	for job in jobs:
		if GemFramePlan.display_key(job)==selected_key:selected=job;break
	if selected==null:_error("Selected frame is missing from admitted plan");return
	var base:={"generation":generation,"estimate":plan.estimate,"capabilities":GemAuthoringAdmission.capabilities(selected),"plan_ms":(Time.get_ticks_usec()-start)/1000.0}
	if mode=="plan":base.status="planned";_send(base);return
	if mode=="inspect":
		var inspection:=GemCutInspection.inspect(selected.stone)
		if not inspection.error.is_empty():_error(inspection.error);return
		var faces:=[]
		for facet in inspection.facets:
			var points:=[]
			for point in facet.points_mm:points.append([point.x,point.y,point.z])
			faces.append({"name":facet.name,"id":facet.id,"points":points,"anchor":[facet.anchor_mm.x,facet.anchor_mm.y,facet.anchor_mm.z],"meets":Array(facet.meet_contacts)})
		var sections:=[]
		for normal in [Vector3.BACK,Vector3.UP]:
			var cut:=GemCutInspection.section(inspection.geometry,normal,0,selected.stone.size_mm)
			var points:=[]
			for point in cut.points_mm:points.append([point.x,point.y,point.z])
			sections.append(points)
		base.status="inspected";base.inspection={"facets":faces,"dimensions_mm":[inspection.dimensions_mm.x,inspection.dimensions_mm.y,inspection.dimensions_mm.z],"sections":sections,"diagnostics":inspection.geometry.diagnostics}
		if _current():_send(base)
		return
	if mode=="preview":
		selected.display_view=int(message.get("view",GemPrint.View.HOUSE_PRINT)) as GemPrint.View
		if selected.display_view==GemPrint.View.DISPLAY_PREVIEW:selected.game_style=null
		var why:=GemJobValidator.validate(selected)
		if not why.is_empty():_error(why);return
		jobs=[selected]
	var maximum_unit_ms:=0.0
	for index in jobs.size():
		var job:=jobs[index]
		while _current() and not _abandoned():
			var unit_start:=Time.get_ticks_usec()
			var result:=worker.run(job,4 if mode=="preview" else 16)
			maximum_unit_ms=maxf(maximum_unit_ms,(Time.get_ticks_usec()-unit_start)/1000.0)
			if not _current():return
			if result.is_empty():_error(worker.last_error);return
			var state:=str(result.get("status",""))
			var response:=base.duplicate(true)
			response.merge({"status":"rendering","frame":index,"frames":jobs.size(),"samples":result.get("samples",job.samples),"target_samples":job.samples,"maximum_unit_ms":maximum_unit_ms,"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"counters":worker.counters.duplicate(),"device":_device_report()},true)
			if state=="busy":response.status="waiting";_send(response);await create_timer(.1).timeout;continue
			if mode=="preview":
				var image:Image
				if state=="complete":image=GemFrameWorker._display_image(worker.store.read(GemFramePlan.display_key(job)),job,GemFramePlan.display_engine(job))
				else:image=worker.tracer.finalize_print(job.print_style,job.display_view,job.exposure,job.output_size)
				if image==null:_error("Cannot read preview image");return
				if not _attach_image(response,image):return
				response.display=GemFramePlan.display_key(job)
				if state=="complete":response.status="complete"
			_send(response)
			if state=="complete":break
			await process_frame
		if not _current() or _abandoned():return
	if mode=="build":
		var destination:=session.path_join("delivery-%d"%generation)
		var packer:=GemPagePacker.new(worker.store,destination)
		var packed:=packer.pack(plan.clips)
		if packed.is_empty():_error(packer.last_error);return
		base.merge({"status":"complete","library":destination.path_join("library.json"),"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"counters":worker.counters.duplicate(),"device":_device_report()},true)
		var image:=GemFrameWorker._display_image(worker.store.read(GemFramePlan.display_key(selected)),selected,GemFramePlan.display_engine(selected))
		if image==null or not _attach_image(base,image):return
		if _current():_send(base)
func _attach_image(response:Dictionary,image:Image)->bool:
	_sequence+=1;var filename:="preview-%d-%d.png"%[generation,_sequence]
	if image.save_png(session.path_join(filename))!=OK:_error("Cannot save preview image");return false
	response.image=filename;response.image_sha256=FileAccess.get_sha256(session.path_join(filename));return true
func _message()->Dictionary:
	var path:=session.path_join("request.json")
	if not FileAccess.file_exists(path):return {}
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func _current()->bool:
	var current:=_message()
	return int(current.get("generation",-1))==generation and current.get("action") not in ["stop","cancel"]
func _abandoned()->bool:
	var path:=session.path_join("heartbeat")
	var latest:=FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if latest!=_heartbeat:_heartbeat=latest;_heartbeat_at=Time.get_ticks_msec()
	return Time.get_ticks_msec()-_heartbeat_at>30000
func _send(response:Dictionary)->void:
	if not GemArtifactStore.atomic_write(session.path_join("response.json"),JSON.stringify(response).to_utf8_buffer()):
		printerr("Cannot publish Atelier response");return
	var cleanup_error := GemAtelierSessionFiles.collect(session, generation)
	if not cleanup_error.is_empty(): printerr(cleanup_error)
func _error(why:String)->void:_send({"generation":generation,"status":"error","error":why})

func _device_report()->Dictionary:
	if worker.tracer==null:return {"status":"not_initialized"}
	var rd:RenderingDevice=worker.tracer.get("_rd")
	return {"name":rd.get_device_name(),"godot":Engine.get_version_info(),
		"allocator_buffer_bytes":rd.get_memory_usage(RenderingDevice.MEMORY_BUFFERS),
		"allocator_texture_bytes":rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES),
		"allocator_total_bytes":rd.get_memory_usage(RenderingDevice.MEMORY_TOTAL),
		"driver_internal_bytes_reported":rd.get_driver_total_memory(),
		"max_texture_2d":rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D),
		"max_storage_buffers_per_stage":rd.limit_get(RenderingDevice.LIMIT_MAX_STORAGE_BUFFERS_PER_SHADER_STAGE),
		"max_push_constant_bytes":rd.limit_get(RenderingDevice.LIMIT_MAX_PUSH_CONSTANT_SIZE),
		"captured_gpu_timestamp_count":rd.get_captured_timestamps_count(),
		"timing_note":"Unit/plan/elapsed values are wall time. A zero timestamp count means GPU-only timing is unavailable, not zero cost."}
