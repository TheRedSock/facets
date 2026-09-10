extends SceneTree
## Same physical recipe through scalar preview and explicit crystal transport.
func _initialize()->void:
	var output:="res://artifacts/materials/lookdev/"
	DirAccess.make_dir_recursive_absolute(output)
	var tracer:=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	var lighting:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var sheet:=Image.create(512,1536,false,Image.FORMAT_RGBA8)
	var report:=[]
	var row:=0
	for id in ["chromium_134ppma","iron_titanium_10ppma","mixed_134cr_5feti_ppma"]:
		var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material=load("res://data/lapidary/materials/measured_corundum/"+id+".tres")
		stone.condition=GemCondition.new();stone.size_mm=8
		stone.shape=GemShape.faceted_outline(&"round")
		for axis_angle in [0.0,PI/2]:
			stone.crystal_to_stone=Quaternion(Vector3.RIGHT,axis_angle)
			var instance:=LapidaryStoneCompiler.compile(stone)
			for crystal in [false,true]:
				var policy:=GemRung.policy(GemRung.REFERENCE)
				policy.crystal_transport=crystal;policy.volume=false;policy.max_bounces=256
				if not tracer.configure_stone(instance,lighting,policy):
					printerr("FAIL: ",tracer.configuration_error);tracer.release();quit(1);return
				tracer.set_stone_orientation(Quaternion(Vector3.UP,.15)*Quaternion(Vector3.RIGHT,-.1))
				tracer.accumulate(32)
				if not tracer.transport_error().is_empty():
					printerr("FAIL: ",tracer.transport_error());tracer.release();quit(1);return
				var image:=tracer.finalize_print(GemPrint.load_house())
				var file:="%s_axis%d_%s.png"%[id,int(rad_to_deg(axis_angle)),"crystal" if crystal else "scalar"]
				image.save_png(output+file)
				sheet.blit_rect(image,Rect2i(0,0,256,256),Vector2i(256 if crystal else 0,row*256))
				report.append({"file":file,"size_mm":8,"samples":32,"axis_angle":axis_angle,"crystal":crystal,"profile":tracer.profile()})
				print(JSON.stringify(report[-1]))
			row+=1
	sheet.save_png(output+"comparison.png")
	GemArtifactStore.atomic_write(output+"report.json",JSON.stringify(report,"\t").to_utf8_buffer())
	tracer.release();quit()
