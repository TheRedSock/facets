#version 450
// Scatter-field pre-pass: the in-scattered radiance field of the volume.
//
// For every grid texel centre x inside the stone (exterior texels are pulled
// to the nearest interior point so trilinear lookups stay continuous at the
// surface), integrate the radiance arriving at x over a Fibonacci direction
// set, projected onto real SH (l <= 3) per spectral band:
//
//     c_lm(x, band) = (4 pi / M) sum_i L_in(x, w_i, band) Y_lm(w_i)
//
// L_in follows the ray x -> w_i through the Fresnel chain: at each hull exit
// the transmitted part evaluates the analytic rig (footprint-filtered by
// env_filter_rad), attenuated by Beer-Lambert absorption along the interior
// path; the reflected / TIR part continues until its throughput dies or
// field_exits hull hits are spent (the rung's bounce budget). Inclusions and
// birefringence are not traced here (second order for in-scatter).
//
// The kernel evaluates the HG-scattered radiance at a scatter event as
// sum_lm g^l c_lm Y_lm(dir) and terminates the path: convolving with a zonal
// kernel scales SH band l by g^l, so scattering from every light AND the
// background is deterministic. Spatial resolution is the grid; angular
// resolution is l <= 3 (adequate under the g^l low-pass of HG scattering).
//
// Work layout: SLICES threads per texel, each integrating an interleaved
// slice of the direction set (TIR-trapped directions then stall a slice, not
// a texel), reduced through shared memory; thread s of a texel finally stores
// SH coefficients 4(s%4)..+3 of band s/4. One dispatch handles 4 bands (64
// accumulators); the host issues FIELD_BANDS / 4 x texel-chunk dispatches.
//
#include "gem_common.glsl"

const int SLICES = 16;                 // threads per texel
const int TEXELS_PER_GROUP = 4;
layout(local_size_x = SLICES * TEXELS_PER_GROUP) in;

layout(set = 0, binding = 7, rgba16f) uniform restrict writeonly image3D field;

layout(push_constant, std430) uniform Params {
	int grid_n;          // texels per axis
	int field_exits;     // hull hits integrated per direction (bounce budget)
	int light_count;
	int inst_count;
	int dirs;            // Fibonacci directions per texel
	int band_group;      // which 4 bands this dispatch integrates
	float env_filter_rad;
	int texel_base;      // first texel of this dispatch (host chunks for TDR safety)
	vec4 bg;             // zenith, horizon, below, kelvin (0 = flat spectrum)
} pc;

const float INSIDE_MARGIN = 0.01;
const float THROUGHPUT_EPS = 0.002;

shared float red[TEXELS_PER_GROUP][SLICES][64];

void main() {
	int lid = int(gl_LocalInvocationID.x);
	int tex_local = lid / SLICES;
	int slice = lid - tex_local * SLICES;
	int gid = int(gl_WorkGroupID.x) * TEXELS_PER_GROUP + tex_local + pc.texel_base;
	int gn = pc.grid_n;
	int per_inst = gn * gn * gn;
	bool live = gid < pc.inst_count * per_inst;
	int inst_idx = live ? gid / per_inst : 0;
	int vox = gid - inst_idx * per_inst;
	int vx = vox % gn;
	int vy = (vox / gn) % gn;
	int vz = vox / (gn * gn);

	Inst inst = insts[inst_idx];
	Stone st = stones[inst.which.x];
	int p_off = st.ranges0.x;
	int p_cnt = st.ranges0.y;
	int a_off = st.ranges1.x;
	vec4 q = inst.quat;
	float rig_yaw = inst.rig.x;
	vec4 role_mult = vec4(inst.rig.z, inst.rig.w, inst.rig2.x, inst.rig2.y);
	float size_mm = st.sell_b_size.w;
	float n_geom = sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, 560.0);

	// Texel centre; exterior texels take the field of the nearest interior
	// point along the segment to the stone centroid.
	vec3 x = vec3(-FIELD_HALF) + (vec3(float(vx), float(vy), float(vz)) + 0.5) * (2.0 * FIELD_HALF / float(gn));
	bool have_point = live;
	if (live && !hull_inside(p_off, p_cnt, x, INSIDE_MARGIN)) {
		vec3 c0 = vec3(0.0, 0.0, -0.15);
		if (!hull_inside(p_off, p_cnt, c0, INSIDE_MARGIN)) { c0 = vec3(0.0); }
		have_point = hull_inside(p_off, p_cnt, c0, INSIDE_MARGIN);
		vec3 lo = c0, hi = x;
		for (int it = 0; it < 14 && have_point; it++) {
			vec3 mid = 0.5 * (lo + hi);
			if (hull_inside(p_off, p_cnt, mid, INSIDE_MARGIN)) { lo = mid; } else { hi = mid; }
		}
		x = lo;
	}

	// Band centres and per-band absorption (o-ray) for this dispatch. Absorption
	// only: the kernel samples one scatter event per path and carries the
	// continuation without further extinction (higher scattering orders are
	// delivered forward, energy-conserving). The field must use the same medium
	// model or the two halves of the estimator disagree.
	vec4 wl = vec4(380.0) + (vec4(float(pc.band_group * 4)) + vec4(0.5, 1.5, 2.5, 3.5)) * FIELD_BAND_NM;
	vec4 alpha = vec4(absorb_at(a_off, wl.x), absorb_at(a_off, wl.y), absorb_at(a_off, wl.z), absorb_at(a_off, wl.w))
		* st.misc.y * size_mm;

	float acc[64];
	for (int i = 0; i < 64; i++) { acc[i] = 0.0; }

	float Y[16];
	for (int m = slice; m < pc.dirs && have_point; m += SLICES) {
		vec3 w0 = fib_dir(m, pc.dirs);
		vec3 pos = x;
		vec3 dir = w0;
		vec4 through = vec4(1.0);
		vec4 L_in = vec4(0.0);
		float path = 0.0;
		for (int e = 0; e < pc.field_exits; e++) {
			float t_exit;
			int h;
			hull_exit(p_off, p_cnt, pos, dir, t_exit, h);
			if (t_exit >= INF * 0.5) { break; }
			path += t_exit;
			pos += dir * t_exit;
			vec3 nh = planes[h].n_d.xyz;
			float ci = clamp(dot(dir, nh), 0.0, 1.0);
			float R = fresnel_diel(ci, n_geom);
			if (R < 1.0) {
				float s2o = n_geom * n_geom * (1.0 - ci * ci);
				float cto = sqrt(max(0.0, 1.0 - s2o));
				vec3 dout = normalize(n_geom * dir - (n_geom * ci - cto) * nh);
				vec4 env = env_radiance_ex(quat_rot(q, dout), wl, rig_yaw, role_mult, pc.env_filter_rad,
					true, pc.bg, uint(pc.light_count));
				L_in += through * (1.0 - R) * exp(-alpha * path) * env;
			}
			through *= R;
			if (max(max(through.x, through.y), max(through.z, through.w)) < THROUGHPUT_EPS) { break; }
			dir = normalize(reflect(dir, nh));
			pos -= nh * (T_EPS * 4.0);
		}
		sh16(w0, Y);
		for (int k = 0; k < 16; k++) {
			acc[k] += L_in.x * Y[k];
			acc[16 + k] += L_in.y * Y[k];
			acc[32 + k] += L_in.z * Y[k];
			acc[48 + k] += L_in.w * Y[k];
		}
	}

	for (int i = 0; i < 64; i++) { red[tex_local][slice][i] = acc[i]; }
	barrier();

	if (!live) { return; }
	// Thread `slice` owns band b = slice / 4, coefficient quad t = slice % 4.
	int b = slice / 4;
	int t = slice - b * 4;
	vec4 v = vec4(0.0);
	for (int s = 0; s < SLICES; s++) {
		v += vec4(red[tex_local][s][b * 16 + t * 4], red[tex_local][s][b * 16 + t * 4 + 1],
			red[tex_local][s][b * 16 + t * 4 + 2], red[tex_local][s][b * 16 + t * 4 + 3]);
	}
	v *= 4.0 * PI / float(pc.dirs);
	int slab = (pc.band_group * 4 + b) * 4 + t;
	imageStore(field, ivec3(inst_idx * gn + vx, vy, slab * gn + vz), v);
}
