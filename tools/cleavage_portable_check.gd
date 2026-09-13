extends SceneTree
## Actual isolated worker execution with an enabled typed condition recipe.
func _initialize()->void:
	var stone:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.cleavage=load("res://data/lapidary/conditions/diamond_cleavage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.cleavage.depth_mm=.3
	stone.crystal_to_stone=Quaternion(Vector3.UP,.4)
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.PREVIEW)[0]
	job.resolution=Vector2i(32,32);job.output_size=Vector2i(24,24);job.samples=8
	var root_path:=ProjectSettings.globalize_path("res://artifacts/cleavage/portable-%d" % Time.get_ticks_usec())
	var bundle_path:=root_path.path_join("bundle")
	var output_path:=root_path.path_join("output")
	var jobs:Array[GemFrameJob]=[job]
	var manifest:=GemJobBundle.write(bundle_path,jobs,{},2)
	if manifest.is_empty():printerr("FAIL: cleavage portable bundle");print("CHECK_COMPLETE: cleavage_portable_check"); quit(1);return
	var stages:=[PackedStringArray(["--headless","--editor","--quit"]),PackedStringArray(["--quit-after","600","--script","res://tools/gem_frame_worker.gd","--","--manifest=res://manifest.json","--output="+output_path])]
	for i in stages.size():
		var args:=PackedStringArray(["--audio-driver","Dummy","--path",bundle_path])
		args.append_array(stages[i])
		var lines:Array=[]
		var code:=OS.execute(OS.get_executable_path(),args,lines,true,false)
		var log_text:="\n".join(lines)
		GemArtifactStore.atomic_write(root_path.path_join("stage%d.log"%i),log_text.to_utf8_buffer())
		if code!=0 or "SCRIPT ERROR:" in log_text or "ERROR:" in log_text or "FAIL:" in log_text:
			printerr("FAIL: standalone cleavage stage %d: %s"%[i,log_text]);print("CHECK_COMPLETE: cleavage_portable_check"); quit(1);return
	var store:=GemArtifactStore.new(output_path)
	var master:=store.read(GemFramePlan.master_key(job))
	var geometry:=store.read(GemGeometryPlan.key(job,2))
	var display:=store.read(GemFramePlan.display_key(job))
	if master.is_empty() or geometry.is_empty() or display.is_empty() or master.metadata.get("condition_report",{}).get("cleavage",{}).get("host_cap_mm3",0.0)<=0:
		printerr("FAIL: standalone cleavage output or physical report missing");print("CHECK_COMPLETE: cleavage_portable_check"); quit(1);return
	print("Cleavage portable worker PASS: optical, geometry, condition report; "+root_path)
	print("CHECK_COMPLETE: cleavage_portable_check"); quit()
