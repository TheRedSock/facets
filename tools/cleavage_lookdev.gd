extends SceneTree
func _initialize() -> void:
	var stone:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=0
	var recipe:GemCleavageRecipe=load("res://data/lapidary/conditions/diamond_cleavage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	# Declare one of the allowed cubic planes and the actual crystal orientation.
	recipe.normals=PackedVector3Array([Vector3(1,1,1).normalized()])
	stone.crystal_to_stone=Quaternion(recipe.normals[0],Vector3(1,0,.35).normalized())
	recipe.finish.alpha_u=.02
	recipe.finish.alpha_v=.02
	recipe.finish.multiple_scattering=true
	stone.condition.cleavage=recipe
	var tracer:=GemTracer.create(384,384)
	if tracer==null:quit(1);return
	var lighting:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["max_bounces"]=256
	policy["birefringence"]=false
	policy["spectral_geometry"]="full"
	var out:="res://artifacts/cleavage/lookdev"
	DirAccess.make_dir_recursive_absolute(out)
	var sheet:=Image.create(1152,1152,false,Image.FORMAT_RGBA8)
	var reports:=[]
	for column in 3:
		recipe.depth_mm=[0.0,.4,1.2][column]
		for row in 3:
			var compiled:=LapidaryStoneCompiler.compile(stone)
			if not tracer.configure_stone(compiled,lighting,policy):printerr("FAIL: "+tracer.configuration_error);quit(1);return
			tracer.set_clip_sample(Quaternion(Vector3.UP,[0.0,-.5,-.25][row]),[0.0,0.0,.8][row],Vector4.ONE,1.2)
			var ms:=tracer.accumulate(128)
			if not tracer.transport_error().is_empty():printerr("FAIL: "+tracer.transport_error());quit(1);return
			var image:=tracer.finalize_print(GemPrint.load_house())
			image.save_png(out.path_join("depth_%d_pose_%d.png" % [column,row]))
			sheet.blit_rect(image,Rect2i(0,0,384,384),Vector2i(column*384,row*384))
			var report:={"depth_mm":recipe.depth_mm,"pose":row,"trace_ms":ms,"condition":compiled.get("condition_report",{})}
			reports.append(report)
			print(JSON.stringify(report))
	tracer.release()
	sheet.save_png(out.path_join("comparison.png"))
	GemArtifactStore.atomic_write(out.path_join("report.json"),JSON.stringify({"results":reports,"engine":GemRenderIdentity.pipeline_digest("scalar"),"samples":128,"resolution":384},"\t").to_utf8_buffer())
	quit()
