extends SceneTree
## Field spectra must survive binary bundles, isolated workers and resume.
func _initialize()->void:
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material=load("res://data/lapidary/materials/measured_corundum/clear_host.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition=load("res://data/lapidary/conditions/corundum_bicolor.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=.1
	stone.size_mm=4
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.PREVIEW)[0]
	job.resolution=Vector2i(32,32);job.output_size=Vector2i(24,24);job.samples=16
	var root_path:=ProjectSettings.globalize_path("res://artifacts/materials/composition-portable-%d"%Time.get_ticks_usec())
	var bundle_path:=root_path.path_join("bundle")
	var output_path:=root_path.path_join("output")
	var manifest:=GemJobBundle.write(bundle_path,[job],{},2)
	if manifest.is_empty():printerr("FAIL: composition portable bundle");quit(1);return
	var worker_args:=PackedStringArray(["--quit-after","600","--script","res://tools/gem_frame_worker.gd","--","--manifest=res://manifest.json","--output="+output_path])
	var partial:=worker_args.duplicate();partial.append("--sample-limit=8")
	var cached:=worker_args.duplicate();cached.insert(0,"--headless")
	var stages:=[PackedStringArray(["--headless","--editor","--quit"]),partial,worker_args,cached]
	for i in stages.size():
		var args:=PackedStringArray(["--audio-driver","Dummy","--path",bundle_path]);args.append_array(stages[i])
		var lines:Array=[]
		var code:=OS.execute(OS.get_executable_path(),args,lines,true,false)
		var log_text:="\n".join(lines)
		GemArtifactStore.atomic_write(root_path.path_join("stage%d.log"%i),log_text.to_utf8_buffer())
		if code!=0 or "SCRIPT ERROR:" in log_text or "ERROR:" in log_text or "FAIL:" in log_text:
			printerr("FAIL: standalone composition stage %d: %s"%[i,log_text]);quit(1);return
		if i==1 and not '"status":"partial"' in log_text.replace(" ",""):
			printerr("FAIL: composition checkpoint was not partial: "+log_text);quit(1);return
		if i==2 and not '"resumed_samples":8' in log_text.replace(" ",""):
			printerr("FAIL: composition checkpoint was not resumed: "+log_text);quit(1);return
		if i==3 and not '"display_hits":1' in log_text.replace(" ",""):
			printerr("FAIL: composition display was not cached: "+log_text);quit(1);return
	var store:=GemArtifactStore.new(output_path)
	var master:=store.read(GemFramePlan.master_key(job))
	var geometry:=store.read(GemGeometryPlan.key(job,2))
	var display:=store.read(GemFramePlan.display_key(job))
	if master.is_empty() or geometry.is_empty() or display.is_empty():
		printerr("FAIL: standalone composition outputs missing");quit(1);return
	print("Composition portable worker PASS: partial, resume, optical, geometry, headless cache; "+root_path)
	quit()
