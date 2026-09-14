class_name WorkSurface
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("141a22"))
	for band in 32:
		var y := size.y*band/32.0
		draw_rect(Rect2(0,y,size.x,size.y/32.0+1),Color(0.08+band*0.0006,0.10+band*0.0008,0.135+band*0.0008))
	for side in [0,1]:
		var x: float = size.x*side
		draw_polyline(PackedVector2Array([Vector2(x,size.y*0.18),Vector2(x+(-1 if side else 1)*70,size.y*0.36),Vector2(x+(-1 if side else 1)*35,size.y*0.7)]),Color(0.30,0.34,0.38,0.14),2.0,true)

static func draw_outlet(canvas: CanvasItem, rect: Rect2, threshold: int) -> void:
	# Presentation fixture only; Open seam does not author an outlet objective.
	canvas.draw_rect(rect.grow(-5),Color("b8b6ac"),false,2)
	canvas.draw_line(rect.get_center(),Vector2(rect.get_center().x,rect.end.y),Color("d9b978"),3)
	canvas.draw_string(ThemeDB.fallback_font,rect.position+Vector2(8,22),"T%d+" % threshold,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f2eadb"))
