shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 gem_color : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform vec4 depth_tint : source_color = vec4(0.25, 0.4, 0.7, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.72;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.03;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.45;
uniform float fire_strength : hint_range(0.0, 1.5) = 0.18;
uniform float emission_strength : hint_range(0.0, 1.5) = 0.15;
uniform float absorption_strength : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndotv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.0);
	float depth_mix = clamp(1.0 - max(n.z, 0.0), 0.0, 1.0);

	vec3 base = mix(gem_color.rgb * (1.0 - absorption_strength), gem_color.rgb, 1.0 - depth_mix * 0.45);
	vec3 fire = vec3(fresnel, fresnel * 0.72, fresnel * 1.15) * fire_strength;
	vec3 albedo = clamp(base + fire * max(fresnel - 0.3, 0.0), 0.0, 1.0);

	if (!FRONT_FACING) {
		albedo = mix(albedo, depth_tint.rgb, 0.35 + depth_mix * 0.25);
	}

	ALBEDO = albedo;
	METALLIC = 0.0;
	ROUGHNESS = roughness_value;
	SPECULAR = 1.0;
	RIM = rim_strength;
	RIM_TINT = 0.45;
	EMISSION = rim_color.rgb * fresnel * emission_strength + fire * 0.65;
	ALPHA = alpha;
}
