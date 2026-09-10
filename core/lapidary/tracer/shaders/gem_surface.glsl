// Anisotropic single-scattering GGX dielectric interface.
// VNDF construction: Heitz, JCGT 7(4), 2018, https://jcgt.org/published/0007/04/01/
// Reflection/transmission and Smith weights: PBRT4, Dielectric BSDF.
// Strong roughness loses unresolved inter-microfacet scattering; it is not an
// accepted automatic frosting model. Do not compensate with arbitrary gain.
struct GemSurfaceData { vec4 slopes; vec4 direction; };
layout(set = 0, binding = 14, std430) readonly buffer Surfaces { GemSurfaceData surfaces[]; };
struct FinishField { vec4 center_strength; vec4 radii; vec4 rotation; vec4 slopes; vec4 direction; };
layout(set = 0, binding = 20, std430) readonly buffer FinishFields { FinishField finish_fields[]; };

mat3 surface_frame(vec3 normal, vec3 polish_direction) {
	vec3 tangent = polish_direction - normal * dot(normal, polish_direction);
	vec3 other;
	if (dot(tangent, tangent) < 1e-10) { basis(normal, tangent, other); }
	else { tangent = normalize(tangent); other = cross(normal, tangent); }
	return mat3(tangent, other, normal);
}

// Interpolate a symmetric GGX slope-shape matrix in the tangent plane.
// This is an authored spatially varying NDF, not variance addition or BSDF mixing.
GemSurfaceData local_finish(GemSurfaceData finish, vec3 point_mm, vec3 normal) {
    int count = int(finish.direction.w);
    if (count == 0) { return finish; }
    mat3 base = surface_frame(normal, finish.direction.xyz);
    vec3 shape = vec3(finish.slopes.x*finish.slopes.x, 0.0, finish.slopes.y*finish.slopes.y);
    vec2 eigenvalues = finish.slopes.xy*finish.slopes.xy;
    vec2 eigenaxis = vec2(1.0,0.0);
    bool changed = false;
    for (int i=0; i<count; i++) {
        FinishField field = finish_fields[int(finish.slopes.w)+i];
        vec3 p = quat_rot(quat_conj(field.rotation), point_mm-field.center_strength.xyz) / field.radii.xyz;
        float density = max(0.0, 1.0-dot(p,p));
        float weight = field.center_strength.w*density*density*density;
        if (weight <= 0.0) { continue; }
        mat3 target = surface_frame(normal, field.direction.xyz);
        vec2 axis = vec2(dot(target[0],base[0]), dot(target[0],base[1]));
        float a = field.slopes.x*field.slopes.x, b = field.slopes.y*field.slopes.y;
        vec3 metric = vec3(a*axis.x*axis.x+b*axis.y*axis.y, (a-b)*axis.x*axis.y,
                           a*axis.y*axis.y+b*axis.x*axis.x);
        // det(sum vv^T) as positive squared cross products. Computing det
        // from rounded matrix entries loses the narrow lobe at high anisotropy.
        float c = dot(eigenaxis,axis), s = eigenaxis.x*axis.y-eigenaxis.y*axis.x;
        float mixed = eigenvalues.x*(a*s*s+b*c*c)+eigenvalues.y*(a*c*c+b*s*s);
        float determinant = (1.0-weight)*(1.0-weight)*eigenvalues.x*eigenvalues.y
            + weight*weight*a*b + weight*(1.0-weight)*mixed;
        shape = mix(shape, metric, weight);
        float difference = shape.x-shape.z;
        float gap = length(vec2(difference,2.0*shape.y));
        float angle = gap > 1e-12 ? 0.5*atan(2.0*shape.y,difference) : 0.0;
        float major = 0.5*(shape.x+shape.z+gap);
        eigenvalues = vec2(major, major>0.0 ? determinant/major : 0.0);
        eigenaxis = vec2(cos(angle),sin(angle));
        changed = true;
    }
    if (!changed) { return finish; }
    finish.slopes.xy = sqrt(max(eigenvalues,vec2(0.0)));
    finish.direction.xyz = eigenaxis.x*base[0]+eigenaxis.y*base[1];
    return finish;
}

vec3 visible_ggx(vec3 outgoing, vec2 alpha, vec2 u) {
	vec3 stretched = normalize(vec3(outgoing.xy * alpha, outgoing.z));
	float radial2 = dot(stretched.xy, stretched.xy);
	vec3 horizontal = radial2 > 1e-12 ? vec3(-stretched.y, stretched.x, 0.0) / sqrt(radial2) : vec3(1, 0, 0);
	vec3 vertical = cross(stretched, horizontal);
	float radius = sqrt(u.x), angle = TAU * u.y;
	vec2 disk = radius * vec2(cos(angle), sin(angle));
	float blend = 0.5 * (1.0 + stretched.z);
	disk.y = mix(sqrt(max(0.0, 1.0 - disk.x * disk.x)), disk.y, blend);
	vec3 hemisphere = horizontal * disk.x + vertical * disk.y + stretched * sqrt(max(0.0, 1.0 - dot(disk, disk)));
	return normalize(vec3(hemisphere.xy * alpha, max(1e-9, hemisphere.z)));
}

float ggx_lambda(vec3 direction, vec2 alpha) {
	vec2 slope = direction.xy * alpha;
	return 0.5 * (sqrt(1.0 + dot(slope, slope) / max(direction.z * direction.z, 1e-16)) - 1.0);
}

float surface_weight(vec3 outgoing, vec3 incoming, vec2 alpha) {
	float lambda_out = ggx_lambda(outgoing, alpha);
	// The VNDF proposal cancels D and the projected-normal Jacobian. What
	// remains is G2/G1, for both reflection and refraction, never a normal jitter.
	return (1.0 + lambda_out) / (1.0 + lambda_out + ggx_lambda(incoming, alpha));
}
