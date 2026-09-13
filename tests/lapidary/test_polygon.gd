extends SceneTree
var checks:=0
var failures:=0
var corpus:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func verify(points:PackedVector2Array,label:String,solid:=false)->void:
	var result:=GemPolygon.triangulate(points)
	check(result.error.is_empty(),label+": "+result.error)
	if not result.error.is_empty():return
	var cap:PackedInt32Array=result.indices
	check(cap.size()==3*(points.size()-2),label+" triangle count")
	var edges:={}
	var positive:=true
	for t in cap.size()/3:
		var a:=points[cap[t*3]];var b:=points[cap[t*3+1]];var c:=points[cap[t*3+2]]
		positive=positive and GemExactPredicates.orient2(Vector3(a.x,a.y,0),Vector3(b.x,b.y,0),Vector3(c.x,c.y,0),0,1)>0
		for k in 3:
			var u:=cap[t*3+k];var v:=cap[t*3+(k+1)%3]
			var key:=Vector2i(mini(u,v),maxi(u,v))
			if not edges.has(key):edges[key]=[]
			edges[key].append(Vector2i(u,v))
	check(positive,label+" nondegenerate CCW triangles")
	var closed:=true
	for key:Vector2i in edges:
		var boundary:=(key.y==key.x+1 or (key.x==0 and key.y==points.size()-1))
		var uses:Array=edges[key]
		if boundary:
			closed=closed and uses.size()==1 and uses[0].y==(uses[0].x+1)%points.size()
		else:
			closed=closed and uses.size()==2 and uses[0]==Vector2i(uses[1].y,uses[1].x)
	for i in points.size():
		var j:=(i+1)%points.size()
		closed=closed and edges.has(Vector2i(mini(i,j),maxi(i,j)))
	check(closed,label+" preserves every boundary segment with paired internal edges")
	check(GemPolygon.triangulate(points).indices==cap,label+" deterministic triangulation")
	var encoded:=[]
	for p in points:encoded.append([p.x,p.y])
	corpus.append({"label":label,"points":encoded,"indices":Array(cap)})
	if solid:
		var mesh:=GemShapeCompiler.loft(points,PackedVector2Array([Vector2(-1,1),Vector2(1,1)]))
		check(mesh.validate().is_empty(),label+" closed admitted loft: "+str(mesh.validate()))

func reject(points:PackedVector2Array,label:String)->void:
	check(not GemPolygon.triangulate(points).error.is_empty(),label)
	check(GemShapeCompiler.loft(points,PackedVector2Array([Vector2(-1,1),Vector2(1,1)])).vertices.is_empty(),label+" no partial mesh")

func _initialize()->void:
	var square:=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])
	for shift in [0.0,100.0,10000.0,1000000.0]:
		var moved:=PackedVector2Array()
		for p in square:moved.append(p+Vector2(shift,shift))
		verify(moved,"translated square "+str(shift),true)
		check(GemShapeCompiler.loft(moved,PackedVector2Array([Vector2(-1,1),Vector2(1,1)])).signed_volume()==8,"translated extrusion volume")
	var comb:=PackedVector2Array([Vector2(-1,0),Vector2(26,0),Vector2(26,4)])
	for i in range(12,-1,-1):comb.append_array(PackedVector2Array([Vector2(2*i+1,4),Vector2(2*i+1,1),Vector2(2*i,1),Vector2(2*i,4)]))
	comb.append(Vector2(-1,4))
	verify(comb,"concave comb",true)
	for start in comb.size():
		var rotated:=PackedVector2Array()
		for i in comb.size():rotated.append(comb[(i+start)%comb.size()])
		verify(rotated,"cyclic comb %d"%start)
	var subdivided:=PackedVector2Array()
	for side in 4:
		for k in 32:subdivided.append(square[side].lerp(square[(side+1)%4],k/32.0))
	verify(subdivided,"128 retained collinear boundary vertices",true)
	var thin:=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(2,1e-20),Vector2(2,1),Vector2(0,1)])
	verify(thin,"almost collinear positive ear",true)
	for scale in [1e-15,1e-7,1.0,1e7,1e15]:
		var scaled:=PackedVector2Array()
		for p in thin:scaled.append(p*scale)
		verify(scaled,"encoded scale "+str(scale))
	for size in [7,16,31,64,128,512]:
		var star:=PackedVector2Array()
		for i in size:
			var angle:float=TAU*i/size
			var radius:=1.0 if i%2==0 else .25
			star.append(Vector2(cos(angle),sin(angle))*radius)
		var begin:=Time.get_ticks_usec()
		verify(star,"radial star %d"%size,size<=64)
		print("Polygon %d vertices: %.3f ms including repeated checks"%[size,(Time.get_ticks_usec()-begin)/1000.0])
	var backwards:=square.duplicate();backwards.reverse();reject(backwards,"clockwise outline")
	reject(PackedVector2Array([Vector2(0,0),Vector2(1,1),Vector2(0,1),Vector2(1,0)]),"bow tie")
	reject(PackedVector2Array([Vector2(0,0),Vector2(2,0),Vector2(1,0),Vector2(2,2),Vector2(0,2)]),"adjacent backtracking")
	reject(PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,4),Vector2(2,0),Vector2(0,4)]),"nonadjacent vertex on edge")
	reject(PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,4),Vector2(1,4),Vector2(1,0),Vector2(3,0),Vector2(3,2),Vector2(0,2)]),"overlapping nonadjacent edges")
	reject(PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(2,0)]),"zero area")
	var repeated:=square.duplicate();repeated.append(square[0]);reject(repeated,"explicit repeated closing vertex")
	var nonfinite:=square.duplicate();nonfinite[0].x=INF;reject(nonfinite,"infinite coordinate")
	var excessive:=PackedVector2Array();excessive.resize(513);reject(excessive,"oversized polygon")
	var snapshot:PackedInt32Array=GemPolygon.triangulate(square).indices.duplicate()
	var detached:=GemPolygon.triangulate(square)
	detached.indices[0]=999
	check(GemPolygon.triangulate(square).indices==snapshot,"caller cannot modify cached triangulation")
	var previous_builds:int=GemPolygon.cache_statistics().builds
	GemPolygon.triangulate(square)
	check(GemPolygon.cache_statistics().builds==previous_builds,"same encoded outline reuses admission and triangulation")
	for i in 32:
		var moved:=PackedVector2Array()
		for p in square:moved.append(p+Vector2(i*4+50,123))
		GemPolygon.triangulate(moved)
	var stats:=GemPolygon.cache_statistics()
	check(stats.entries<=GemPolygon.CACHE_ENTRIES and stats.retained_bytes<=GemPolygon.CACHE_BYTES,"polygon cache stays within both budgets")
	check(GemPolygon.triangulate(square).indices==snapshot,"eviction and rebuild preserve output")
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.shape.mode="loft";stone.shape.outline_points=backwards
	check(LapidaryStoneCompiler.compile(stone).has("compilation_error"),"invalid procedural host returns a compilation error")
	DirAccess.make_dir_recursive_absolute("res://artifacts/polygon")
	check(GemArtifactStore.atomic_write("res://artifacts/polygon/corpus.json",JSON.stringify(corpus,"\t",true,true).to_utf8_buffer()),"write current rational-reference corpus")
	print("Polygon: %d checks, %d failures"%[checks,failures]);print("CHECK_COMPLETE: test_polygon"); quit(1 if failures else 0)
