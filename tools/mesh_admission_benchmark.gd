extends SceneTree
## CPU authoring admission cost, independent of GPU/rendering time.
func _initialize() -> void:
	var rows := []
	for resolution in [32, 64, 128]:
		var defect := GemDefect.new()
		defect.fracture_profile.resolution = resolution
		defect.orientation = Quaternion(Vector3(1,2,3).normalized(), 0.7)
		defect.center_mm = Vector3(0.4,-0.3,0.2)
		var start := Time.get_ticks_usec()
		var mesh := GemDefectCompiler.compile(defect, 4.0)
		var built := Time.get_ticks_usec()
		var errors := mesh.validate()
		var admitted := Time.get_ticks_usec()
		var cached := mesh.validate()
		var end := Time.get_ticks_usec()
		var rebuilt := GemDefectCompiler.compile(defect, 4.0)
		var rebuilt_start := Time.get_ticks_usec()
		var rebuilt_errors := rebuilt.validate()
		var rebuilt_end := Time.get_ticks_usec()
		if not errors.is_empty() or not cached.is_empty() or not rebuilt_errors.is_empty():
			printerr("FAIL: %s" % errors)
			quit(1)
			return
		var row := {"resolution":resolution,"triangles":mesh.triangle_count(),"build_ms":(built-start)/1000.0,"admission_ms":(admitted-built)/1000.0,"cached_ms":(end-admitted)/1000.0,"rebuilt_cached_ms":(rebuilt_end-rebuilt_start)/1000.0}
		print(JSON.stringify(row))
		rows.append(row)
	GemArtifactStore.atomic_write("res://artifacts/geometry/admission_benchmark.json", JSON.stringify(rows,"\t").to_utf8_buffer())
	quit()
