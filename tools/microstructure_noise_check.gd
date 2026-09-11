extends SceneTree
## Two-stream delivered-noise study; not an unbiasedness or temporal-coherence
## proof. Fixed physical population, pose and light; only transport seeds vary.
func _initialize()->void:
	var source:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	source.condition=GemCondition.new();source.material.scatter_per_mm=0
	var recipe:GemMicrostructureRecipe=load("res://data/lapidary/microstructures/diagnostic_crystal_layer.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	recipe.populations[0].count=18
	var realized:=GemMicrostructureCompiler.realize(source,recipe)
	if not realized.error.is_empty():printerr("FAIL: "+realized.error);quit(1);return
	var out:="res://artifacts/microstructure/noise"
	DirAccess.make_dir_recursive_absolute(out)
	var tracer:=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	var instance:=LapidaryStoneCompiler.compile(realized.stone)
	var lighting:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var images:={};var times:={}
	for seed_value in [37,91]:
		if not tracer.configure_stone(instance,lighting,GemRung.policy(GemRung.PREVIEW)):printerr("FAIL: "+tracer.configuration_error);tracer.release();quit(1);return
		tracer.set_seed(seed_value);tracer.set_clip_sample(Quaternion(Vector3.UP,.44)*Quaternion(Vector3.RIGHT,.2),.7,Vector4.ONE,1.4)
		var elapsed:=0.0
		for samples in [64,128,512]:
			elapsed+=tracer.accumulate(samples-tracer.samples_accumulated)
			if not tracer.transport_error().is_empty():printerr("FAIL: "+tracer.transport_error());tracer.release();quit(1);return
			var image:=tracer.finalize_print(GemPrint.load_house())
			for size in [256,112]:
				var frame:Image=image if size==256 else GemImagePipeline.resize_display(image,size,size)
				var key:="%d-%d"%[samples,size]
				if not images.has(key):images[key]=[]
				images[key].append(frame)
				if frame.save_png(out.path_join("%s-seed-%d.png"%[key,seed_value]))!=OK:tracer.release();quit(1);return
			if not times.has(samples):times[samples]=[]
			times[samples].append(elapsed)
	tracer.release()
	var metrics:={}
	for key in images:
		metrics[key]=stats(images[key][0],images[key][1])
		print("Population noise "+key+": "+JSON.stringify(metrics[key]))
	var report:={"seeds":[37,91],"members":18,"trace_ms":times,"metrics":metrics,"limits":"Opaque-pixel two-seed print-space noise only. Differences include sampling and quantization; no claim of unbiasedness, invisibility or natural-inclusion calibration."}
	if not GemArtifactStore.atomic_write(out.path_join("report.json"),JSON.stringify(report,"\t",true,true).to_utf8_buffer()):quit(1);return
	quit()

static func stats(a:Image,b:Image)->Dictionary:
	var squared:=0.0;var differences:Array[float]=[];var peak:=0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
			if minf(ca.a,cb.a)<.999:continue
			var delta:=Vector3(ca.r-cb.r,ca.g-cb.g,ca.b-cb.b)*255
			var maximum:=maxf(absf(delta.x),maxf(absf(delta.y),absf(delta.z)))
			squared+=delta.length_squared()/3;differences.append(maximum);peak=maxf(peak,maximum)
	differences.sort()
	return {"noise_lsb":sqrt(squared/differences.size()/2),"p99_difference_lsb":differences[int(.99*(differences.size()-1))],"peak_difference_lsb":peak,"opaque_pixels":differences.size()}
