extends SceneTree
## Headless facet/meet overlay and sections from the actual compiled program.
## --stone=res://... --output=res://artifacts/cut-inspection
func _initialize() -> void:
	var options := {"stone": "res://data/lapidary/cut_examples/pointed_flat.tres", "output": "res://artifacts/cut-inspection"}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2 or not options.has(pair[0]): _fail("Unknown or missing option: " + argument); return
		options[pair[0]] = pair[1]
	if not ResourceLoader.exists(options.stone): _fail("Specimen resource does not exist"); return
	var stone := ResourceLoader.load(options.stone, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GemStone
	var result := GemCutInspection.inspect(stone)
	if not result.error.is_empty(): _fail(result.error); return
	var horizontal := GemCutInspection.section(result.geometry, Vector3.BACK, 0, stone.size_mm)
	var vertical := GemCutInspection.section(result.geometry, Vector3.UP, 0, stone.size_mm)
	if not horizontal.error.is_empty() or not vertical.error.is_empty(): _fail("Section computation failed"); return
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 1200 760"><rect width="1200" height="760" fill="#111827"/><g font-family="sans-serif" fill="#e5e7eb"><text x="30" y="35" font-size="22">%s — facet program inspection</text>' % String(stone.stone_id).xml_escape()
	svg += '<text x="30" y="65" font-size="15">Dimensions %.4f × %.4f × %.4f mm; unit radius scale %.4f mm; %d surviving facets</text>' % [result.dimensions_mm.x, result.dimensions_mm.y, result.dimensions_mm.z, stone.size_mm, result.facets.size()]
	svg += '<text x="30" y="90" font-size="13">Manufactured facet program before rounding/cleavage. Dots are constraint anchors; hover faces for stable IDs.</text>'
	var scale := 285.0 / maxf(result.dimensions_mm.x, maxf(result.dimensions_mm.y, result.dimensions_mm.z))
	var center: Vector3 = (result.bounds_min_mm + result.bounds_max_mm) * 0.5
	for view in 2:
		var origin := Vector2(210 + view*390, 330)
		svg += '<text x="%d" y="130" font-size="18">%s</text>' % [int(origin.x-120), "Top: XY" if view==0 else "Front: XZ"]
		for facet: Dictionary in result.facets:
			var facing: float = facet.normal.z if view == 0 else -facet.normal.y
			if facing <= 1e-6: continue
			var points := _points(facet.points_mm, origin, scale, center, view)
			svg += '<polygon points="%s" fill="hsl(%d,55%%,45%%)" fill-opacity="0.4" stroke="#d1d5db" stroke-width="0.7"><title>%s; ID %d</title></polygon>' % [points, facet.zone*43, String(facet.name).xml_escape(), facet.id]
			var at := _project(facet.anchor_mm, origin, scale, center, view)
			svg += '<circle cx="%.3f" cy="%.3f" r="2" fill="#fbbf24"><title>Constraint anchor: %s; meets %s</title></circle>' % [at.x, at.y, String(facet.name).xml_escape(), ", ".join(facet.meet_contacts).xml_escape()]
	var section_origin := Vector2(990, 290)
	svg += '<text x="870" y="130" font-size="18">Sections through origin</text>'
	svg += '<polygon points="%s" fill="none" stroke="#60a5fa" stroke-width="2"/>' % _points(horizontal.points_mm, section_origin, scale, center, 0)
	svg += '<polygon points="%s" fill="none" stroke="#f472b6" stroke-width="2"/>' % _points(vertical.points_mm, Vector2(990,520), scale, center, 1)
	svg += '<text x="820" y="695" font-size="14">XY %.5f mm²; XZ %.5f mm²</text>' % [horizontal.area_mm2, vertical.area_mm2]
	svg += '<text x="30" y="720" font-size="14">%d pruning/coincidence diagnostics. Facet names, IDs, anchors and measures are saved in report.json.</text></g></svg>' % result.geometry.diagnostics.size()
	var faces := []
	for facet: Dictionary in result.facets:
		var vertices := []
		for point in facet.points_mm: vertices.append([point.x,point.y,point.z])
		faces.append({"name":facet.name,"id":facet.id,"vertices_mm":vertices,"anchor_mm":[facet.anchor_mm.x,facet.anchor_mm.y,facet.anchor_mm.z],"meet_contacts":facet.meet_contacts})
	var report := {"specimen":stone.fingerprint(),"dimensions_mm":[result.dimensions_mm.x,result.dimensions_mm.y,result.dimensions_mm.z],
		"stage":"manufactured facet program before rounding/cleavage","facets":faces,"diagnostics":result.geometry.diagnostics,
		"program_measures":result.geometry.program_measures,"sections_mm2":{"xy":horizontal.area_mm2,"xz":vertical.area_mm2}}
	var output: String = options.output
	if DirAccess.make_dir_recursive_absolute(output) != OK or not GemArtifactStore.atomic_write(output.path_join("overlay.svg"),svg.to_utf8_buffer()) or not GemArtifactStore.atomic_write(output.path_join("report.json"),JSON.stringify(report,"\t").to_utf8_buffer()):
		_fail("Cannot save cut inspection"); return
	print("Cut inspection: " + output)
	print("CHECK_COMPLETE: inspect_cut"); quit()

func _project(point:Vector3,origin:Vector2,scale:float,center:Vector3,view:int)->Vector2:
	var p := point-center
	return origin + Vector2(p.x, -p.y if view==0 else -p.z)*scale

func _points(points:PackedVector3Array,origin:Vector2,scale:float,center:Vector3,view:int)->String:
	var parts := PackedStringArray()
	for point in points:
		var p := _project(point,origin,scale,center,view)
		parts.append("%.4f,%.4f" % [p.x,p.y])
	return " ".join(parts)

func _fail(message:String)->void:
	printerr("FAIL: " + message); print("CHECK_COMPLETE: inspect_cut"); quit(1)
