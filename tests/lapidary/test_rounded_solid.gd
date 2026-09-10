extends SceneTree
const V := preload("res://core/lapidary/geometry/geometry64.gd")
var checks:=0
var failures:=0
var maximum_distance_error:=0.0

func check(value:bool,label:String)->void:
	checks+=1
	if not value: failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var planes:=PackedFloat32Array()
	for n:Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:
		planes.append_array(PackedFloat32Array([n.x,n.y,n.z,1,0,0,0,0]))
	var recipe:=GemRounding.new();recipe.max_removed_fraction=.99
	var kinds:=PackedInt32Array([0,0,0])
	for radius in [1e-8,.000001,.01,.2,.8,.999]:
		recipe.radius_mm=radius
		var solid:=GemRoundedSolid.compile(planes,PackedInt32Array(),1,recipe)
		check(solid.error.is_empty(),"continuous cube radius %s: %s"%[radius,solid.error])
		if not solid.error.is_empty():continue
		check(solid.patches.size()==26,"cube has six planes, twelve cylinders, eight spherical patches")
		var a:float=1-radius
		var expected:float=8*a*a*a+24*a*a*radius+6*PI*a*radius*radius+4*PI*radius*radius*radius/3
		check(absf(solid.report.retained_mm3-expected)<2e-12,"Steiner volume agrees with independent cube decomposition")
		for normal:PackedFloat64Array in [V.vec(1,0,0),V.unit(V.vec(1,1,0)),V.unit(V.vec(1,1,1))]:
			var center:=V.vec(a,a if normal[1]>0 else 0,a if normal[2]>0 else 0)
			var target:=V.add(center,V.scale(normal,radius))
			var hit:=solid.intersect(V.add(target,V.scale(normal,3)),V.scale(normal,-1))
			check(not hit.is_empty() and absf(hit.t-3)<1e-12 and V.dot(hit.normal,normal)>1-1e-10,"targeted face/edge/corner hit at radius %s"%radius)
			if not hit.is_empty():kinds[hit.kind]+=1
		for i in 96:
			var normal:=V.unit(V.vec(sin(i*1.23+.1),cos(i*.71+.2),sin(i*2.51+.3)))
			var origin:=V.scale(normal,3)
			var direction:=V.unit(V.subtract(V.vec(.5*sin(i*.2),.4*cos(i*.3),.3*sin(i*.4)),origin))
			var roots:=box_roots(origin,direction,a,radius)
			var hit:=solid.intersect(origin,direction)
			check(not hit.is_empty() and roots.size()==2,"convex ray has entry and exit")
			if hit.is_empty() or roots.size()!=2:continue
			var difference:=absf(hit.t-roots[0])
			maximum_distance_error=maxf(maximum_distance_error,difference)
			check(difference<2e-11,"entry agrees with independent piecewise rounded-box oracle")
			var exit_hit:=solid.intersect(origin,direction,hit.t+1e-10)
			check(not exit_hit.is_empty() and absf(exit_hit.t-roots[1])<2e-11,"exit agrees with independent rounded-box oracle")
			var p:PackedFloat64Array=hit.position
			var q:=V.vec(clampf(p[0],-a,a),clampf(p[1],-a,a),clampf(p[2],-a,a))
			var delta:=V.subtract(p,q)
			check(absf(sqrt(V.dot(delta,delta))-radius)<2e-12,"hit lies on continuous rounded-box surface")
		# The exact face/cylinder junction must not leave a hole or a normal jump.
		var seam:=solid.intersect(V.vec(3,a,0),V.vec(-1,0,0))
		check(not seam.is_empty() and absf(seam.t-2)<1e-12 and V.dot(seam.normal,V.vec(1,0,0))>1-1e-12,"continuous patch seam")
	check(kinds[0]>0 and kinds[1]>0 and kinds[2]>0,"all three patch families exercised")
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.rounding=null;recipe.radius_mm=.03
	for outline in [&"round",&"square",&"triangle",&"oval",&"diamond",&"rectangle",&"marquise",&"pear"]:
		stone.shape=GemShape.faceted_outline(outline)
		var geometry:=LapidaryStoneCompiler.compile_geometry(stone)
		var solid:=GemRoundedSolid.compile(geometry.planes,geometry.facet_ids,stone.size_mm,recipe)
		check(solid.error.is_empty(),"continuous "+str(outline)+": "+solid.error)
		if not solid.error.is_empty():continue
		check(solid.report.removed_mm3>0 and solid.patches.size()<1000,"finite positive removal and compact patch count")
		var worst_surface:=0.0;var worst_support:=0.0;var missing:=0
		for i in 32:
			var direction:=V.unit(V.vec(sin(i*1.2+.1),cos(i*.7+.2),sin(i*2.5+.3)))
			var hit:=solid.intersect(V.scale(direction,3),V.scale(direction,-1))
			if hit.is_empty():missing+=1;continue
			var nearest:=solid.core.closest_point(hit.position)
			worst_surface=maxf(worst_surface,absf(nearest.distance-solid.radius))
			var core_point:=V.subtract(hit.position,V.scale(hit.normal,solid.radius))
			for vertex in solid.core.vertices:
				worst_support=maxf(worst_support,V.dot(hit.normal,V.subtract(vertex,core_point)))
		check(missing==0 and worst_surface<1e-10,"all-outline hits agree with independent closest-feature distance")
		check(worst_support<1e-10,"surface normal supports the convex offset body")
		var mesh_reference:=GemRoundingCompiler.compile(geometry.planes,geometry.facet_ids,stone.size_mm,recipe)
		check(mesh_reference.error.is_empty(),"mesh comparison compiles")
		if mesh_reference.has("mesh"):
			var worst_deviation:=0.0
			var points:PackedVector3Array=mesh_reference.mesh.vertices
			for i in 32:
				var point:=points[i*(points.size()-1)/31]
				var nearest:=solid.core.closest_point(V.vec(point.x,point.y,point.z))
				worst_deviation=maxf(worst_deviation,absf(nearest.distance-solid.radius)*stone.size_mm)
			check(worst_deviation<mesh_reference.report.chord_sag_bound_mm+5e-6,"mesh vertices approach the continuous offset within construction/tessellation tolerance")
		var scaled_recipe:GemRounding=recipe.duplicate();scaled_recipe.radius_mm*=3
		var scaled:=GemRoundedSolid.compile(geometry.planes,geometry.facet_ids,stone.size_mm*3,scaled_recipe)
		check(scaled.error.is_empty() and absf(scaled.report.retained_mm3-solid.report.retained_mm3*27)<1e-9,"physical scaling preserves shape and scales analytic volume cubically")
	recipe.radius_mm=1.1
	check(not GemRoundedSolid.compile(planes,PackedInt32Array(),1,recipe).error.is_empty(),"collapsed inset rejected")
	recipe.radius_mm=.2;recipe.max_removed_fraction=1e-5
	check(not GemRoundedSolid.compile(planes,PackedInt32Array(),1,recipe).error.is_empty(),"analytic removal budget enforced")
	recipe.max_removed_fraction=.99
	var valid:=GemRoundedSolid.compile(planes,PackedInt32Array(),1,recipe)
	var scaled_planes:=planes.duplicate()
	for i in scaled_planes.size()/8:
		for k in 4:scaled_planes[i*8+k]*=pow(2,i)
	check(absf(GemRoundedSolid.compile(scaled_planes,PackedInt32Array(),1,recipe).report.retained_mm3-valid.report.retained_mm3)<1e-12,"positive support rescaling leaves the physical body unchanged")
	check(not GemRoundedSolid.compile(planes.slice(0,40),PackedInt32Array(),1,recipe).error.is_empty(),"unbounded host rejected")
	check(not GemRoundedSolid.compile(planes,PackedInt32Array([1]),1,recipe).error.is_empty(),"incomplete semantic identity table rejected")
	check(not GemRoundedSolid.compile(planes,PackedInt32Array(),0,recipe).error.is_empty(),"zero physical size rejected")
	var invalid:=planes.duplicate();invalid[0]=NAN
	check(not GemRoundedSolid.compile(invalid,PackedInt32Array(),1,recipe).error.is_empty(),"nonfinite support rejected")
	check(valid.intersect(V.vec(0,0,3),V.vec(0,0,-1),NAN).is_empty(),"nonfinite ray interval rejected")
	var detached:=valid.intersect(V.vec(3,0,0),V.vec(-1,0,0))
	detached.normal[0]=0
	check(valid.intersect(V.vec(3,0,0),V.vec(-1,0,0)).normal[0]==1,"returned plane normal cannot mutate the solid")
	var packed:=GemAnalyticPacking.pack(valid)
	check(packed.count==26 and packed.primitives.size()==26*64 and packed.clips.size()%16==0,"analytic candidate wire sizes")
	var clip_end:=0
	for i in packed.count:
		var meta:int=packed.primitives.decode_s32(i*64+52)
		var offset:int=packed.primitives.decode_s32(i*64+56)
		clip_end=maxi(clip_end,offset+(meta>>8))
	check(clip_end*16==packed.clips.size(),"every packed clipping plane belongs to a declared range")
	print("Continuous rounded solid: %d checks, %d failures; maximum ray error %s"%[checks,failures,maximum_distance_error])
	quit(1 if failures else 0)

## Independent implicit-box oracle. Break the ray where a coordinate crosses
## a core slab; within each interval the squared distance is a quadratic.
static func box_roots(o:PackedFloat64Array,d:PackedFloat64Array,a:float,r:float)->Array[float]:
	var cuts:Array[float]=[0,10]
	for axis in 3:
		if absf(d[axis])>1e-20:
			for side in [-a,a]:
				var t:float=(side-o[axis])/d[axis]
				if t>0 and t<10:cuts.append(t)
	cuts.sort()
	var roots:Array[float]=[]
	for interval in cuts.size()-1:
		var middle:=.5*(cuts[interval]+cuts[interval+1])
		var aa:=0.0;var bb:=0.0
		var origins:Array[float]=[];var directions:Array[float]=[]
		for axis in 3:
			var coordinate:=o[axis]+middle*d[axis]
			if absf(coordinate)>a:
				var start:=o[axis]-signf(coordinate)*a
				origins.append(start);directions.append(d[axis]);aa+=d[axis]*d[axis];bb+=start*d[axis]
		if aa==0:continue
		var closest:=-bb/aa
		var minimum:=0.0
		for index in origins.size():minimum+=pow(origins[index]+closest*directions[index],2)
		if minimum>r*r:continue
		var delta:=sqrt((r*r-minimum)/aa)
		for t in [closest-delta,closest+delta]:
			if t>0 and t>=cuts[interval]-1e-13 and t<=cuts[interval+1]+1e-13:
				if roots.is_empty() or absf(t-roots[-1])>1e-12:roots.append(t)
	return roots
