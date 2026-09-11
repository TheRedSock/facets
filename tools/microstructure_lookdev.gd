extends SceneTree
## Unstyled, physically sized population study. Synthetic optical coefficients
## are labeled; this is not a geological-provenance or clarity calibration.
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var output:="res://artifacts/microstructure/lookdev"
	DirAccess.make_dir_recursive_absolute(output)
	var source:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	source.condition=GemCondition.new();source.material.scatter_per_mm=0
	var recipe:GemMicrostructureRecipe=load("res://data/lapidary/microstructures/diagnostic_crystal_layer.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var population:=recipe.populations[0]
	var tracer:=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	var rig:GemLightRig=load("res://data/lapidary/rigs/gameplay_studio.tres")
	var policy:=GemRung.policy(GemRung.PREVIEW)
	var records:=[]
	for count in [0,6,18]:
		population.count=count
		var realized:=GemMicrostructureCompiler.realize(source,recipe)
		if not realized.error.is_empty():printerr("FAIL: "+realized.error);tracer.release();quit(1);return
		var stone:GemStone=realized.stone
		var job:=GemFrameJob.new();job.stone=stone;job.rig=rig;job.print_style=GemPrint.load_house();job.quality=policy
		var error:=GemJobValidator.validate(job)
		if not error.is_empty():printerr("FAIL: "+error);tracer.release();quit(1);return
		if GemResourceBundle.save(stone,output.path_join("population-%d.res"%count))!=OK:tracer.release();quit(1);return
		var instance:=LapidaryStoneCompiler.compile(stone)
		for pose in 3:
			if not tracer.configure_stone(instance,GemRigCompiler.compile(rig),policy):printerr("FAIL: "+tracer.configuration_error);tracer.release();quit(1);return
			tracer.set_seed(37);tracer.set_clip_sample(Quaternion(Vector3.UP,pose*.22)*Quaternion(Vector3.RIGHT,pose*.1),pose*.35,Vector4.ONE,1.4)
			var start:=Time.get_ticks_usec();tracer.accumulate(128)
			if not tracer.transport_error().is_empty():printerr("FAIL: "+tracer.transport_error());tracer.release();quit(1);return
			var ms:=(Time.get_ticks_usec()-start)/1000.0
			var image:=tracer.finalize_print(GemPrint.load_house())
			if image.save_png(output.path_join("population-%d-pose-%d.png"%[count,pose]))!=OK:tracer.release();quit(1);return
			var small:=GemImagePipeline.resize_display(image,112,112)
			if small.save_png(output.path_join("sprite-%d-pose-%d.png"%[count,pose]))!=OK:tracer.release();quit(1);return
			records.append({"count":count,"pose":pose,"trace_ms":ms,"realization":realized.report})
			print("Population %d pose%d 256px128spp %.1fms"%[count,pose,ms]);await process_frame
	if not GemArtifactStore.atomic_write(output.path_join("report.json"),JSON.stringify({"fixture":population.filling.source_note,"frames":records},"\t",true,true).to_utf8_buffer()):tracer.release();quit(1);return
	tracer.release();quit()
