extends SceneTree
## Contact sheet: rows quartz/emerald/ruby/diamond; columns physical/mild/banded.
## A deliberately illustrative preset; no automatic grading or final art direction.
func _initialize() -> void:
	var root := "res://artifacts/style-lookdev"
	var worker := GemFrameWorker.new(root + "/store")
	var sheet := Image.create_empty(112 * 3, 112 * 4, false, Image.FORMAT_RGBA8)
	var report := []
	var row := 0
	for name in ["quartz", "emerald", "ruby", "diamond"]:
		var job := GemFramePlan.animation(load("res://data/lapidary/stones/" + name + ".tres"), load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.PREVIEW)[0]
		job.output_size = Vector2i(112, 112)
		var start := Time.get_ticks_usec()
		if worker.run(job).is_empty(): worker.release(); quit(1); return
		var render_ms := (Time.get_ticks_usec() - start) / 1000.0
		var original := Image.new()
		if original.load_webp_from_buffer(worker.store.read(GemFramePlan.print_key(job)).payload) != OK:
			worker.release(); quit(1); return
		original.convert(Image.FORMAT_RGBA8)
		var column := 0
		for variant in ["physical", "mild", "banded"]:
			var style: GemStyle = null
			if variant != "physical":
				style = load("res://data/lapidary/styles/illustrative_sprite.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
				if variant == "banded": style.luminance_bands = 8
			start = Time.get_ticks_usec()
			var display := GemStylePipeline.apply(original, style)
			var style_ms := (Time.get_ticks_usec() - start) / 1000.0
			display.save_png(root + "/" + name + "-" + variant + ".png")
			sheet.blit_rect(display, Rect2i(Vector2i.ZERO, display.get_size()), Vector2i(column * 112, row * 112))
			report.append({"stone": name, "variant": variant, "frame_ms": render_ms, "style_ms": style_ms})
			column += 1
		row += 1
	worker.release()
	sheet.save_png(root + "/sheet.png")
	GemArtifactStore.atomic_write(root + "/report.json", JSON.stringify(report, "\t").to_utf8_buffer())
	print(JSON.stringify(report)); quit()
