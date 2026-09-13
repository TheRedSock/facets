extends SceneTree
const Compiler := preload("res://core/lapidary/cut/cut_compiler.gd")
var failures := 0
var checks := 0
func check(ok:bool,label:String)->void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + label)

func _initialize()->void:
	for name in ["pointed_flat","independent_pavilion","mixed_rows","custom_girdle"]:
		var stone:GemStone=load("res://data/lapidary/cut_examples/"+name+".tres")
		var inspection:=GemCutInspection.inspect(stone)
		check(inspection.error.is_empty(),"admit authored demonstration: "+name)
		if not inspection.error.is_empty():continue
		check(inspection.dimensions_mm.x>0 and inspection.dimensions_mm.y>0 and inspection.dimensions_mm.z>0,"finite physical dimensions")
		var mesh:=GemShapeCompiler.from_hull(inspection.geometry.planes,inspection.geometry.facet_ids)
		check(mesh.validate().is_empty() and mesh.signed_volume()>0,"demonstration converts to a closed oriented mesh")
		var section:=GemCutInspection.section(inspection.geometry,Vector3.BACK,0,stone.size_mm)
		check(section.error.is_empty() and section.points_mm.size()>=3 and section.area_mm2>0,"section crosses the actual convex hull")
		if name=="pointed_flat":
			check(not inspection.facets.any(func(f:Dictionary)->bool:return f.zone==0),"pointed crown has no forced table")
			check(inspection.facets.any(func(f:Dictionary)->bool:return String(f.name).begins_with("bottom/")),"independent flat bottom survives")
		if name=="independent_pavilion":
			check(stone.cut.groups[0].directions.divisions==8 and stone.cut.groups[2].directions.divisions==7,"pavilion indices independent of crown")
		if name=="custom_girdle":
			check(inspection.geometry.outline.size()==stone.shape.outline_points.size(),"custom girdle retains authored edge count")
	var source:GemStone=load("res://data/lapidary/cut_examples/independent_pavilion.tres")
	var original:=Compiler.compile(source.cut,source.shape,17,Vector4(0.1,0.1,0.001,0.001))
	var repeat:=Compiler.compile(source.cut,source.shape,17,Vector4(0.1,0.1,0.001,0.001))
	check(original.planes==repeat.planes and original.facet_ids==repeat.facet_ids,"deterministic independent manufacture channels")
	var nominal:=Compiler.compile(source.cut,source.shape,17)
	var table_id: int = nominal.facet_ids[nominal.facet_names.find("table/0.0")]
	var before_index: int = nominal.facet_ids.find(table_id)
	var after_index: int = original.facet_ids.find(table_id)
	check(after_index>=0 and original.planes.slice(after_index*8,after_index*8+4)!=nominal.planes.slice(before_index*8,before_index*8+4),"termination facets participate in explicit manufacture")
	var altered:GemStone=source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	altered.cut.cut_id=&"renamed_design"
	check(Compiler.compile(altered.cut,altered.shape,17,Vector4(0.1,0.1,0.001,0.001)).planes==original.planes,"cut label does not change manufacture")
	var extra:=GemFacetGroup.new();extra.group_id=&"outside_plane";extra.directions=altered.cut.groups[1].directions
	extra.inclination="0";extra.height="4";extra.scale="0"
	altered.cut.groups.append(extra)
	var pruned:=Compiler.compile(altered.cut,altered.shape,17,Vector4(0.1,0.1,0.001,0.001))
	check(not pruned.has("compilation_error"),"redundant support is diagnosed and pruned")
	check(pruned.planes==original.planes and pruned.facet_ids==original.facet_ids,"adding a pruned facet preserves existing IDs and manufacture")
	check(pruned.diagnostics.any(func(d:Dictionary)->bool:return d.kind=="vanished" and String(d.facet).begins_with("outside_plane/")),"vanished facet named in diagnostics")
	altered=source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	altered.cut.groups[3].meet_groups=PackedStringArray(["missing"])
	check(Compiler.compile(altered.cut,altered.shape,0).get("compilation_error","").contains("earlier named"),"invalid meet reference fails clearly")
	altered.cut.groups[3].meet_groups=PackedStringArray(["table"])
	check(Compiler.compile(altered.cut,altered.shape,0).get("compilation_error","").contains("correctly facing"),"wrong-facing meet fails without default height")
	altered=source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	altered.cut.parameters.unused=1.0
	check(Compiler.template_error(altered.cut).contains("Unused"),"unused scalar knobs are rejected")
	check(GemCutExpression.evaluate("1/2",{},{}).get("value")==0.5,"scalar arithmetic uses real division")
	for text in ["randf()","p.clear()","OS.kill(1)","load(1)","Vector3(1,2,3)"]:
		check(not GemCutExpression.syntax_error(text).is_empty(),"unsupported expression rejected: "+text)
	check(GemCutExpression.evaluate("sqrt(-1)",{},{}).has("error"),"nonfinite expression fails admission")
	check(GemCutExpression.evaluate("meet",{},{}).has("error"),"unbound meet cannot become a hidden zero")
	var polygon:=PackedVector2Array([Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1)])
	check(not Compiler.SilhouetteLib.custom_error(polygon).is_empty(),"concave faceted girdle rejected")
	print("Facet program: %d checks, %d failures" % [checks,failures])
	print("CHECK_COMPLETE: test_facet_program");quit(1 if failures else 0)
