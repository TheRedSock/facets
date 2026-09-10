// Camera-path importance is a ROW of a Mueller product. Its basis refers to
// physical light propagation (-camera_ray_direction). Emitters are unpolarized.
// Scalar interfaces still preserve absorption polarization between segments.
// Only the full Mueller variant polarizes light at dielectric interfaces.
struct PathWeight {
	vec4 I;
	vec4 Q; vec4 U; vec4 V;
	vec3 axis;
};

PathWeight weight_initial(vec3 direction) {
	PathWeight w; w.I = vec4(1.0);
	w.Q = vec4(0.0); w.U = vec4(0.0); w.V = vec4(0.0);
	vec3 unused; basis(-direction, w.axis, unused);
	return w;
}

void weight_scale(inout PathWeight w, vec4 value) {
	w.I *= value;
	w.Q *= value; w.U *= value; w.V *= value;
}

void weight_depolarize(inout PathWeight w, vec3 direction) {
	// The scalar HG effective medium is explicitly an ideal depolarizer.
	// Polarized particle phase matrices are not inferred from HG g.
	w.Q = vec4(0.0); w.U = vec4(0.0); w.V = vec4(0.0);
	vec3 unused; basis(-direction, w.axis, unused);
}

#ifdef POLARIZED_TRANSPORT
mat4 polarized_diattenuator(float tx, float ty) {
	float a = 0.5 * (tx + ty), b = 0.5 * (tx - ty), c = sqrt(max(0.0, tx * ty));
	return mat4(a,b,0,0, b,a,0,0, 0,0,c,0, 0,0,0,c);
}

// ni/nt convention. Mueller axes are perpendicular to the incidence plane.
mat4 polarized_dielectric(float ci, float eta, bool transmission) {
	if (abs(eta - 1.0) < 1e-7) { return mat4(transmission ? 1.0 : 0.0); }
	float sin2 = eta * eta * max(0.0, 1.0 - ci * ci);
	if (sin2 >= 1.0) {
		if (transmission) { return mat4(0.0); }
		float gamma = sqrt(sin2 - 1.0);
		float phase = -2.0 * atan(eta * gamma, ci) + 2.0 * atan(gamma, eta * ci);
		float c = cos(phase), s = sin(phase);
		return mat4(1,0,0,0, 0,1,0,0, 0,0,c,-s, 0,0,s,c);
	}
	float ct = sqrt(1.0 - sin2);
	float rs = (eta * ci - ct) / max(eta * ci + ct, 1e-20);
	float rp = (ci - eta * ct) / max(ci + eta * ct, 1e-20);
	if (transmission) { return polarized_diattenuator(1.0-rs*rs, 1.0-rp*rp); }
	mat4 result = polarized_diattenuator(rs*rs, rp*rp);
	result[2][2] = rs * rp; result[3][3] = rs * rp;
	return result;
}
#endif

// Persistent axial dichroism for an isotropic REAL refractive index. This is
// the weak-loss transverse absorption tensor, not anisotropic refraction.
PathWeight absorption_weight(PathWeight w, vec3 camera_direction, vec3 optic_axis,
        vec4 ordinary_transmittance, vec4 extraordinary_transmittance) {
    vec3 propagation=-camera_direction;
    vec3 axis=cross(optic_axis,propagation);
    axis=dot(axis,axis)>1e-12?normalize(axis):w.axis;
    float c=clamp(dot(axis,w.axis),-1.0,1.0);
    float s=dot(propagation,cross(axis,w.axis));
    vec4 Q=w.Q*(c*c-s*s)-w.U*(2.0*c*s);
    vec4 U=w.Q*(2.0*c*s)+w.U*(c*c-s*s);
    vec4 a=0.5*(ordinary_transmittance+extraordinary_transmittance);
    vec4 b=0.5*(ordinary_transmittance-extraordinary_transmittance);
    vec4 coherence=sqrt(max(vec4(0),ordinary_transmittance*extraordinary_transmittance));
    w.Q=b*w.I+a*Q;
    w.I=a*w.I+b*Q;
    w.U=coherence*U; w.V*=coherence;
    w.axis=axis;
    return w;
}

PathWeight interface_weight(PathWeight w, vec3 previous_dir, vec3 next_dir,
		vec3 normal, vec4 index_before, vec4 index_after, bool transmission,
		float geometry_weight, vec4 scalar_weight) {
	vec3 outgoing = -previous_dir, incident = -next_dir;
	vec3 out_axis = cross(normal, outgoing), in_axis = cross(normal, incident);
	if (dot(out_axis,out_axis) < 1e-12 || dot(in_axis,in_axis) < 1e-12) {
		out_axis = w.axis;
		in_axis = normalize(w.axis - incident * dot(incident,w.axis));
	} else { out_axis = normalize(out_axis); in_axis = normalize(in_axis); }
	// Row importance in the outgoing natural Fresnel frame: W * R(natural→old).
	float c = clamp(dot(out_axis, w.axis), -1.0, 1.0);
	float s = dot(outgoing, cross(out_axis, w.axis));
	vec4 Q = w.Q * (c*c-s*s) - w.U * (2.0*c*s);
	vec4 U = w.Q * (2.0*c*s) + w.U * (c*c-s*s);
#ifdef POLARIZED_TRANSPORT
	float ci = clamp(abs(dot(transmission ? incident : outgoing, normal)), 0.0, 1.0);
	for (int channel=0; channel<4; channel++) {
		float eta = transmission ? index_after[channel]/index_before[channel] : index_before[channel]/index_after[channel];
		mat4 m = polarized_dielectric(ci, eta, transmission);
		vec4 value = transpose(m) * vec4(w.I[channel], Q[channel], U[channel], w.V[channel]);
		float radiance_eta = index_before[channel]/index_after[channel];
		value *= geometry_weight * (transmission ? radiance_eta*radiance_eta : 1.0);
		w.I[channel]=value.x; w.Q[channel]=value.y; w.U[channel]=value.z; w.V[channel]=value.w;
	}
#else
    // Scalar Fresnel is an approximation, but an interface must not erase
    // polarization accumulated through selective bulk absorption. Rotate
    // between incidence frames and retain both channels/coherence.
    w.Q=Q;w.U=U;
    weight_scale(w,scalar_weight);
#endif
    w.axis=in_axis;
	return w;
}
