// Shared continuous-patch intersection for optical transport and admission probes.
// The host supplies analytic_clip(). Wire data is always binary32.
#undef GP_REAL
#undef GP_VEC3
#ifdef GEM_ANALYTIC_FP64
#define GP_REAL double
#define GP_VEC3 dvec3
#else
#define GP_REAL float
#define GP_VEC3 vec3
#endif
#ifndef GEM_ANALYTIC_STRUCT
#define GEM_ANALYTIC_STRUCT
struct GemAnalyticPrimitive { vec4 center_radius; vec4 normal; vec4 end; ivec4 meta; };
#endif
vec4 analytic_clip(int index);

bool analytic_patch_hit(GemAnalyticPrimitive primitive, GP_VEC3 origin, GP_VEC3 direction,
        GP_REAL min_t, GP_REAL max_t, GP_REAL tolerance, out GP_REAL distance, out GP_VEC3 normal) {
    int kind=primitive.meta.y&255;
    if(kind<1 || kind>3) return false;
    GP_VEC3 center=GP_VEC3(primitive.center_radius.xyz);
    GP_REAL radius=GP_REAL(primitive.center_radius.w);
    GP_VEC3 axis=GP_VEC3(primitive.normal.xyz);
    // Keep the independently encoded direction. Subtracting two binary32
    // endpoints can rotate or collapse extremely short, valid convex edges.
    if(kind==1 || kind==2) axis=normalize(axis);
    GP_REAL roots[2]; int count=0;
    if(kind==1) {
        GP_REAL denominator=dot(axis,direction);
        if(abs(denominator)<GP_REAL(1e-30)) return false;
        roots[count++]=dot(axis,center-origin)/denominator;
    } else {
        GP_VEC3 o=origin-center, d=direction;
        if(kind==2) { o-=axis*dot(o,axis); d-=axis*dot(d,axis); }
        GP_REAL a=dot(d,d);
        if(a<GP_REAL(1e-30)) return false;
        GP_REAL middle=-dot(o,d)/a;
        GP_VEC3 nearest=o+d*middle;
        GP_REAL squared=radius*radius-dot(nearest,nearest);
        if(squared<GP_REAL(0)) return false;
        GP_REAL delta=sqrt(squared/a);
        roots[count++]=middle-delta; roots[count++]=middle+delta;
    }
    for(int root=0;root<count;root++) {
        GP_REAL t=roots[root];
        if(t<=min_t || t>=max_t) continue;
        GP_VEC3 relative=(origin-center)+direction*t;
        bool inside=true;
        for(int i=0;i<(primitive.meta.y>>8);i++) {
            vec4 clip=analytic_clip(primitive.meta.z+i);
            if(dot(GP_VEC3(clip.xyz),relative)-GP_REAL(clip.w)>tolerance) { inside=false;break; }
        }
        if(!inside) continue;
        normal=axis;
        if(kind!=1) {
            if(kind==2) relative-=axis*dot(relative,axis);
            normal=normalize(relative);
        }
        distance=t;return true;
    }
    return false;
}
