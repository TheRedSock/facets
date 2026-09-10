// Lossless uniaxial Maxwell interface math, independently checked against the
// float64 CPU solver. The explicit crystal backend compiles this same source
// at float64 precision; float32 remains a diagnostic variant.
struct CrystalMode {
    vec3 kr; vec3 ki;
    vec3 er; vec3 ei;
    vec3 hr; vec3 hi;
    vec3 poynting;
    vec2 q;
    float normal_flux;
    bool evanescent;
    bool valid;
};
struct CrystalInterface {
    CrystalMode mode[4];
    vec2 amplitude[4];
    vec4 power;
    float residual;
    bool valid;
};
vec2 crystal_mul(vec2 a, vec2 b) { return vec2(a.x*b.x-a.y*b.y, a.x*b.y+a.y*b.x); }
vec2 crystal_div(vec2 a, vec2 b) { return crystal_mul(a, vec2(b.x,-b.y))/dot(b,b); }
vec3 crystal_metric(vec3 v, vec3 axis, float no, float ne) {
    return v/(ne*ne) + axis*dot(v,axis)*(1.0/(no*no)-1.0/(ne*ne));
}
vec3 crystal_inverse_epsilon(vec3 v, vec3 axis, float no, float ne) {
    return v/(no*no) + axis*dot(v,axis)*(1.0/(ne*ne)-1.0/(no*no));
}
CrystalMode crystal_mode_unit(float no, float ne, vec3 axis, vec3 normal, vec3 tangent, float side, bool extraordinary) {
    CrystalMode m;
    m.valid=false;
    float a=1.0, b=0.0, c=dot(tangent,tangent)-no*no;
    if (extraordinary) {
        vec3 mn=crystal_metric(normal,axis,no,ne);
        vec3 mt=crystal_metric(tangent,axis,no,ne);
        a=dot(normal,mn); b=dot(normal,mt); c=dot(tangent,mt)-1.0;
    }
    float disc=b*b-a*c;
    m.q=vec2(-b/a,0.0);
    if (disc>=0.0) m.q.x+=side*sqrt(disc)/a;
    else m.q.y=side*sqrt(-disc)/a;
    m.evanescent=disc<0.0;
    m.kr=tangent+normal*m.q.x; m.ki=normal*m.q.y;
    vec3 orr=cross(axis,m.kr), ori=cross(axis,m.ki);
    if (dot(orr,orr)+dot(ori,ori)<1e-12) {
        vec3 helper=abs(m.kr.x)<0.8*length(m.kr)?vec3(1,0,0):vec3(0,1,0);
        orr=cross(helper,m.kr); ori=cross(helper,m.ki);
    }
    m.er=orr; m.ei=ori;
    if (extraordinary) {
        m.er=crystal_inverse_epsilon(cross(m.kr,orr)-cross(m.ki,ori),axis,no,ne);
        m.ei=crystal_inverse_epsilon(cross(m.kr,ori)+cross(m.ki,orr),axis,no,ne);
    }
    float norm=sqrt(dot(m.er,m.er)+dot(m.ei,m.ei));
    if (!(norm>1e-20)) return m;
    m.er/=norm; m.ei/=norm;
    m.hr=cross(m.kr,m.er)-cross(m.ki,m.ei);
    m.hi=cross(m.kr,m.ei)+cross(m.ki,m.er);
    m.poynting=0.5*(cross(m.er,m.hr)+cross(m.ei,m.hi));
    m.normal_flux=dot(m.poynting,normal);
    m.valid=true;
    return m;
}
CrystalMode crystal_mode(float no, float ne, vec3 axis, vec3 normal, vec3 tangent, float side, bool extraordinary) {
    return crystal_mode_unit(no,ne,normalize(axis),normalize(normal),tangent,side,extraordinary);
}
vec2 crystal_field(CrystalMode m, vec3 u, vec3 v, int row) {
    vec3 axis=(row%2)==0?u:v;
    return row<2?vec2(dot(m.er,axis),dot(m.ei,axis)):vec2(dot(m.hr,axis),dot(m.hi,axis));
}
// Propagating lossless modes have real basis fields, even when the incoming
// coherent packet is elliptical. Solve one real matrix with two RHS components;
// evanescent modes still use the complete complex system below.
bool crystal_solve_real(inout CrystalInterface result, CrystalMode incoming, vec3 u, vec3 v) {
    vec4 rows[4]; vec2 rhs[4];
    for (int row=0;row<4;row++) {
        for (int col=0;col<4;col++) rows[row][col]=crystal_field(result.mode[col],u,v,row).x*(col<2?1.0:-1.0);
        rhs[row]=-crystal_field(incoming,u,v,row);
    }
    for (int pivot=0;pivot<4;pivot++) {
        int best=pivot; float magnitude=0.0;
        for (int row=pivot;row<4;row++) {
            float candidate=rows[row][pivot]*rows[row][pivot];
            if (candidate>magnitude) { magnitude=candidate; best=row; }
        }
        if (magnitude<1e-16) return false;
        if (best!=pivot) {
            vec4 temporary=rows[pivot]; rows[pivot]=rows[best]; rows[best]=temporary;
            vec2 r=rhs[pivot]; rhs[pivot]=rhs[best]; rhs[best]=r;
        }
        float inverse=1.0/rows[pivot][pivot];
        for (int row=pivot+1;row<4;row++) {
            float factor=rows[row][pivot]*inverse;
            for (int col=pivot+1;col<4;col++) rows[row][col]-=factor*rows[pivot][col];
            rhs[row]-=factor*rhs[pivot];
        }
    }
    for (int row=3;row>=0;row--) {
        vec2 value=rhs[row];
        for (int col=row+1;col<4;col++) value-=rows[row][col]*result.amplitude[col];
        result.amplitude[row]=value/rows[row][row];
    }
    return true;
}
CrystalInterface crystal_interface(vec2 source_n, vec3 source_axis, vec2 target_n, vec3 target_axis,
        vec3 normal, CrystalMode incoming) {
    CrystalInterface result;
    result.valid=false; result.power=vec4(0); result.residual=0.0;
    normal=normalize(normal);
    source_axis=normalize(source_axis); target_axis=normalize(target_axis);
    float flux=dot(incoming.poynting,normal);
    if (!incoming.valid || incoming.evanescent || flux<=1e-8) return result;
    vec3 tangent=incoming.kr-normal*dot(incoming.kr,normal);
    for (int i=0;i<4;i++) {
        bool reflected=i<2;
        vec2 indices=reflected?source_n:target_n;
        vec3 axis=reflected?source_axis:target_axis;
        result.mode[i]=crystal_mode_unit(indices.x,indices.y,axis,normal,tangent,reflected?-1.0:1.0,(i%2)==1);
        if (!result.mode[i].valid) return result;
    }
    vec3 helper=abs(normal.x)<0.8?vec3(1,0,0):vec3(0,1,0);
    vec3 u=normalize(cross(helper,normal)), v=cross(normal,u);
    bool real_basis=true;
    for (int i=0;i<4;i++) real_basis=real_basis && !result.mode[i].evanescent;
    if (real_basis) {
        if (!crystal_solve_real(result,incoming,u,v)) return result;
    } else {
        vec2 a[20];
        for (int row=0;row<4;row++) {
            for (int col=0;col<4;col++) a[row*5+col]=crystal_field(result.mode[col],u,v,row)*(col<2?1.0:-1.0);
            a[row*5+4]=-crystal_field(incoming,u,v,row);
        }
        for (int pivot=0;pivot<4;pivot++) {
            int best=pivot; float magnitude=0.0;
            for (int row=pivot;row<4;row++) {
                float candidate=dot(a[row*5+pivot],a[row*5+pivot]);
                if (candidate>magnitude) { magnitude=candidate; best=row; }
            }
            if (magnitude<1e-16) return result;
            if (best!=pivot) {
                for (int col=0;col<5;col++) {
                    vec2 temporary=a[pivot*5+col]; a[pivot*5+col]=a[best*5+col]; a[best*5+col]=temporary;
                }
            }
            // Forward elimination needs only rows below the pivot. One reciprocal
            // serves the whole column; back substitution avoids reducing all four
            // columns to an identity matrix for a single incident-field RHS.
            vec2 inverse=crystal_div(vec2(1,0),a[pivot*5+pivot]);
            for (int row=pivot+1;row<4;row++) {
                vec2 factor=crystal_mul(a[row*5+pivot],inverse);
                for (int col=pivot+1;col<5;col++) a[row*5+col]-=crystal_mul(factor,a[pivot*5+col]);
            }
        }
        for (int row=3;row>=0;row--) {
            vec2 rhs=a[row*5+4];
            for (int col=row+1;col<4;col++) rhs-=crystal_mul(a[row*5+col],result.amplitude[col]);
            result.amplitude[row]=crystal_div(rhs,a[row*5+row]);
        }
    }
    for (int col=0;col<4;col++) {
        float factor=dot(result.amplitude[col],result.amplitude[col]);
        result.power[col]=result.mode[col].evanescent?0.0:(col<2?-1.0:1.0)*result.mode[col].normal_flux*factor/flux;
    }
    for (int row=0;row<4;row++) {
        vec2 residual=crystal_field(incoming,u,v,row);
        for (int col=0;col<4;col++) residual+=crystal_mul(crystal_field(result.mode[col],u,v,row),result.amplitude[col])*(col<2?1.0:-1.0);
        result.residual=max(result.residual,length(residual));
    }
    result.valid=true;
    return result;
}
