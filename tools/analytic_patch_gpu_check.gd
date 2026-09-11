extends SceneTree
const V := preload("res://core/lapidary/geometry/geometry64.gd")
var failures:=0
var reports:=[]

func _initialize()->void:
	var stress:=OS.get_cmdline_user_args().has("--stress")
	var accelerated:=OS.get_cmdline_user_args().has("--bvh")
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var shaders:=[];var pipelines:=[]
	for fp64 in [false,true]:
		var src:=RDShaderSource.new()
		src.source_compute="#version 450\n"+("#extension GL_ARB_gpu_shader_fp64 : require\n#define GEM_ANALYTIC_FP64\n" if fp64 else "")+FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_analytic_patch.glsl")+_body(accelerated)
		var spirv:=rd.shader_compile_spirv_from_source(src)
		if not spirv.compile_error_compute.is_empty():printerr(spirv.compile_error_compute);rd.free();quit(1);return
		var shader:=rd.shader_create_from_spirv(spirv);shaders.append(shader);pipelines.append(rd.compute_pipeline_create(shader))
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.rounding=null
	var recipe:=GemRounding.new();recipe.max_removed_fraction=.9
	for outline in [&"round",&"square",&"triangle",&"oval",&"diamond",&"rectangle",&"marquise",&"pear"]:
		stone.shape=GemShape.faceted_outline(outline)
		var geometry:=LapidaryStoneCompiler.compile_geometry(stone)
		for radius in [.03,.6]:
			recipe.radius_mm=radius
			var start:=Time.get_ticks_usec()
			var solid:=GemRoundedSolid.compile(geometry.planes,geometry.facet_ids,4,recipe)
			if not solid.error.is_empty():printerr("FAIL: "+solid.error);failures+=1;continue
			var compile_ms:=(Time.get_ticks_usec()-start)/1000.0
			var queries:=PackedFloat32Array()
			for pose in 2:
				var rotation:=Basis(Quaternion(Vector3.UP,.53*pose)*Quaternion(Vector3.RIGHT,.27*pose))
				for y in 16:
					for x in 16:
						var o:=rotation*Vector3((x-7.5)*.17,(y-7.5)*.17,3)
						var d:=rotation*Vector3.FORWARD
						queries.append_array(PackedFloat32Array([o.x,o.y,o.z,0,d.x,d.y,d.z,0]))
			if stress:_feature_queries(solid,queries)
			var expected:Array[Dictionary]=[]
			for i in queries.size()/8:
				expected.append(solid.intersect(V.vec(queries[i*8],queries[i*8+1],queries[i*8+2]),V.vec(queries[i*8+4],queries[i*8+5],queries[i*8+6]),queries[i*8+3]))
			var packed:=GemAnalyticPacking.pack(solid)
			if accelerated:
				var accelerated_data:=GemPrimitiveBvh.pack(solid)
				if not accelerated_data.error.is_empty():printerr("FAIL: "+accelerated_data.error);failures+=1;continue
				packed["primitives"]=accelerated_data.triangles
				packed["nodes"]=accelerated_data.nodes
			for precision in 2:
				var raw:=_dispatch(rd,shaders[precision],pipelines[precision],packed,queries)
				var missing:=0;var extra:=0;var mismatch:=0;var maximum_t:=0.0;var maximum_angle:=0.0
				var anomalies:=[]
				var primitive_tests:=0
				for i in expected.size():
					primitive_tests+=raw.decode_s32(i*48+40)
					var hit:=raw.decode_s32(i*48+32)>=0
					if expected[i].is_empty():
						if hit:
							extra+=1
							if anomalies.size()<6:anomalies.append({"query":i,"reason":"extra","ray":Array(queries.slice(i*8,i*8+8)),"actual_t":raw.decode_float(i*48)+raw.decode_float(i*48+16),"actual_patch":raw.decode_s32(i*48+32)})
						continue
					if not hit:missing+=1;continue
					var t:=raw.decode_float(i*48)+raw.decode_float(i*48+16)
					var normal:=V.vec(raw.decode_float(i*48+4)+raw.decode_float(i*48+20),raw.decode_float(i*48+8)+raw.decode_float(i*48+24),raw.decode_float(i*48+12)+raw.decode_float(i*48+28))
					if not is_finite(t) or not V.finite(normal):missing+=1;continue
					maximum_t=maxf(maximum_t,absf(t-expected[i].t))
					maximum_angle=maxf(maximum_angle,acos(clampf(V.dot(V.unit(normal),expected[i].normal),-1,1)))
					if (absf(t-expected[i].t)>5e-6 or acos(clampf(V.dot(V.unit(normal),expected[i].normal),-1,1))>1e-3) and anomalies.size()<6:
						anomalies.append({"query":i,"reason":"difference","ray":Array(queries.slice(i*8,i*8+8)),"expected":expected[i],"actual_t":t,"actual_normal":Array(normal),"actual_patch":raw.decode_s32(i*48+32)})
					if raw.decode_s32(i*48+36)!=expected[i].facet:mismatch+=1
				var report:={"outline":outline,"radius_mm":radius,"precision":"float64" if precision else "float32","queries":expected.size(),"patches":solid.patches.size(),"compile_ms":compile_ms,"missing":missing,"extra":extra,"facet_mismatches":mismatch,"maximum_t_error":maximum_t,"maximum_normal_degrees":rad_to_deg(maximum_angle)}
				report["anomalies"]=anomalies
				report["accelerated"]=accelerated
				report["mean_primitive_tests"]=float(primitive_tests)/expected.size()
				reports.append(report);print(JSON.stringify(report,"",true,true))
				if missing>0 or extra>0 or maximum_t>5e-6 or maximum_angle>1e-3:failures+=1
	for rid in pipelines+shaders:rd.free_rid(rid)
	rd.free()
	GemArtifactStore.atomic_write("res://artifacts/rounded-solid/gpu-bvh-report.json" if accelerated else ("res://artifacts/rounded-solid/gpu-stress-report.json" if stress else "res://artifacts/rounded-solid/gpu-report.json"),JSON.stringify(reports,"\t",true,true).to_utf8_buffer())
	print("Analytic patch GPU: %d cases, %d failures"%[reports.size(),failures]);quit(1 if failures else 0)

func _dispatch(rd:RenderingDevice,shader:RID,pipeline:RID,packed:Dictionary,queries:PackedFloat32Array)->PackedByteArray:
	var zero:=PackedByteArray();zero.resize(queries.size()/8*48)
	var blobs:=[packed.primitives,packed.clips,queries.to_byte_array(),zero]
	if packed.has("nodes"):blobs.append(packed.nodes)
	var uniforms:Array[RDUniform]=[];var buffers:=[]
	for binding in blobs.size():
		var bytes:PackedByteArray=blobs[binding]
		var buffer:=rd.storage_buffer_create(bytes.size(),bytes);buffers.append(buffer)
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=binding;u.add_id(buffer);uniforms.append(u)
	var set:=rd.uniform_set_create(uniforms,shader,0)
	var push:=PackedByteArray();push.resize(32);push.encode_u32(0,queries.size()/8);push.encode_u32(4,packed.count);push.encode_float(16,1e-6)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0);rd.compute_list_set_push_constant(list,push,32);rd.compute_list_dispatch(list,ceili(queries.size()/8.0/64),1,1);rd.compute_list_end();rd.submit();rd.sync()
	var result:=rd.buffer_get_data(buffers[3])
	rd.free_rid(set)
	for rid in buffers:rd.free_rid(rid)
	return result

func _feature_queries(solid:GemRoundedSolid,queries:PackedFloat32Array)->void:
	for face:Dictionary in solid.core.faces:
		var center:=V.vec(0,0,0)
		for vertex in face.ring:center=V.add(center,V.scale(solid.core.vertices[vertex],1.0/face.ring.size()))
		_probe(queries,V.add(center,V.scale(face.normal,solid.radius)),face.normal)
	for edge:Dictionary in solid.core.edges:
		var a:=solid.core.vertices[edge.a];var b:=solid.core.vertices[edge.b]
		var na:PackedFloat64Array=solid.core.faces[edge.faces[0]].normal
		var nb:PackedFloat64Array=solid.core.faces[edge.faces[1]].normal
		var normal:=V.unit(V.add(na,nb));var middle:=V.scale(V.add(a,b),.5)
		_probe(queries,V.add(middle,V.scale(normal,solid.radius)),normal)
		for n:PackedFloat64Array in [na,nb]:
			var point:=V.add(middle,V.scale(n,solid.radius))
			_query(queries,V.add(point,V.scale(n,.5)),V.scale(n,-1),0)
		for point:PackedFloat64Array in [a,b]:
			point=V.add(point,V.scale(normal,solid.radius))
			_query(queries,V.add(point,V.scale(normal,.5)),V.scale(normal,-1),0)
	for vertex in solid.core.vertices.size():
		var normal:=V.vec(0,0,0)
		for face:Dictionary in solid.core.faces:
			if face.ring.has(vertex):normal=V.add(normal,face.normal)
		normal=V.unit(normal)
		_probe(queries,V.add(solid.core.vertices[vertex],V.scale(normal,solid.radius)),normal)

func _probe(queries:PackedFloat32Array,point:PackedFloat64Array,normal:PackedFloat64Array)->void:
	_query(queries,V.add(point,V.scale(normal,.5)),V.scale(normal,-1),0)
	_query(queries,point,V.scale(normal,-1),1e-5)
	_query(queries,point,normal,1e-5)
	var helper:=V.vec(0,0,1) if absf(normal[2])<.8 else V.vec(1,0,0)
	var tangent:=V.unit(V.cross(normal,helper))
	_query(queries,point,V.unit(V.subtract(tangent,V.scale(normal,.01))),1e-5)

func _query(queries:PackedFloat32Array,o:PackedFloat64Array,d:PackedFloat64Array,min_t:float)->void:
	queries.append_array(PackedFloat32Array([o[0],o[1],o[2],min_t,d[0],d[1],d[2],0]))

func _body(accelerated:bool)->String:
	if not accelerated: return BODY.replace("ivec4(winner,facet,0,0)","ivec4(winner,facet,params.counts.y,0)")
	var body:=BODY.replace("void main() {",BVH+"\nvoid main() {")
	body=body.replace("for(int p=0;p<int(params.counts.y);p++) {", "int tested=0; int pending=1; int stack[64]; stack[0]=0;\n    while(pending>0) {\n        Node node=nodes[stack[--pending]];\n        if(!box_hit(node,o,d,GP_REAL(queries[i*2].w),nearest)) continue;\n        if(node.links.w==0) { stack[pending++]=node.links.x;stack[pending++]=node.links.y;continue; }\n        for(int p=node.links.z;p<node.links.z+node.links.w;p++) { tested++;")
	body=body.replace("    vec4 high=", "    }\n    vec4 high=")
	return body.replace("ivec4(winner,facet,0,0)","ivec4(winner,facet,tested,0)")

const BVH:="""
struct Node { vec4 low; vec4 high; ivec4 links; };
layout(set=0,binding=4,std430) readonly buffer Nodes { Node nodes[]; };
bool box_hit(Node n,GP_VEC3 o,GP_VEC3 d,GP_REAL lo,GP_REAL hi) {
    for(int axis=0;axis<3;axis++) {
        if(abs(d[axis])<GP_REAL(1e-30)) {
            if(o[axis]<GP_REAL(n.low[axis]) || o[axis]>GP_REAL(n.high[axis])) return false;
        } else {
            GP_REAL a=(GP_REAL(n.low[axis])-o[axis])/d[axis];
            GP_REAL b=(GP_REAL(n.high[axis])-o[axis])/d[axis];
            lo=max(lo,min(a,b));hi=min(hi,max(a,b));
            if(lo>hi) return false;
        }
    }
    return true;
}
"""

const BODY:="""
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Primitives { GemAnalyticPrimitive primitives[]; };
layout(set=0,binding=1,std430) readonly buffer Clips { vec4 clips[]; };
layout(set=0,binding=2,std430) readonly buffer Queries { vec4 queries[]; };
layout(set=0,binding=3,std430) buffer Results { vec4 results[]; };
layout(push_constant,std430) uniform Params { uvec4 counts; vec4 tolerance; } params;
vec4 analytic_clip(int index) { return clips[index]; }
void main() {
    uint i=gl_GlobalInvocationID.x;if(i>=params.counts.x)return;
    GP_VEC3 o=GP_VEC3(queries[i*2].xyz),d=GP_VEC3(queries[i*2+1].xyz);
    GP_REAL nearest=GP_REAL(1e30);GP_VEC3 normal=GP_VEC3(0);int winner=-1,facet=0;
    for(int p=0;p<int(params.counts.y);p++) {
        GP_REAL t;GP_VEC3 n;
        if(analytic_patch_hit(primitives[p],o,d,GP_REAL(queries[i*2].w),nearest,GP_REAL(params.tolerance.x),t,n)) { nearest=t;normal=n;winner=p;facet=primitives[p].meta.x; }
    }
    vec4 high=vec4(float(nearest),vec3(normal));
    results[i*3]=high;
    results[i*3+1]=vec4(float(nearest-GP_REAL(high.x)),vec3(normal-GP_VEC3(high.yzw)));
    results[i*3+2]=intBitsToFloat(ivec4(winner,facet,0,0));
}
"""
