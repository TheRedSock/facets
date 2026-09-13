class_name GemCutOverlay
extends Control
## Debug geometry from the admitted compiler, in physical coordinates.
var inspection:Dictionary={}
var _anchors:Array=[]
func show_inspection(value:Dictionary)->void:inspection=value;visible=true;queue_redraw()
func _draw()->void:
	_anchors.clear()
	if inspection.is_empty():return
	var dimensions:Array=inspection.dimensions_mm
	var scale:=minf(size.x*.8/maxf(float(dimensions[0]),.0001),size.y*.28/maxf(maxf(float(dimensions[1]),float(dimensions[2])),.0001))
	var font:=get_theme_default_font()
	draw_string(font,Vector2(12,22),"Manufactured program before rounding/cleavage",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	draw_string(font,Vector2(12,42),"Dimensions mm: %.3f × %.3f × %.3f"%dimensions,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	for view in 2:
		var center:=Vector2(size.x*.5,size.y*(.3 if view==0 else .75))
		draw_string(font,center+Vector2(-size.x*.45,-size.y*.16),"Top / XY section" if view==0 else "Front / XZ section",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("aabbd0"))
		for facet in inspection.facets:
			var points:=PackedVector2Array()
			for point in facet.points:points.append(_project(point,view,center,scale))
			if points.size()<3:continue
			points.append(points[0]);draw_polyline(points,Color(.55,.7,.9,.45),1,true)
			var anchor:=_project(facet.anchor,view,center,scale);draw_circle(anchor,2,Color("fbbf24"))
			_anchors.append({"position":anchor,"text":"%s (ID %d)\nMeets: %s"%[facet.name,facet.id,", ".join(facet.meets)]})
		var section:=PackedVector2Array()
		for point in inspection.sections[view]:section.append(_project(point,view,center,scale))
		if section.size()>2:section.append(section[0]);draw_polyline(section,Color("5fddab"),2,true)
func _get_tooltip(at:Vector2)->String:
	for anchor in _anchors:
		if at.distance_to(anchor.position)<9:return anchor.text
	return "Yellow points are constraint anchors. Hover for facet identity and meets."
static func _project(point:Array,view:int,center:Vector2,scale:float)->Vector2:
	return center+Vector2(float(point[0]),-float(point[1 if view==0 else 2]))*scale
