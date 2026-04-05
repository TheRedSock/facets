shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D texture_a : source_color;
uniform sampler2D texture_b : source_color;
uniform sampler2D texture_c : source_color;
uniform sampler2D texture_d : source_color;
uniform vec4 weights = vec4(0.0);
uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float outline_width_pixels = 1.0;
uniform vec2 texture_size_px = vec2(112.0, 112.0);

vec4 sample_blended(vec2 uv) {
	vec4 sample_a = texture(texture_a, uv);
	vec4 sample_b = texture(texture_b, uv);
	vec4 sample_c = texture(texture_c, uv);
	vec4 sample_d = texture(texture_d, uv);
	vec4 blended = sample_a * weights.x;
	blended += sample_b * weights.y;
	blended += sample_c * weights.z;
	blended += sample_d * weights.w;
	return vec4(blended.rgb, clamp(blended.a, 0.0, 1.0));
}

void fragment() {
	vec4 blended = sample_blended(UV);
	if (!outline_enabled) {
		COLOR = blended;
	} else {
		vec2 texel = 1.0 / max(texture_size_px, vec2(1.0));
		vec2 offset = texel * max(outline_width_pixels, 0.75);
		float center_alpha = blended.a;
		float neighbor_alpha = 0.0;
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(offset.x, 0.0)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(-offset.x, 0.0)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(0.0, offset.y)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(0.0, -offset.y)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(offset.x, offset.y)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(-offset.x, offset.y)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(offset.x, -offset.y)).a);
		neighbor_alpha = max(neighbor_alpha, sample_blended(UV + vec2(-offset.x, -offset.y)).a);

		float outline_alpha = clamp((neighbor_alpha - center_alpha) * outline_color.a, 0.0, 1.0);
		float final_alpha = max(center_alpha, outline_alpha);
		vec3 final_rgb = blended.rgb;
		if (outline_alpha > 0.0001) {
			float inside_mix = clamp(center_alpha * 3.5, 0.0, 1.0);
			final_rgb = mix(outline_color.rgb, final_rgb, inside_mix);
		}
		COLOR = vec4(final_rgb, final_alpha);
	}
}
