extends SceneTree
## A finish region anchored to the generated table plane; no random marks.
func _initialize() -> void:
	var stone: GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=0
	stone.condition.banding.contrast=0
	var clean:=LapidaryStoneCompiler.compile(stone)
	var planes: PackedFloat32Array=clean.planes
	var height:=NAN
	for i in planes.size()/8:
		if planes[i*8+2]>0.9999: height=planes[i*8+3]*stone.size_mm; break
	if not is_finite(height): printerr("FAIL: specimen has no table plane"); quit(1); return
	var field:=GemFinishField.new()
	field.center_mm=Vector3(0,0,height)
	field.radius_mm=Vector3(stone.size_mm*100,stone.size_mm*100,0.01)
	field.direction=Vector3(1,0.5,0)
	var finish:=stone.condition.finish
	finish.multiple_scattering=true
	var tracer:=GemTracer.create(256,256)
	if tracer==null: quit(1); return
	var lights:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["max_bounces"]=256
	policy["birefringence"]=false
	policy["spectral_geometry"]="full"
	var sheet:=Image.create(768,512,false,Image.FORMAT_RGBA8)
	var reports:=[]
	var out:="res://artifacts/finish-fields/lookdev"
	DirAccess.make_dir_recursive_absolute(out)
	for column in 3:
		finish.alpha_u=0.04 if column==2 else 0.0
		finish.alpha_v=finish.alpha_u
		finish.fields.clear()
		if column>0:
			field.alpha_u=0.15 if column==1 else 0.0
			field.alpha_v=0.03 if column==1 else 0.0
			finish.fields.append(field)
		for row in 2:
			if not tracer.configure_stone(LapidaryStoneCompiler.compile(stone),lights,policy): printerr(tracer.configuration_error); quit(1); return
			tracer.set_stone_orientation(Quaternion(Vector3.UP,0.0 if row==0 else 0.35)*Quaternion(Vector3.RIGHT,-0.15))
			var ms:=tracer.accumulate(128)
			var image:=tracer.finalize_print(GemPrint.load_house())
			if not tracer.transport_error().is_empty(): printerr("FAIL: "+tracer.transport_error()); quit(1); return
			image.save_png(out.path_join("finish_%d_pose_%d.png" % [column,row]))
			sheet.blit_rect(image,Rect2i(0,0,256,256),Vector2i(column*256,row*256))
			var report:={"case":column,"pose":row,"trace_ms":ms,"diagnostics":tracer.surface_diagnostics()}
			reports.append(report)
			print(JSON.stringify(report))
	tracer.release()
	sheet.save_png(out.path_join("comparison.png"))
	GemArtifactStore.atomic_write(out.path_join("report.json"),JSON.stringify({"results":reports,"engine":GemRenderIdentity.pipeline_digest("scalar"),"table_height_mm":height,"samples":128,"resolution":256},"\t").to_utf8_buffer())
	quit()
