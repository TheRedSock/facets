#version 450
// Deterministic primary-surface geometry; no optical paths, lighting or RNG.
#include "gem_common.glsl"
#include "gem_mesh.glsl"
layout(local_size_x=8,local_size_y=8) in;
layout(push_constant,std430) uniform Params {
    ivec2 resolution;
    ivec2 grid;
    ivec2 cell_px;
    int coverage_side;
    int row_origin;
} pc;
struct GeometryRecord { vec4 position_depth; vec4 normal_coverage; ivec4 ids; };
layout(set=0,binding=16,std430) writeonly buffer Geometry { GeometryRecord records[]; };
void main() {
    ivec2 pix=ivec2(gl_GlobalInvocationID.xy);
    pix.y+=pc.row_origin;
    if(any(greaterThanEqual(pix,pc.resolution))) return;
    int idx=pix.y*pc.resolution.x+pix.x;
    ivec2 cell=pix/pc.cell_px;
    GeometryRecord result;
    result.position_depth=vec4(0); result.normal_coverage=vec4(0); result.ids=ivec4(-1);
    if(any(greaterThanEqual(cell,pc.grid))) { records[idx]=result; return; }
    int instance_id=cell.y*pc.grid.x+cell.x;
    Inst inst=insts[instance_id]; Stone st=stones[inst.which.x];
    vec4 qc=quat_conj(inst.quat);
    vec3 direction=quat_rot(qc,vec3(0,0,-1));
    vec2 pixel=vec2(pix-cell*pc.cell_px);
    float hits=0.0,best=INF;
    for(int y=0;y<pc.coverage_side;y++) for(int x=0;x<pc.coverage_side;x++) {
        // Match the tracer's pixel-center convention: pixel+sample-0.5.
        vec2 offset=(vec2(x,y)+0.5)/float(pc.coverage_side)-0.5;
        vec2 ndc=(pixel+offset)/vec2(pc.cell_px)*2.0-1.0;
        vec3 origin=quat_rot(qc,vec3(ndc.x*inst.rig.y,-ndc.y*inst.rig.y,inst.rig2.z));
        float distance; int surface; uvec4 after;
        if(!physical_boundary(st,origin,direction,uvec4(0),distance,surface,after)) continue;
        hits+=1.0;
        float score=dot(offset,offset);
        if(score>=best) continue;
        best=score;
        vec3 position=origin+direction*distance;
        vec3 normal=boundary_normal(st,surface,position);
        if(dot(normal,direction)>0.0) normal=-normal;
        int region=surface<0||st.ranges1.z==0?0:triangles[surface].meta.w;
        int facet=st.ranges1.z==0?floatBitsToInt(planes[surface].aux.z):
            (surface<0?surface:triangles[surface].meta.x);
        result.position_depth=vec4(position*st.sell_b_size.w,distance*st.sell_b_size.w);
        result.normal_coverage.xyz=normal;
        result.ids=ivec4(instance_id,facet,region,region_medium(st,after));
    }
    result.normal_coverage.w=hits/float(pc.coverage_side*pc.coverage_side);
    records[idx]=result;
}
