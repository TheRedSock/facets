extends SceneTree
## Isotropic control isolates geometry across admitted transport backends.
## Beauty is not forced equal across scalar and polarization-aware models.
func _initialize()->void:
	var output := "res://artifacts/facet-program-gpu/%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(output)
	var worker := GemFrameWorker.new(output.path_join("store"))
	var report := []
	for name in ["pointed_flat","independent_pavilion","mixed_rows","custom_girdle"]:
		var stone:GemStone=load("res://data/lapidary/cut_examples/"+name+".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material=GemMaterial.new();stone.material.species=GemSpecies.new()
		stone.material.species.species_id=&"isotropic_control"
		stone.material.species.ordinary.index_offset=0.5
		if name=="pointed_flat": stone.condition.workmanship.polar_error_deg=0.1;stone.condition.workmanship.inward_offset_mm=0.001
		var geometry:PackedByteArray=PackedByteArray()
		var compiled:=LapidaryStoneCompiler.compile_geometry(stone)
		for backend in ["scalar","polarized","crystal"]:
			var job:=GemFrameJob.new();job.stone=stone
			job.rig=load("res://data/lapidary/rigs/gameplay_studio.tres");job.print_style=GemPrint.load_house()
			job.resolution=Vector2i(32,32);job.output_size=job.resolution;job.samples=8
			job.orientation=Quaternion(Vector3.RIGHT,deg_to_rad(-18))
			job.quality=GemRung.policy(GemRung.REFERENCE)
			job.quality.polarization=backend=="polarized";job.quality.crystal_transport=backend=="crystal"
			var start:=Time.get_ticks_msec()
			var result:=worker.run(job)
			if result.get("status")!="complete":worker.release();_fail(name+"/"+backend+": "+str(result));return
			var image:=GemFrameWorker._display_image(worker.store.read(GemFramePlan.display_key(job)),job,GemFramePlan.display_engine(job))
			if image==null or image.get_pixel(16,16).a<0.5:worker.release();_fail("Missing visible body");return
			var aov:=worker.tracer.geometry_aov(2)
			if aov==null or GemGeometryAov.decode(aov.encode())==null:worker.release();_fail("Invalid primary geometry payload");return
			if backend=="scalar":geometry=aov.data
			elif aov.data!=geometry:worker.release();_fail("Backend changed primary geometry: "+name+"/"+backend);return
			var count:=0
			for y in aov.height:
				for x in aov.width:
					var pixel:=aov.record(x,y)
					if pixel.coverage>0:
						count+=1
						if pixel.facet not in compiled.facet_ids:worker.release();_fail("Stable facet ID was lost in GPU packing");return
			var image_path:=output.path_join(name+"-"+backend+".png")
			if image.save_png(image_path)!=OK:worker.release();_fail("Cannot save gate image");return
			report.append({"specimen":name,"backend":backend,"covered_pixels":count,"wall_ms":Time.get_ticks_msec()-start,"png_sha256":FileAccess.get_sha256(image_path)})
	worker.release()
	if not GemArtifactStore.atomic_write(output.path_join("report.json"),JSON.stringify({"results":report,"status":"passed","geometry":"byte-identical primary records across all three backends"},"\t").to_utf8_buffer()):_fail("Cannot save report");return
	print("Facet program GPU PASS: 4 specimens, 3 backends, exact primary geometry/IDs; "+output)
	print("CHECK_COMPLETE: facet_program_gpu_check");quit()

func _fail(message:String)->void:
	printerr("FAIL: "+message);print("CHECK_COMPLETE: facet_program_gpu_check");quit(1)
