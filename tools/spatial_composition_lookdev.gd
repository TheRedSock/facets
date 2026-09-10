extends SceneTree
## Columns: homogeneous blend / spatial composition / spatial + authored milk.
## Rows: face-up and tilted views of the same physical color regions.
func _initialize()->void:
	var output:="res://artifacts/materials/spatial-lookdev/"
	DirAccess.make_dir_recursive_absolute(output)
	var tracer:=GemTracer.create(384,384)
	if tracer==null:quit(1);return
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material=load("res://data/lapidary/materials/measured_corundum/clear_host.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.size_mm=8;stone.shape=GemShape.faceted_outline(&"oval")
	var condition:GemCondition=load("res://data/lapidary/conditions/corundum_bicolor.tres")
	var lighting:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var sheet:=Image.create(1152,768,false,Image.FORMAT_RGBA8)
	var report:=[]
	for column in 3:
		stone.condition=condition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material.absorbers.clear()
		stone.material.scatter_per_mm=.15 if column==2 else 0.0
		if column==0:
			for field in stone.condition.volume_fields:
				var term:GemAbsorber=field.absorbers[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
				term.amount*=.5;stone.material.absorbers.append(term)
			stone.condition.volume_fields.clear()
		var instance:=LapidaryStoneCompiler.compile(stone)
		var policy:=GemRung.policy(GemRung.PREVIEW)
		for row in 2:
			if not tracer.configure_stone(instance,lighting,policy):
				printerr(tracer.configuration_error);tracer.release();quit(1);return
			tracer.set_stone_orientation(Quaternion(Vector3.UP,.1+.4*row)*Quaternion(Vector3.RIGHT,-.1))
			tracer.accumulate(128)
			if not tracer.transport_error().is_empty():printerr(tracer.transport_error());tracer.release();quit(1);return
			var image:=tracer.finalize_print(GemPrint.load_house())
			var file:="condition%d_pose%d.png"%[column,row]
			image.save_png(output+file)
			sheet.blit_rect(image,Rect2i(0,0,384,384),Vector2i(column*384,row*384))
			report.append({"file":file,"physical_radius_mm":8,"samples":128,"scatter_per_mm":stone.material.scatter_per_mm,"profile":tracer.profile()})
			print(JSON.stringify(report[-1]))
	sheet.save_png(output+"comparison.png")
	GemArtifactStore.atomic_write(output+"report.json",JSON.stringify(report,"\t").to_utf8_buffer())
	tracer.release();quit()
