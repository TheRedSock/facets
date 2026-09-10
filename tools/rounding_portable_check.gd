extends SceneTree
func _initialize()->void:
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition=load("res://data/lapidary/conditions/rounded_polish.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.rounding.angular_step_deg=12
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.INTERACT)[0]
	job.resolution=Vector2i(32,32);job.output_size=Vector2i(24,24);job.samples=8
	var base:=ProjectSettings.globalize_path("res://artifacts/rounding/portable-%d"%Time.get_ticks_usec())
	var bundle:=base.path_join("bundle");var output:=base.path_join("output")
	if GemJobBundle.write(bundle,[job],{},2).is_empty():printerr("FAIL: rounding bundle");quit(1);return
	var run:=PackedStringArray(["--quit-after","600","--script","res://tools/gem_frame_worker.gd","--","--manifest=res://manifest.json","--output="+output])
	var cached:=run.duplicate();cached.insert(0,"--headless")
	var stages:=[PackedStringArray(["--headless","--editor","--quit"]),run,cached]
	for i in stages.size():
		var args:=PackedStringArray(["--audio-driver","Dummy","--path",bundle]);args.append_array(stages[i])
		var lines:Array=[]
		var code:=OS.execute(OS.get_executable_path(),args,lines,true,false)
		var log_text:="\n".join(lines)
		GemArtifactStore.atomic_write(base.path_join("stage%d.log"%i),log_text.to_utf8_buffer())
		if code!=0 or "SCRIPT ERROR:" in log_text or "ERROR:" in log_text:
			printerr("FAIL: rounding portable stage %d %s"%[i,log_text]);quit(1);return
	var store:=GemArtifactStore.new(output)
	var master:=store.read(GemFramePlan.master_key(job));var geometry:=store.read(GemGeometryPlan.key(job,2))
	if master.is_empty() or geometry.is_empty() or master.metadata.get("condition_report",{}).get("rounding",{}).get("removed_mm3",0)<=0:
		printerr("FAIL: rounding physical outputs/report");quit(1);return
	print("Rounding portable PASS: optical master, removed-volume report, geometry and headless reuse; "+base);quit()
