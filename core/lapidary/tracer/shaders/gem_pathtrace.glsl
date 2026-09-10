#version 450
// Spectral transport over convex half-spaces or procedural closed meshes.
// Four stratified wavelengths; quality policies select shared or independent
// geometry. Repeated volume scattering is the production estimator. Optional
// reconstruction filters only the volume residual against zero-scatter light.
// See KERNEL_CONTRACT.md for layouts and physical limitations.

#include "gem_common.glsl"
#include "gem_mesh.glsl"
#include "gem_surface.glsl"
#include "gem_volume.glsl"
#include "gem_polarization.glsl"

layout(local_size_x = 8, local_size_y = 8) in;

layout(push_constant, std430) uniform Params {
	ivec2 resolution;     // 0
	uint sample_base;     // 8   global sample index of this dispatch's first sample
	uint spp;             // 12
	uint seed;            // 16
	uint max_bounces;     // 20
	uint flags;           // 24  bit0 dispersion_split, bit1 birefringence, bit2 volume, bit4 fluorescence
	uint light_count;     // 28
	ivec2 grid;           // 32  cols, rows
	ivec2 cell_px;        // 40
	float bg_zenith;      // 48
	float bg_horizon;     // 52
	float bg_below;       // 56
	float spectral_norm;  // 60
	float rad_clamp;      // 64  per-sample radiance ceiling (firefly control; rung policy)
	int row_origin;       // 68 first image row of this dispatch
	float bg_spectrum;    // 72 background spectrum table offset
	float throughput_epsilon; // 76 numerical path termination threshold
} pc;


layout(set = 0, binding = 8, std430) buffer Guides { vec4 guides[]; };
layout(set = 0, binding = 9, std430) buffer Ballistic { vec4 ballistic_pixels[]; };
layout(set = 0, binding = 10, std430) buffer Residual { vec4 residual_pixels[]; };

const float WL_MIN = 380.0;
const float WL_RANGE = 400.0;
#define THROUGHPUT_EPS pc.throughput_epsilon

#define FLAG_DISPERSION  ((pc.flags & 1u) != 0u)
#define FLAG_BIREF       ((pc.flags & 2u) != 0u)
#define FLAG_VOLUME      ((pc.flags & 4u) != 0u)
#define FLAG_FLUOR       ((pc.flags & 16u) != 0u)

// Polarisation modes for Beer-Lambert.
const int POL_UNPOL = 0;
const int POL_O = 1;
const int POL_K = 2;

// ---------------------------------------------------------------- phase function
// Henyey-Greenstein direction from stratified (u1,u2).
vec3 hg_sample_u(vec3 dir, float g, vec2 u) {
	float ct;
	if (abs(g) < 0.01) {
		ct = 1.0 - 2.0 * u.x;
	} else {
		float sq = (1.0 - g * g) / (1.0 - g + 2.0 * g * u.x);
		ct = (1.0 + g * g - sq * sq) / (2.0 * g);
	}
	float st = sqrt(max(0.0, 1.0 - ct * ct));
	float phi = TAU * u.y;
	vec3 t1, t2;
	basis(dir, t1, t2);
	return normalize(t1 * (st * cos(phi)) + t2 * (st * sin(phi)) + dir * ct);
}

// ---------------------------------------------------------------- environment
vec4 env_radiance(vec3 dir, vec4 wl, float rig_yaw, vec4 role_mult, float fp) {
	return env_radiance_ex(dir, wl, rig_yaw, role_mult, fp, true,
		vec4(pc.bg_zenith, pc.bg_horizon, pc.bg_below, pc.bg_spectrum), pc.light_count);
}

// ---------------------------------------------------------------- zoning / absorption
float zoning_column(Stone st, vec3 position, vec3 direction, float distance) {
	float contrast = st.scatter_zone.w;
	if (contrast == 0.0) { return distance; }
	float half_phase = 0.5 * distance * dot(direction, st.zone_axis_phase.xyz) * st.scatter_zone.z * PI;
	float sinc = abs(half_phase) < 0.001 ? 1.0 - half_phase * half_phase / 6.0 : sin(half_phase) / half_phase;
	float mid_phase = dot(position + direction * (distance * 0.5), st.zone_axis_phase.xyz) * st.scatter_zone.z * PI + st.zone_axis_phase.w;
	return max(0.0, distance * (1.0 + contrast * sin(mid_phase) * sinc));
}

// Beer-Lambert. pol_mode: UNPOL = 0.5 To + 0.5 Tk; O = pure o-ray; K = mixed k-ray.
// alpha_k = cos^2(phi) alpha_o + sin^2(phi) alpha_e  (GIA G&G Spring 2021).
void segment_beer(Stone st, vec3 pos, vec3 dir, float t, int a_off, bool has_eray, vec4 wl,
        out vec4 ordinary, out vec4 extraordinary) {
	float size_mm = st.sell_b_size.w;
	float L = (zoning_column(st, pos, dir, t) + field_columns(st, pos, dir, t).x) * st.misc.y * size_mm;
	if (!has_eray) {
		vec4 alpha = vec4(absorb_at(a_off, wl.x), absorb_at(a_off, wl.y),
			absorb_at(a_off, wl.z), absorb_at(a_off, wl.w));
		ordinary=exp(-alpha*L); extraordinary=ordinary;
		return;
	}
	float ca = abs(dot(dir, st.optic_fluor.xyz));
	float c2 = clamp(ca * ca, 0.0, 1.0);
	float s2 = 1.0 - c2;
	vec4 alpha_o, alpha_e, alpha_k;
	for (int i = 0; i < 4; i++) {
		alpha_o[i] = absorb_at(a_off, wl[i]);
		alpha_e[i] = absorb_at(a_off + 401, wl[i]);
		alpha_k[i] = c2 * alpha_o[i] + s2 * alpha_e[i];
	}
	ordinary=exp(-alpha_o*L); extraordinary=exp(-alpha_k*L);
}

vec4 segment_att(Stone st, vec3 pos, vec3 dir, float t, int a_off, bool has_eray, vec4 wl, int pol_mode) {
    vec4 ordinary,extraordinary;
    segment_beer(st,pos,dir,t,a_off,has_eray,wl,ordinary,extraordinary);
    if(pol_mode==POL_O) return ordinary;
    if(pol_mode==POL_K) return extraordinary;
    return 0.5*(ordinary+extraordinary);
}

PathWeight segment_weight(PathWeight w, Stone st, vec3 pos, vec3 dir, float t, vec4 wl, int pol_mode) {
#ifdef POLARIZED_TRANSPORT
    vec4 ordinary,extraordinary;
    segment_beer(st,pos,dir,t,st.ranges1.x,(st.ranges1.y&1)!=0,wl,ordinary,extraordinary);
    return absorption_weight(w,dir,st.optic_fluor.xyz,ordinary,extraordinary);
#else
    weight_scale(w,segment_att(st,pos,dir,t,st.ranges1.x,(st.ranges1.y&1)!=0,wl,pol_mode));
    return w;
#endif
}

// ---------------------------------------------------------------- surfaces
// Specular dielectric exit at a known plane (segment attenuation already applied).
void surface_exit_at(Stone st, int exit_plane, vec4 wl, vec4 n_wl, float n_geom, vec4 q,
		float rig_yaw, vec4 role_mult, float fp_env,
		inout vec3 pos, inout vec3 dir, inout vec4 throughput, inout vec4 radiance) {
	vec3 en = planes[exit_plane].n_d.xyz;
	float ci = clamp(dot(dir, en), 0.0, 1.0);
	float s2o = n_geom * n_geom * (1.0 - ci * ci);
	if (s2o < 1.0) {
		vec4 r_exit = vec4(
			fresnel_diel(ci, n_wl.x), fresnel_diel(ci, n_wl.y),
			fresnel_diel(ci, n_wl.z), fresnel_diel(ci, n_wl.w));
		float cto = sqrt(1.0 - s2o);
		vec3 dout = normalize(n_geom * dir - (n_geom * ci - cto) * en);
		radiance += throughput * (vec4(1.0) - r_exit)
			* env_radiance(quat_rot(q, dout), wl, rig_yaw, role_mult, fp_env);
		throughput *= r_exit;
	}
	dir = normalize(reflect(dir, en));
	pos -= en * (T_EPS * 4.0);
}

// General closed-mesh transport. Air segments can hit the same specimen
// again. Deterministic exit splitting is used only when visibility proves
// the escaping ray reaches the environment; coupled branches use roulette.
vec4 medium_index(int material, vec4 wl) {
	if (material < 0) { return vec4(1.0); }
	return principal_indices(stones[material], wl, false);
}

float geometry_index(int material, vec4 indices, vec4 wl, int wavelength, bool extraordinary, vec3 direction) {
	float ordinary = wavelength >= 0 ? indices[wavelength] : 0.5 * (indices.y + indices.z);
	if (material < 0 || !extraordinary) { return ordinary; }
	Stone m = stones[material];
	vec4 extra = principal_indices(m, wl, true);
	float ne = wavelength >= 0 ? extra[wavelength] : 0.5 * (extra.y + extra.z);
	return n_e_phi(ordinary, ne, abs(dot(direction, m.optic_fluor.xyz)));
}

vec4 trace_mesh_path(Stone st, vec3 pos, vec3 dir, vec4 wl, int wavelength, bool extraordinary,
		vec4 q, float rig_yaw, vec4 roles, int pol_mode, bool use_volume, inout uint rng) {
	PathWeight throughput = weight_initial(dir);
	vec4 radiance = vec4(0.0);
	uvec4 region_state = uvec4(0u);
	for (uint bounce = 0u; bounce < pc.max_bounces; bounce++) {
		float distance; int triangle;
		int before_medium = region_medium(st, region_state);
		if (!boundary_hit(st, pos, dir, distance, triangle)) {
			if (before_medium < 0) { radiance += throughput.I * env_radiance(quat_rot(q, dir), wl, rig_yaw, roles, 0.0); }
			break;
		}
		if (before_medium >= 0) {
			Stone medium = stones[before_medium];
			float free_flight = use_volume ? scatter_distance(medium, pos, dir, distance, -log(max(1e-7, 1.0 - rnd(rng)))) : INF;
			float segment = min(free_flight, distance);
			throughput=segment_weight(throughput,medium,pos,dir,segment,wl,pol_mode);
			if (free_flight < distance) {
				pos += dir * free_flight;
				dir = hg_sample_u(dir, medium.scatter_zone.y, vec2(rnd(rng), rnd(rng)));
				weight_depolarize(throughput, dir);
				continue;
			}
			if (!use_volume && FLAG_VOLUME) { weight_scale(throughput, vec4(exp(-scattering_depth(medium, pos, dir, distance)))); }
		}
		pos += dir * distance;
		uvec4 after = cross_region(st, region_state, triangle, pos, dir);
		int after_medium = region_medium(st, after);
		if (before_medium == after_medium) {
			region_state = after;
			pos += dir * T_EPS * 4.0;
			continue;
		}
		vec3 normal = boundary_normal(st, triangle, pos);
		vec3 facing = dot(dir, normal) < 0.0 ? normal : -normal;
		int region = triangle < 0 || st.ranges1.z == 0 ? 0 : triangles[triangle].meta.w;
		GemSurfaceData finish = surfaces[st.ranges1.w + region];
		bool rough = max(finish.slopes.x, finish.slopes.y) >= 0.0001;
		vec4 index_before = medium_index(before_medium, wl), index_after = medium_index(after_medium, wl);
		float eta = geometry_index(before_medium, index_before, wl, wavelength, extraordinary, dir)
			/ geometry_index(after_medium, index_after, wl, wavelength, extraordinary, dir);
		// An index-matched interface is invisible, regardless of its finish.
		rough = rough && abs(eta - 1.0) > 1e-6;
		mat3 frame = surface_frame(facing, finish.direction.xyz);
		vec3 outgoing = transpose(frame) * -dir;
		vec2 alpha = max(finish.slopes.xy, vec2(0.0001));
		vec3 micro_normal = rough ? frame * visible_ggx(outgoing, alpha, vec2(rnd(rng), rnd(rng))) : facing;
		float ci = clamp(-dot(dir, micro_normal), 0.0, 1.0);
		float reflectance = fresnel_diel(ci, eta);
		vec4 R;
		for (int channel = 0; channel < 4; channel++) { R[channel] = fresnel_diel(ci, index_before[channel] / index_after[channel]); }
		vec3 reflected = normalize(reflect(dir, micro_normal));
		vec3 transmitted = reflectance < 1.0 ? normalize(refract(dir, micro_normal, eta)) : -facing;
		float reflect_geometry = dot(reflected, facing) > 0.0 ? (rough ? surface_weight(outgoing, transpose(frame) * reflected, alpha) : 1.0) : 0.0;
		float transmit_geometry = reflectance < 1.0 && dot(transmitted, facing) < 0.0 ? (rough ? surface_weight(outgoing, transpose(frame) * transmitted, alpha) : 1.0) : 0.0;
		vec4 eta_radiance = index_before / index_after;
		vec4 weight_r = R * reflect_geometry;
		vec4 weight_t = (vec4(1.0) - R) * transmit_geometry * eta_radiance * eta_radiance;
		PathWeight reflected_weight = interface_weight(throughput, dir, reflected, micro_normal, index_before, index_after, false, reflect_geometry, weight_r);
		PathWeight transmitted_weight = interface_weight(throughput, dir, transmitted, micro_normal, index_before, index_after, true, transmit_geometry, weight_t);
		if (reflectance >= 1.0) {
			throughput = reflected_weight;
			dir = reflected;
		} else {
			bool escape_reflect = before_medium < 0;
			bool can_escape = escape_reflect || after_medium < 0;
			vec3 escape_direction = escape_reflect ? reflected : transmitted;
			uvec4 escape_active = escape_reflect ? region_state : after;
			float next_distance; int next_triangle;
			bool obstructed = !can_escape || physical_hit(st, pos + escape_direction * T_EPS * 4.0, escape_direction, escape_active, next_distance, next_triangle);
			if (!obstructed) {
				PathWeight escape_weight = escape_reflect ? reflected_weight : transmitted_weight;
				radiance += escape_weight.I * env_radiance(quat_rot(q, escape_direction), wl, rig_yaw, roles, 0.0);
				throughput = escape_reflect ? transmitted_weight : reflected_weight;
				dir = escape_reflect ? transmitted : reflected;
				if (escape_reflect) { region_state = after; }
			} else if (rnd(rng) < reflectance) {
				throughput = reflected_weight;
				weight_scale(throughput, vec4(1.0 / max(reflectance, 1e-7)));
				dir = reflected;
			} else {
				throughput = transmitted_weight;
				weight_scale(throughput, vec4(1.0 / max(1.0 - reflectance, 1e-7)));
				dir = transmitted;
				region_state = after;
			}
		}
		pos += dir * T_EPS * 4.0;
		if (max(max(throughput.I.x, throughput.I.y), max(throughput.I.z, throughput.I.w)) < THROUGHPUT_EPS) { break; }
	}
	return radiance;
}

#ifdef CRYSTAL_TRANSPORT
#include "gem_crystal_path.glsl"
#endif

// ================================================================= main
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy) + ivec2(0, pc.row_origin);
	if (pix.x >= pc.resolution.x || pix.y >= pc.resolution.y) { return; }
	uint idx = uint(pix.y) * uint(pc.resolution.x) + uint(pix.x);

	int col = min(pix.x / pc.cell_px.x, pc.grid.x - 1);
	int row = min(pix.y / pc.cell_px.y, pc.grid.y - 1);
	int inst_idx = row * pc.grid.x + col;
	Inst inst = insts[inst_idx];
	Stone st = stones[inst.which.x];
	vec2 cell_uv = vec2(pix - ivec2(col, row) * pc.cell_px) / vec2(pc.cell_px);

	// Fixed per-pixel CP rotation (independent of dispatch); PCG stream per dispatch.
	uint prot = (uint(pix.x) * 1973u + uint(pix.y) * 9277u + pc.seed * 30011u) | 1u;
	vec2 pix_rot = vec2(rnd(prot), rnd(prot));
	uint rng = (uint(pix.x) * 1973u + uint(pix.y) * 9277u + pc.sample_base * 26699u + pc.seed * 30011u) | 1u;
	pcg(rng);
	vec4 q = inst.quat;
	vec4 qc = quat_conj(q);
	vec4 role_mult = vec4(inst.rig.z, inst.rig.w, inst.rig2.x, inst.rig2.y);
	float rig_yaw = inst.rig.x;
	float ortho_half = inst.rig.y;
	int p_off = st.ranges0.x;
	int p_cnt = st.ranges0.y;
	int a_off = st.ranges1.x;
	bool has_eray = (st.ranges1.y & 1) != 0;
	float size_mm = st.sell_b_size.w;
	float sigma_h = FLAG_VOLUME ? st.scatter_zone.x * size_mm : 0.0;
	float hg_g = st.scatter_zone.y;
	bool reconstruct_volume = FLAG_VOLUME && (sigma_h > 0.0 || st.misc.z > 0.0);
	bool reconstruct_surface = st.misc.w > 0.0;
	bool boundary_transport = st.ranges1.z != 0 || reconstruct_surface;
#ifdef POLARIZED_TRANSPORT
	boundary_transport = true;
#endif

	vec3 total_xyz = vec3(0.0);
	vec3 total_ballistic = vec3(0.0);
	vec3 total_residual = vec3(0.0);
	float total_cov = 0.0;
	vec4 geometry_sum = vec4(0.0);
	vec2 moment_sum = vec2(0.0);
	float min_facet = pc.sample_base == 0u ? 1e20 : guides[idx * 2u + 1u].z;
	float max_facet = pc.sample_base == 0u ? -1.0 : guides[idx * 2u + 1u].w;

	for (uint s = 0u; s < pc.spp; s++) {
		uint n = pc.sample_base + s;
		rng = (uint(pix.x) * 1973u + uint(pix.y) * 9277u + n * 26699u + pc.seed * 30011u) | 1u;
		pcg(rng);
		float xi = qmc(n, 2u, pix_rot);
		vec4 wl = WL_MIN + (vec4(0.0, 1.0, 2.0, 3.0) + xi) * (WL_RANGE / 4.0);
		vec4 n_wl = principal_indices(st, wl, false);

		vec2 r2 = qmc2(n, 0u, 1u, pix_rot);
		vec2 ndc = (cell_uv + (r2 - 0.5) / vec2(pc.cell_px)) * 2.0 - 1.0;
		vec3 ro_w = vec3(ndc.x * ortho_half, -ndc.y * ortho_half, inst.rig2.z);
		vec3 ro = quat_rot(qc, ro_w);
		vec3 rd = quat_rot(qc, vec3(0.0, 0.0, -1.0));

		float t_near;
		int entry_plane;
		if (!body_entry(st, ro, rd, t_near, entry_plane)) { continue; }
		total_cov += 1.0;

		vec3 p_hit = ro + rd * t_near;
		vec3 n_entry = body_normal(st, entry_plane, p_hit);
		if (dot(rd, n_entry) > 0.0) { n_entry = -n_entry; }
		geometry_sum += vec4(quat_rot(q, n_entry), t_near);
		min_facet = min(min_facet, float(entry_plane));
		max_facet = max(max_facet, float(entry_plane));
		float cos_i = clamp(-dot(rd, n_entry), 0.0, 1.0);

		vec4 radiance = vec4(0.0);
#ifdef CRYSTAL_TRANSPORT
		for(int channel=0;channel<4;channel++) {
			for(int pol=0;pol<2;pol++) radiance[channel]+=0.5*trace_crystal_probe(st,ro,rd,wl[channel],pol,q,rig_yaw,role_mult,rng);
		}
		vec4 ballistic=radiance;
#else

		vec4 r_surf = vec4(
			fresnel_diel(cos_i, 1.0 / n_wl.x), fresnel_diel(cos_i, 1.0 / n_wl.y),
			fresnel_diel(cos_i, 1.0 / n_wl.z), fresnel_diel(cos_i, 1.0 / n_wl.w));
		if (!boundary_transport) { radiance += r_surf * env_radiance(quat_rot(q, reflect(rd, n_entry)), wl, rig_yaw, role_mult, 0.0); }

		vec4 ballistic = radiance;
		bool disp = FLAG_DISPERSION && ((pc.flags & 32u) != 0u || (st.ranges1.y & 2) != 0);
		bool biref = FLAG_BIREF && abs(st.sell_c_biref.w) > 0.015;
		int n_passes = (disp ? 4 : 1) * (biref ? 2 : 1);

		// Structured dimensions shared by all passes of this sample.
		float tau_free0 = -log(max(1e-6, 1.0 - qmc(n, 3u, pix_rot)));
		vec2 u_scat = qmc2(n, 4u, 5u, pix_rot);

		for (int pass_i = 0; pass_i < n_passes; pass_i++) {
			int wl_i = disp ? (pass_i % 4) : -1;
			bool eray = biref && (pass_i >= n_passes / 2);
			vec4 mask = disp ? vec4(wl_i == 0 ? 1.0 : 0.0, wl_i == 1 ? 1.0 : 0.0, wl_i == 2 ? 1.0 : 0.0, wl_i == 3 ? 1.0 : 0.0) : vec4(1.0);
			float pass_w = (biref ? 0.5 : 1.0);
			// Shared geometry uses a mid-spectrum index when not splitting.
			float n_o = disp ? n_wl[wl_i] : 0.5 * (n_wl.y + n_wl.z);
			float ca_in = abs(dot(rd, st.optic_fluor.xyz));
			vec4 ne_wl = eray ? principal_indices(st, wl, true) : n_wl;
			float ne = disp ? ne_wl[wl_i] : 0.5 * (ne_wl.y + ne_wl.z);
			float n_geom = eray ? n_e_phi(n_o, ne, ca_in) : n_o;
			int pol_mode = biref ? (eray ? POL_K : POL_O) : POL_UNPOL;

			if (boundary_transport) {
				radiance += mask * pass_w * trace_mesh_path(st, ro, rd, wl, wl_i, eray, q, rig_yaw, role_mult, pol_mode, FLAG_VOLUME, rng);
				if (reconstruct_volume && !reconstruct_surface) { ballistic += mask * pass_w * trace_mesh_path(st, ro, rd, wl, wl_i, eray, q, rig_yaw, role_mult, pol_mode, false, rng); }
				continue;
			}
			float eta_in = 1.0 / n_geom;
			float s2 = eta_in * eta_in * (1.0 - cos_i * cos_i);
			if (s2 >= 1.0) { continue; }
			float ct = sqrt(1.0 - s2);
			vec3 dir = normalize(eta_in * rd + (eta_in * cos_i - ct) * n_entry);
			vec4 throughput = (vec4(1.0) - r_surf) * mask * pass_w;
			vec3 pos = p_hit - n_entry * (T_EPS * 4.0);
			// Deterministic zero-scattering contribution, used as a control
			// image for reconstruction. Only the residual gets filtered, so
			// sharp internal reflections cannot be mistaken for volume noise.
			if (reconstruct_volume) {
				vec3 clear_pos = pos, clear_dir = dir;
				vec4 clear_throughput = throughput;
				for (uint hit = 0u; hit < pc.max_bounces; hit++) {
					float distance;
					int face;
					hull_exit(p_off, p_cnt, clear_pos, clear_dir, distance, face);
					if (distance >= INF * 0.5) { break; }
					clear_throughput *= segment_att(st, clear_pos, clear_dir, distance, a_off, has_eray, wl, pol_mode)
						* exp(-scattering_depth(st, clear_pos, clear_dir, distance));
					clear_pos += clear_dir * distance;
					surface_exit_at(st, face, wl, n_wl, n_geom, q, rig_yaw, role_mult, 0.0,
						clear_pos, clear_dir, clear_throughput, ballistic);
					if (max(max(clear_throughput.x, clear_throughput.y), max(clear_throughput.z, clear_throughput.w)) < THROUGHPUT_EPS) { break; }
				}
			}
			float tau_free = tau_free0;
			int scatter_events = 0;
			for (uint bounce = 0u; bounce < pc.max_bounces; bounce++) {
				float distance; int face;
				hull_exit(p_off, p_cnt, pos, dir, distance, face);
				if (distance >= INF * 0.5) { break; }
				// Preserve the low-variance convex path and its stratified first event.
				float collision = FLAG_VOLUME ? scatter_distance(st, pos, dir, distance, tau_free) : INF;
				float segment = min(collision, distance);
				throughput *= segment_att(st, pos, dir, segment, a_off, has_eray, wl, pol_mode);
				float traveled_depth = FLAG_VOLUME ? scattering_depth(st, pos, dir, segment) : 0.0;
				pos += dir * segment;
				if (collision < distance) {
					dir = hg_sample_u(dir, hg_g, scatter_events == 0 ? u_scat : vec2(rnd(rng), rnd(rng)));
					scatter_events++;
					tau_free = -log(max(1e-7, 1.0 - rnd(rng)));
				} else {
					tau_free = max(0.0, tau_free - traveled_depth);
					surface_exit_at(st, face, wl, n_wl, n_geom, q, rig_yaw, role_mult,
						0.0, pos, dir, throughput, radiance);
				}
				if (max(max(throughput.x, throughput.y), max(throughput.z, throughput.w)) < THROUGHPUT_EPS) { break; }
			}

		}

#endif
		radiance = min(radiance, vec4(pc.rad_clamp));
		vec3 xyz = (radiance.x * cie_xyz(wl.x) + radiance.y * cie_xyz(wl.y)
			+ radiance.z * cie_xyz(wl.z) + radiance.w * cie_xyz(wl.w)) * pc.spectral_norm;
		total_xyz += xyz;
		vec3 ballistic_xyz = reconstruct_volume || reconstruct_surface ? (ballistic.x * cie_xyz(wl.x) + ballistic.y * cie_xyz(wl.y)
			+ ballistic.z * cie_xyz(wl.z) + ballistic.w * cie_xyz(wl.w)) * pc.spectral_norm : xyz;
		vec3 residual_xyz = xyz - ballistic_xyz;
		total_ballistic += ballistic_xyz;
		total_residual += residual_xyz;
		moment_sum += vec2(residual_xyz.y * residual_xyz.y, residual_xyz.y);
	}

	accum[idx] += vec4(total_xyz, total_cov);
	ballistic_pixels[idx] += vec4(total_ballistic, total_cov);
	residual_pixels[idx] += vec4(total_residual, total_cov);
	guides[idx * 2u] += geometry_sum;
	guides[idx * 2u + 1u] = vec4(guides[idx * 2u + 1u].xy + moment_sum, min_facet, max_facet);
}
