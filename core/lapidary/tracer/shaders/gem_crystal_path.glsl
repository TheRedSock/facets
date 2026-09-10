// Reciprocal camera transport with air endpoints and unpolarized illumination.
// Launch two orthogonal Jones probes; reciprocity transposes the complete
// flux-normalized path response. The ray-measure factors telescope because
// both endpoints are in air. Intermediate crystal modes follow energy rays.
// No emitting volume, particle scattering, rough boundary or separated-path
// interference is modeled here. Admission rejects these unsupported inputs.
layout(set=0,binding=18,std430) buffer CrystalDiagnostics { uint crystal_stats[]; };

dvec2 crystal_indices(int material, float wavelength) {
    if(material<0) return dvec2(1.0);
    Stone st=stones[material];
    return dvec2(principal_index(st,wavelength,false),principal_index(st,wavelength,true));
}
dvec3 crystal_axis(int material) {
    return material<0?dvec3(0,0,1):normalize(dvec3(stones[material].optic_fluor.xyz));
}
CrystalMode crystal_normalize_packet(CrystalMode p) {
    double norm=sqrt(dot(p.er,p.er)+dot(p.ei,p.ei));
    p.er/=norm; p.ei/=norm; p.hr/=norm; p.hi/=norm;
    p.poynting=0.5*(cross(p.er,p.hr)+cross(p.ei,p.hi));
    return p;
}
CrystalMode crystal_packet(CrystalInterface boundary, int first, bool combine) {
    CrystalMode p=boundary.mode[first];
    p.er=dvec3(0); p.ei=dvec3(0); p.hr=dvec3(0); p.hi=dvec3(0);
    for(int j=first;j<first+(combine?2:1);j++) {
        CrystalMode m=boundary.mode[j]; dvec2 a=boundary.amplitude[j];
        p.er+=a.x*m.er-a.y*m.ei; p.ei+=a.x*m.ei+a.y*m.er;
        p.hr+=a.x*m.hr-a.y*m.hi; p.hi+=a.x*m.hi+a.y*m.hr;
    }
    p.poynting=0.5*(cross(p.er,p.hr)+cross(p.ei,p.hi));
    return p;
}

double crystal_absorption(inout CrystalMode packet, int material, float wavelength,
        vec3 position, vec3 direction, float distance) {
    if(material<0) return 1.0;
    Stone st=stones[material]; dvec2 indices=crystal_indices(material,wavelength);
    double ao=absorb_at(st.ranges1.x,wavelength);
    double ae=(st.ranges1.y&1)!=0?absorb_at(st.ranges1.x+401,wavelength):ao;
    double column=(zoning_column(st,position,direction,distance)+field_columns(st,position,direction,distance).x)
        *st.misc.y*st.sell_b_size.w;
    dvec3 axis=crystal_axis(material);
    if(indices.x==indices.y) {
        // Coherent isotropic Jones components may attenuate differently.
        dvec3 k=normalize(packet.kr), u=cross(axis,k);
        if(dot(u,u)<1e-22) u=normalize(cross(abs(k.z)<0.9?dvec3(0,0,1):dvec3(0,1,0),k));
        else u=normalize(u);
        dvec3 v=cross(k,u);
        double ca=dot(k,axis), ak=ca*ca*ao+(1.0-ca*ca)*ae;
        double to=double(exp(float(-0.5*ao*column))), te=double(exp(float(-0.5*ak*column)));
        double before=length(packet.poynting);
        packet.er=u*(dot(packet.er,u)*to)+v*(dot(packet.er,v)*te);
        packet.ei=u*(dot(packet.ei,u)*to)+v*(dot(packet.ei,v)*te);
        packet.hr=cross(packet.kr,packet.er); packet.hi=cross(packet.kr,packet.ei);
        packet.poynting=0.5*(cross(packet.er,packet.hr)+cross(packet.ei,packet.hi));
        double fraction=length(packet.poynting)/before;
        if(fraction>1e-30) packet=crystal_normalize_packet(packet);
        return fraction;
    }
    // Weak loss on a single extraordinary/ordinary Maxwell eigenmode.
    double e2=dot(packet.er,packet.er)+dot(packet.ei,packet.ei);
    double axial=dot(packet.er,axis)*dot(packet.er,axis)+dot(packet.ei,axis)*dot(packet.ei,axis);
    double alpha=(indices.x*ao*max(0.0,e2-axial)+indices.y*ae*axial)/(2.0*length(packet.poynting));
    return double(exp(float(-alpha*column)));
}

float trace_crystal_probe(Stone host, vec3 position, vec3 direction, float wavelength,
        int polarization, vec4 rotation, float rig_yaw, vec4 roles, inout uint rng) {
    dvec3 point=dvec3(position), ray_direction=normalize(dvec3(direction));
    dvec3 k=normalize(dvec3(ray_direction));
    dvec3 helper=abs(k.z)<0.9?dvec3(0,0,1):dvec3(0,1,0);
    dvec3 u=normalize(cross(helper,k));
    CrystalMode packet;
    packet.kr=k; packet.ki=dvec3(0); packet.er=polarization==0?u:cross(k,u);
    packet.ei=dvec3(0); packet.hr=cross(k,packet.er); packet.hi=dvec3(0);
    packet.poynting=0.5*cross(packet.er,packet.hr); packet.valid=true; packet.evanescent=false;
    uvec4 region_state=uvec4(0u);
    double weight=1.0, radiance=0.0;
    for(uint bounce=0u;bounce<pc.max_bounces;bounce++) {
        double distance; int hit;
        int before=crystal_geo_region_medium(host,region_state);
        if(!crystal_geo_boundary_hit(host,point,ray_direction,distance,hit)) {
            if(before<0) radiance+=weight*env_radiance(quat_rot(rotation,vec3(ray_direction)),vec4(wavelength),rig_yaw,roles,0).x;
            else { atomicAdd(crystal_stats[0],1u); atomicOr(crystal_stats[2],1u); }
            return float(radiance);
        }
        weight*=crystal_absorption(packet,before,wavelength,vec3(point),vec3(ray_direction),float(distance));
        if(weight<double(THROUGHPUT_EPS)) return float(radiance);
        point+=ray_direction*distance;
        uvec4 after=crystal_geo_cross_region(host,region_state,hit,point,ray_direction);
        int next=crystal_geo_region_medium(host,after);
        if(before==next) { region_state=after; point+=ray_direction*CRYSTAL_GEO_EPS*4.0; continue; }
        dvec3 normal=normalize(dvec3(crystal_geo_boundary_normal(host,hit,point)));
        if(dot(normal,packet.poynting)<0.0) normal=-normal;
        CrystalInterface boundary=crystal_interface(crystal_indices(before,wavelength),crystal_axis(before),
            crystal_indices(next,wavelength),crystal_axis(next),normal,packet);
        if(!boundary.valid || boundary.residual>1e-7) { atomicAdd(crystal_stats[0],1u); atomicOr(crystal_stats[2],2u); return float(radiance); }
        // Keep compact branch descriptors, not four copies of every complex
        // field vector. Only the selected continuing packet needs persistence.
        int mode_indices[4]; bool combined[4]; double powers[4]; int count=0;
        double remaining=0.0, total=0.0;
        for(int side=0;side<2;side++) {
            int medium=side==0?before:next;
            dvec2 indices=crystal_indices(medium,wavelength);
            dvec3 delta=boundary.mode[side*2].kr-boundary.mode[side*2+1].kr;
            bool combine=indices.x==indices.y || dot(delta,delta)<1e-26;
            for(int component=0;component<(combine?1:2);component++) {
                int j=side*2+component;
                if(boundary.mode[j].evanescent) continue;
                CrystalMode out_packet=crystal_packet(boundary,j,combine);
                double power=(side==0?-1.0:1.0)*dot(out_packet.poynting,normal)/dot(packet.poynting,normal);
                if(power<=1e-20) continue;
                total+=power;
                dvec3 ray=normalize(out_packet.poynting);
                uvec4 outgoing_state=side==0?region_state:after;
                double next_distance; int next_hit;
                bool escape=medium<0 && !crystal_geo_physical_hit(host,point+ray*CRYSTAL_GEO_EPS*4.0,ray,outgoing_state,next_distance,next_hit);
                if(escape) radiance+=weight*power*env_radiance(quat_rot(rotation,vec3(ray)),vec4(wavelength),rig_yaw,roles,0).x;
                else { mode_indices[count]=j; combined[count]=combine; powers[count]=power; remaining+=power; count++; }
            }
        }
        if(abs(total-1.0)>1e-6) { atomicAdd(crystal_stats[0],1u); atomicOr(crystal_stats[2],4u); atomicMax(crystal_stats[3],floatBitsToUint(float(abs(total-1.0)))); return float(radiance); }
        if(count==0 || remaining<=1e-20) return float(radiance);
        double pick=double(rnd(rng))*remaining, cumulative=0.0; int chosen=count-1;
        for(int j=0;j<count;j++) { cumulative+=powers[j]; if(pick<cumulative) { chosen=j; break; } }
        packet=crystal_normalize_packet(crystal_packet(boundary,mode_indices[chosen],combined[chosen]));
        region_state=mode_indices[chosen]<2?region_state:after; weight*=remaining;
        ray_direction=normalize(packet.poynting); point+=ray_direction*CRYSTAL_GEO_EPS*4.0;
        if(weight<double(THROUGHPUT_EPS)) return float(radiance);
    }
    atomicAdd(crystal_stats[1],1u);
    return float(radiance);
}
