class_name GemPolygon
extends RefCounted
## Simple CCW polygon admission and triangulation of the encoded binary32 points.
## No welding, recentering, distance epsilon or discarded collinear vertices.
## Ear clipping: https://www.geometrictools.com/Documentation/TriangulationByEarClipping.pdf
## Predicate signs use GemExactPredicates, including its exact fallback.
const MAX_VERTICES := 512
const CACHE_ENTRIES := 16
const CACHE_BYTES := 65536
static var _cache:Dictionary={}
static var _retained_bytes:=0
static var _builds:=0
static var _hits:=0
var points := PackedVector3Array()
var previous := PackedInt32Array()
var following := PackedInt32Array()
var alive := PackedByteArray()
var blockers := PackedByteArray()
var counts := PackedInt32Array()
var count := 0

static func triangulate(outline: PackedVector2Array) -> Dictionary:
	if outline.size()<3 or outline.size()>MAX_VERTICES:
		return {"error":"Polygon requires 3..512 vertices"}
	var key:=GemContentIdentity.digest(outline)
	if _cache.has(key):
		var stored:PackedInt32Array=_cache[key]
		_cache.erase(key);_cache[key]=stored
		_hits+=1
		return {"error":"","indices":stored.duplicate()}
	var worker := GemPolygon.new()
	var result:=worker._triangulate(outline)
	_builds+=1
	if result.error.is_empty():
		var indices:PackedInt32Array=result.indices
		var bytes:=indices.size()*4
		while not _cache.is_empty() and (_cache.size()>=CACHE_ENTRIES or _retained_bytes+bytes>CACHE_BYTES):
			var oldest:String=_cache.keys()[0]
			_retained_bytes-=_cache[oldest].size()*4;_cache.erase(oldest)
		_cache[key]=indices.duplicate();_retained_bytes+=bytes
	return result

static func cache_statistics()->Dictionary:
	return {"builds":_builds,"hits":_hits,"entries":_cache.size(),"retained_bytes":_retained_bytes}

func _triangulate(outline: PackedVector2Array) -> Dictionary:
	count = outline.size()
	if count < 3 or count > MAX_VERTICES:
		return {"error":"Polygon requires 3..512 vertices"}
	for p in outline:
		if not p.is_finite():return {"error":"Polygon coordinates must be finite"}
		points.append(Vector3(p.x,p.y,0))
	for i in count:
		for j in range(i+1,count):
			if points[i] == points[j]:return {"error":"Polygon repeats vertex %d at %d" % [i,j]}
		var p := (i+count-1)%count
		var q := (i+1)%count
		if _turn(p,i,q)==0 and not _between(points[p],points[q],points[i]):
			return {"error":"Polygon doubles back at vertex %d" % i}
		for j in range(i+1,count):
			var r := (j+1)%count
			if j==q or r==i:continue
			if _contact(i,q,j,r):return {"error":"Polygon edges %d and %d touch or cross" % [i,j]}
	# A lexicographic extreme has the polygon's orientation. Unlike a shoelace
	# sum, this sign needs no cancellation-prone area accumulation.
	var extreme := 0
	for i in range(1,count):
		if points[i].x<points[extreme].x or (points[i].x==points[extreme].x and points[i].y<points[extreme].y):extreme=i
	if _turn((extreme+count-1)%count,extreme,(extreme+1)%count)<=0:
		return {"error":"Polygon must enclose positive area in counterclockwise order"}
	previous.resize(count);following.resize(count);alive.resize(count);alive.fill(1)
	counts.resize(count);blockers.resize(count*count);blockers.fill(0)
	for i in count:
		previous[i]=(i+count-1)%count;following[i]=(i+1)%count
	for i in count:_refresh(i)
	var indices := PackedInt32Array()
	for remaining in range(count,3,-1):
		var ear := -1
		for i in count:
			if alive[i] and counts[i]==0:ear=i;break
		if ear<0:return {"error":"Polygon has no nondegenerate ear"}
		var p := previous[ear];var q := following[ear]
		indices.append_array(PackedInt32Array([p,ear,q]))
		alive[ear]=0;following[p]=q;previous[q]=p
		# Removing any point can unblock an unchanged candidate, including a
		# collinear point on its diagonal. Track that dependency explicitly.
		for i in count:
			if alive[i] and blockers[i*count+ear]:
				blockers[i*count+ear]=0;counts[i]-=1
		_refresh(p);_refresh(q)
	var last := PackedInt32Array()
	for i in count:
		if alive[i]:last.append(i)
	if last.size()!=3 or _turn(last[0],last[1],last[2])<=0:
		return {"error":"Polygon leaves a degenerate final triangle"}
	indices.append_array(last)
	return {"error":"","indices":indices}

func _refresh(i:int) -> void:
	var p := previous[i];var q := following[i]
	for j in count:blockers[i*count+j]=0
	counts[i]=-1
	if _turn(p,i,q)<=0:return
	counts[i]=0
	for j in count:
		if not alive[j] or j==p or j==i or j==q:continue
		if _turn(p,i,j)>=0 and _turn(i,q,j)>=0 and _turn(q,p,j)>=0:
			blockers[i*count+j]=1;counts[i]+=1

func _turn(a:int,b:int,c:int) -> int:
	return GemExactPredicates.orient2(points[a],points[b],points[c],0,1)

func _contact(a:int,b:int,c:int,d:int) -> bool:
	var abc:=_turn(a,b,c);var abd:=_turn(a,b,d)
	var cda:=_turn(c,d,a);var cdb:=_turn(c,d,b)
	return (abc*abd<0 and cda*cdb<0) or (abc==0 and _between(points[a],points[b],points[c])) or (abd==0 and _between(points[a],points[b],points[d])) or (cda==0 and _between(points[c],points[d],points[a])) or (cdb==0 and _between(points[c],points[d],points[b]))

static func _between(a:Vector3,b:Vector3,p:Vector3) -> bool:
	return p.x>=minf(a.x,b.x) and p.x<=maxf(a.x,b.x) and p.y>=minf(a.y,b.y) and p.y<=maxf(a.y,b.y)
