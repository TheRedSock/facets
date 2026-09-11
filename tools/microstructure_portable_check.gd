extends SceneTree
func _initialize()->void:
	var source:GemStone=load("res://data/lapidary/stones/quartz.tres")
	var recipe:GemMicrostructureRecipe=load("res://data/lapidary/microstructures/diagnostic_crystal_layer.tres")
	var realized:=GemMicrostructureCompiler.realize(source,recipe)
	if not realized.error.is_empty():printerr("FAIL: "+realized.error);quit(1);return
	var job:=GemFramePlan.animation(realized.stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.INTERACT)[0]
	job.resolution=Vector2i(48,48);job.output_size=Vector2i(32,32);job.samples=16
	var jobs:Array[GemFrameJob]=[]
	for pose in 3:
		var frame:GemFrameJob=job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		frame.orientation=Quaternion(Vector3.UP,.2*pose);jobs.append(frame)
	var base:=ProjectSettings.globalize_path("res://artifacts/microstructure/portable-%d"%Time.get_ticks_usec())
	var bundle:=base.path_join("bundle");var output:=base.path_join("output")
	if GemJobBundle.write(bundle,jobs,{},2).is_empty():printerr("FAIL: microstructure bundle");quit(1);return
	var run:=PackedStringArray(["--quit-after","600","--script","res://tools/gem_frame_worker.gd","--","--manifest=res://manifest.json","--output="+output])
	var cached:=run.duplicate();cached.insert(0,"--headless")
	for stage in [PackedStringArray(["--headless","--editor","--quit"]),run,cached]:
		var args:=PackedStringArray(["--audio-driver","Dummy","--path",bundle]);args.append_array(stage)
		var lines:Array=[];var code:=OS.execute(OS.get_executable_path(),args,lines,true,false)
		var log_text:="\n".join(lines)
		if code!=0 or "SCRIPT ERROR:" in log_text or "ERROR:" in log_text:printerr("FAIL: microstructure portable "+log_text);quit(1);return
	var store:=GemArtifactStore.new(output)
	for frame in jobs:
		if store.read(GemFramePlan.master_key(frame)).is_empty() or store.read(GemGeometryPlan.key(frame,2)).is_empty():printerr("FAIL: missing populated specimen outputs");quit(1);return
	print("Microstructure portable PASS: three physical specimens/poses, geometry companions and headless cache reuse; "+base);quit()
