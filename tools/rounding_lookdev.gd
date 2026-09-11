extends SceneTree
## Physical rounding only: sharp, 30um, 120um. No grade-to-damage mapping.
func _initialize()->void:
	var continuous:=OS.get_cmdline_user_args().has("--continuous")
	var macro:=OS.get_cmdline_user_args().has("--macro")
	var fine:=OS.get_cmdline_user_args().has("--fine")
	var output:="res://artifacts/rounding/macro/" if macro else "res://artifacts/rounding/lookdev/"
	if fine:output=output.trim_suffix("/")+"-fine/"
	if continuous:output=output.trim_suffix("/")+"-continuous/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	var tracer:=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.size_mm=4;stone.material.scatter_per_mm=0
	stone.condition.rounding=GemRounding.new();stone.condition.rounding.angular_step_deg=3 if fine else 6
	var rig:GemLightRig=load("res://data/lapidary/rigs/gameplay_studio.tres")
	var sheet:=Image.create(768,512,false,Image.FORMAT_RGBA8)
	var reports:=[]
	for column in 3:
		stone.condition.rounding.radius_mm=([0.0,.12,.6] if macro else [0.0,.03,.12])[column]
		var start:=Time.get_ticks_usec()
		var requested_radius:=stone.condition.rounding.radius_mm
		if continuous:stone.condition.rounding.radius_mm=0
		var instance:=LapidaryStoneCompiler.compile(stone)
		stone.condition.rounding.radius_mm=requested_radius
		if continuous and requested_radius>0:
			var solid:=GemRoundedSolid.compile(instance.planes,instance.facet_ids,stone.size_mm,stone.condition.rounding)
			if not solid.error.is_empty():printerr(solid.error);tracer.release();quit(1);return
			instance["rounded_solid"]=solid;instance["planes"]=PackedFloat32Array()
			instance["condition_report"]={"rounding":solid.report}
		var compile_ms:=(Time.get_ticks_usec()-start)/1000.0
		if instance.has("compilation_error"):printerr(instance.compilation_error);tracer.release();quit(1);return
		for row in 2:
			var configure_start:=Time.get_ticks_usec()
			if not tracer.configure_stone(instance,GemRigCompiler.compile(rig),GemRung.policy(GemRung.PREVIEW)):
				printerr(tracer.configuration_error);tracer.release();quit(1);return
			var configure_ms:=(Time.get_ticks_usec()-configure_start)/1000.0
			tracer.set_stone_orientation(Quaternion(Vector3.UP,.1+.4*row)*Quaternion(Vector3.RIGHT,-.1))
			tracer.accumulate(128)
			if not tracer.transport_error().is_empty():printerr(tracer.transport_error());tracer.release();quit(1);return
			var image:=tracer.finalize_print(GemPrint.load_house())
			var file:="radius%d_pose%d.png"%[column,row]
			image.save_png(output+file);sheet.blit_rect(image,Rect2i(0,0,256,256),Vector2i(column*256,row*256))
			reports.append({"file":file,"compile_ms":compile_ms,"configure_upload_ms":configure_ms,"radius_mm":stone.condition.rounding.radius_mm,"condition":instance.get("condition_report",{}),"profile":tracer.profile()})
			print(JSON.stringify(reports[-1]))
	sheet.save_png(output+"comparison.png")
	GemArtifactStore.atomic_write(output+"report.json",JSON.stringify(reports,"\t").to_utf8_buffer())
	tracer.release();quit()
