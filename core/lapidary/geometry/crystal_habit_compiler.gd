class_name GemCrystalHabitCompiler
extends RefCounted
## Bounded template cache. Instance transforms never mutate cached geometry.
static var _cache:Dictionary={}
static var _order:Array[String]=[]

static func compile(habit:GemCrystalHabit)->GemMesh:
	if habit==null or not habit.validate().is_empty():return GemMesh.new()
	var key:=GemContentIdentity.digest(habit.faces)
	if not _cache.has(key):
		var scale:=0.0
		for face in habit.faces:scale=maxf(scale,face.d)
		var planes:=PackedFloat32Array()
		for face in habit.faces:
			planes.append_array(PackedFloat32Array([face.normal.x,face.normal.y,face.normal.z,face.d/scale,0,0,0,0]))
		var mesh:=GemShapeCompiler.from_hull(planes)
		for i in mesh.vertices.size():mesh.vertices[i]*=scale
		if not mesh.validate().is_empty():return GemMesh.new()
		_cache[key]=mesh
		if _order.size()==16:_cache.erase(_order.pop_front())
	else:_order.erase(key)
	_order.append(key)
	var result:=GemMesh.new();result.append_region(_cache[key],0)
	return result
