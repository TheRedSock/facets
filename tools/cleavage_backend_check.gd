extends SceneTree
var failures:=0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+message)
func _initialize()->void:
	var stone:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=0
	stone.condition.cleavage=load("res://data/lapidary/conditions/diamond_cleavage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var recipe:=stone.condition.cleavage
	recipe.normals=PackedVector3Array([Vector3(1,1,1).normalized()]);recipe.depth_mm=1.2
	stone.crystal_to_stone=Quaternion(recipe.normals[0],Vector3(1,0,.35).normalized())
	recipe.finish.multiple_scattering=true
	var tracer:=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	var lighting:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["max_bounces"]=256;policy["birefringence"]=false;policy["spectral_geometry"]="full"
	var out:="res://artifacts/cleavage/backends"
	DirAccess.make_dir_recursive_absolute(out)
	var sheet:=Image.create(1024,512,false,Image.FORMAT_RGBA8)
	var reports:=[]
	for finish_case in 2:
		recipe.finish.alpha_u=0 if finish_case==0 else .02
		recipe.finish.alpha_v=recipe.finish.alpha_u
		for pose in 2:
			var images:Array[Image]=[]
			var aovs:Array[GemGeometryAov]=[]
			var times:=[]
			var reference:=LapidaryStoneCompiler.compile(stone,false)
			var distance:=GemTracer._boundary_radius(reference)*1.05+.5
			for backend in 2:
				var compiled:=reference if backend==0 else LapidaryStoneCompiler.compile(stone,true)
				check(tracer.configure_stone(compiled,lighting,policy),"backend config")
				tracer._camera_distance=distance # identical orthographic origins for A/B
				tracer.set_seed(81823)
				tracer.set_clip_sample(Quaternion(Vector3.UP,0.0 if pose==0 else -.5),0,Vector4.ONE,1.2)
				tracer.accumulate(8);tracer.reset_accumulation()
				var ms:=tracer.accumulate(128)
				check(tracer.transport_error().is_empty(),"backend completes valid transport")
				var image:=tracer.finalize_print(GemPrint.load_house())
				images.append(image);times.append(ms);aovs.append(tracer.geometry_aov(2))
				image.save_png(out.path_join("finish%d_pose%d_backend%d.png"%[finish_case,pose,backend]))
				sheet.blit_rect(image,Rect2i(0,0,256,256),Vector2i((finish_case*2+backend)*256,pose*256))
			var squared:=0.0;var id_errors:=0;var coverage_errors:=0;var matched:=0;var max_position:=0.0;var max_partial_position:=0.0;var max_normal:=0.0
			for y in 256:
				for x in 256:
					var ca:=images[0].get_pixel(x,y);var cb:=images[1].get_pixel(x,y)
					var delta:=Vector3(ca.r,ca.g,ca.b)*ca.a-Vector3(cb.r,cb.g,cb.b)*cb.a
					squared+=delta.length_squared()
					var a:=aovs[0].record(x,y);var b:=aovs[1].record(x,y)
					if a.coverage!=b.coverage:coverage_errors+=1
					if a.coverage>0 and b.coverage>0:
						if a.facet!=b.facet or a.region!=b.region or a.material!=b.material:id_errors+=1
						else:
							matched+=1
							if a.coverage==1 and b.coverage==1:
								max_position=maxf(max_position,a.position_mm.distance_to(b.position_mm))
							else:
								max_partial_position=maxf(max_partial_position,a.position_mm.distance_to(b.position_mm))
							max_normal=maxf(max_normal,a.normal_object.distance_to(b.normal_object))
			var report:={"roughness":recipe.finish.alpha_u,"pose":pose,"reference_ms":times[0],"planes_ms":times[1],"speedup":times[0]/times[1],"composite_rmse_lsb":255*sqrt(squared/(256*256*3)),"id_errors":id_errors,"coverage_errors":coverage_errors,"matched_pixels":matched,"max_full_coverage_position_mm":max_position,"max_partial_coverage_position_mm":max_partial_position,"max_normal_error":max_normal}
			reports.append(report);print(JSON.stringify(report))
			check(id_errors<8 and coverage_errors<8 and max_position<.0001 and max_normal<.0001,"backend physical geometry agreement")
			check(report.composite_rmse_lsb<.5,"backend print difference below half a display level RMS")
	tracer.release()
	sheet.save_png(out.path_join("comparison.png"))
	GemArtifactStore.atomic_write(out.path_join("report.json"),JSON.stringify({"cases":reports,"engine":GemRenderIdentity.pipeline_digest("scalar"),"spp":128,"resolution":256},"\t").to_utf8_buffer())
	quit(1 if failures else 0)
