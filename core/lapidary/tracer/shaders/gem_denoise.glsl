#version 450
// Variance-guided, edge-avoiding a-trous reconstruction. No learned assets.
// References: Dammertz et al., HPG 2010; Schied et al., HPG 2017.
// This spatial filter is a controllable biased reconstruction, never the
// reference estimator. Original accumulations and sample moments stay intact.
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, std430) readonly buffer Input { vec4 input_pixels[]; };
layout(set = 0, binding = 1, std430) readonly buffer Guide { vec4 guides[]; };
layout(set = 0, binding = 2, std430) writeonly buffer Output { vec4 output_pixels[]; };
layout(set = 0, binding = 3, std430) readonly buffer Ballistic { vec4 ballistic_pixels[]; };
layout(push_constant, std430) uniform Parameters {
	ivec2 resolution;
	int step_size;
	float samples;
	float phi;
	float normal_power;
	vec2 padding;
} pc;

float variance(int index, vec4 value) {
	float n = max(value.w, 1.0);
	float mean = guides[index * 2 + 1].y / n;
	return max(0.0, guides[index * 2 + 1].x / n - mean * mean) / max(n - 1.0, 1.0);
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, pc.resolution))) { return; }
	int index = p.y * pc.resolution.x + p.x;
	vec4 center = input_pixels[index];
	if (pc.step_size == 0) {
		output_pixels[index] = vec4(center.xyz + ballistic_pixels[index].xyz, center.w);
		return;
	}
	float coverage = center.w / pc.samples;
	// Coverage is never blurred, and mixed silhouettes are resolved by the
	// output area filter. Geometry normals are accumulated over covered rays.
	if (coverage < 0.99) { output_pixels[index] = center; return; }
	vec3 normal = normalize(guides[index * 2].xyz);
	vec3 color = center.xyz / center.w;
	float var_center = variance(index, center);
	float kernel[5] = float[](1.0, 4.0, 6.0, 4.0, 1.0);
	vec3 sum = vec3(0.0);
	float weights = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 q = p + ivec2(x, y) * pc.step_size;
			if (any(lessThan(q, ivec2(0))) || any(greaterThanEqual(q, pc.resolution))) { continue; }
			int neighbor_index = q.y * pc.resolution.x + q.x;
			vec4 other = input_pixels[neighbor_index];
			if (other.w / pc.samples < 0.99) { continue; }
			vec3 other_normal = normalize(guides[neighbor_index * 2].xyz);
			float normal_weight = pow(max(dot(normal, other_normal), 0.0), pc.normal_power);
			vec3 other_color = other.xyz / other.w;
			float delta = color.y - other_color.y;
			float noise = pc.phi * pc.phi * (var_center + variance(neighbor_index, other)) + 1e-12;
			float weight = kernel[x + 2] * kernel[y + 2] * normal_weight * exp(-delta * delta / noise);
			sum += other_color * weight;
			weights += weight;
		}
	}
	output_pixels[index] = vec4((sum / max(weights, 1e-12)) * center.w, center.w);
}
