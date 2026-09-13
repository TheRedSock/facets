extends SceneTree
## Spectral out-of-gamut, neutral, coverage and offline/live print equivalence.
const OUT := "res://artifacts/print-acceptance"
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + message)
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var values := PackedFloat32Array()
	var records := []
	for row in 8:
		for i in 401:
			var xyz := GemStandardSpectra.xyz(380+i)
			xyz /= maxf(xyz.x, maxf(xyz.y, xyz.z))
			if row >= 4: xyz = Vector3(.95047,1,1.08883) * pow(10.0, -4.0+6.0*i/400.0)
			var coverage: float = [1.0,.25,.0,.75][row%4]
			values.append_array([xyz.x*coverage,xyz.y*coverage,xyz.z*coverage,coverage])
			if row%4 == 0: records.append({"xyz":[xyz.x,xyz.y,xyz.z],"spectral":row<4})
	var master := Image.create_from_data(401,8,false,Image.FORMAT_RGBAF,values.to_byte_array())
	var live := GemTracer.create(401,8)
	var offline := GemTracer.create(401,8,true)
	if live == null or offline == null: check(false,"No GPU"); _finish(); return
	var encoded := GemArtifactStore.encode_linear(master)
	check(live.load_linear_master(master),"Live master load")
	check(offline.load_linear_master(GemArtifactStore.decode_linear(encoded)),"Compressed offline master load")
	var print_style := GemPrint.load_house().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemPrint
	print_style.highlight_desat=0;print_style.chroma_ceiling=10;print_style.contrast=1
	for view in [GemPrint.View.HOUSE_PRINT,GemPrint.View.DISPLAY_PREVIEW]:
		var a := live.finalize_print(print_style,view)
		var b := offline.finalize_print(print_style,view)
		check(a.get_data()==b.get_data(),"Offline/live byte parity view %d"%view)
		for x in 401:
			for base in [0,4]:
				var opaque := a.get_pixel(x,base)
				for row in [1,3]:
					var partial := a.get_pixel(x,base+row)
					check(Vector3(opaque.r,opaque.g,opaque.b)==Vector3(partial.r,partial.g,partial.b),"Straight coverage-independent RGB")
				check(a.get_pixel(x,base+2)==Color(0,0,0,0),"Transparent pixels zero")
		check(a.save_png(OUT.path_join("view-%d.png"%view))==OK,"Save spectral test image")
	check(live.read_linear_master().get_data()==master.get_data(),"Display does not mutate linear XYZ")
	var matrix: Basis=live.get("_xyz_to_rgb")
	var report := {"inputs":records,"xyz_to_rgb_columns":[[matrix.x.x,matrix.x.y,matrix.x.z],[matrix.y.x,matrix.y.y,matrix.y.z],[matrix.z.x,matrix.z.y,matrix.z.z]],"print_engine":GemRenderIdentity.pipeline_digest("print")}
	check(GemArtifactStore.atomic_write(OUT.path_join("inputs.json"),JSON.stringify(report,"\t").to_utf8_buffer()),"Save color inputs")
	live.release();offline.release()
	var worker := GemFrameWorker.new(OUT.path_join("store-%d"%Time.get_ticks_usec()))
	var job := GemFramePlan.animation(load("res://data/lapidary/stones/ruby.tres"),load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.PREVIEW)[0]
	job.resolution=Vector2i(32,32);job.output_size=Vector2i(32,32);job.samples=8
	check(worker.run(job).get("status")=="complete","House factory build")
	var master_key := GemFramePlan.master_key(job)
	job.display_view=GemPrint.View.DISPLAY_PREVIEW
	check(GemFramePlan.master_key(job)==master_key,"View is not optical identity")
	check(worker.run(job).get("status")=="complete","Preview factory reprint")
	check(worker.counters.rendered==1 and worker.counters.reprinted==1,"View change only reprints retained master")
	worker.release();_finish()
func _finish() -> void:
	print("Print GPU failures: ",failures)
	print("CHECK_COMPLETE: print_gpu_check");quit(1 if failures else 0)
