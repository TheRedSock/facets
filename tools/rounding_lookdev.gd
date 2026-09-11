extends SceneTree
## Physical rounding only: sharp, 30um, 120um. No grade-to-damage mapping.
func _initialize()->void:
	var continuous:=not OS.get_cmdline_user_args().has("--mesh-reference")
	var macro:=OS.get_cmdline_user_args().has("--macro")
	var fine:=OS.get_cmdline_user_args().has("--fine")
	var conditions:=OS.get_cmdline_user_args().has("--conditions")
	var output:="res://artifacts/rounding/macro-authored/" if macro else "res://artifacts/rounding/authored/"
	if conditions:output="res://artifacts/rounding/conditions/"
	if fine:output=output.trim_suffix("/")+"-fine/"
	if not continuous:output=output.trim_suffix("/")+"-mesh/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(output)
	var tracer:=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.size_mm=4;stone.material.scatter_per_mm=0
	stone.condition.rounding=GemRounding.new()
	var rig:GemLightRig=load("res://data/lapidary/rigs/gameplay_studio.tres")
	var sheet:=Image.create(1024 if conditions else 768,512,false,Image.FORMAT_RGBA8)
	var reports:=[]
	for column in (4 if conditions else 3):
		stone.condition.defects.clear();stone.condition.cleavage=null
		stone.condition.rounding.radius_mm=([0.0,.12,.12,.12] if conditions else ([0.0,.12,.6] if macro else [0.0,.03,.12]))[column]
		if conditions and column==2:
			var host:=LapidaryStoneCompiler.compile(stone)
			var chip:=GemDefectCompiler.edge_chip(host,stone.size_mm,51,.5,.2)
			if chip==null:printerr("FAIL: rounded junction chip placement");tracer.release();quit(1);return
			stone.condition.defects.append(chip)
		if conditions and column==3:
			# Geometric plane separation only: quartz has no declared cleavage here.
			# The explicit authored plane is a diagnostic, not mineral cleavage evidence.
			var separation:=GemCleavageRecipe.new()
			separation.normals=PackedVector3Array([Vector3(1,0,.35).normalized()])
			separation.depth_mm=.4
			separation.source_note="Explicit diagnostic plane separation on rounded quartz; not a natural cleavage claim."
			stone.condition.cleavage=separation
		var start:=Time.get_ticks_usec()
		var instance:=LapidaryStoneCompiler.compile(stone)
		if not continuous and instance.has("rounded_solid"):
			var reference:Dictionary=instance.rounded_solid.reference_mesh(3 if fine else 6)
			if not reference.error.is_empty():printerr(reference.error);tracer.release();quit(1);return
			instance["mesh"]=reference.mesh;instance.erase("rounded_solid")
			instance.condition_report.rounding["mesh_reference_step_deg"]=3 if fine else 6
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
			reports.append({"file":file,"compile_ms":compile_ms,"configure_upload_ms":configure_ms,"radius_mm":stone.condition.rounding.radius_mm,"variant":(["sharp","rounded","rounded_chip","rounded_plane_separation"][column] if conditions else "radius_sweep"),"condition":instance.get("condition_report",{}),"profile":tracer.profile()})
			print(JSON.stringify(reports[-1]))
	sheet.save_png(output+"comparison.png")
	GemArtifactStore.atomic_write(output+"report.json",JSON.stringify(reports,"\t").to_utf8_buffer())
	tracer.release();quit()
