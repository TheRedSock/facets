// Anisotropic single-scattering GGX dielectric interface.
// VNDF construction: Heitz, JCGT 7(4), 2018, https://jcgt.org/published/0007/04/01/
// Reflection/transmission and Smith weights: PBRT4, Dielectric BSDF.
// Strong roughness loses unresolved inter-microfacet scattering; it is not an
// accepted automatic frosting model. Do not compensate with arbitrary gain.
struct GemSurfaceData { vec4 slopes; vec4 direction; };
layout(set = 0, binding = 14, std430) readonly buffer Surfaces { GemSurfaceData surfaces[]; };

mat3 surface_frame(vec3 normal, vec3 polish_direction) {
	vec3 tangent = polish_direction - normal * dot(normal, polish_direction);
	vec3 other;
	if (dot(tangent, tangent) < 1e-10) { basis(normal, tangent, other); }
	else { tangent = normalize(tangent); other = cross(normal, tangent); }
	return mat3(tangent, other, normal);
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
