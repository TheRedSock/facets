#version 450
// Lapidary gem path tracer — kernel v3 (clean optics).
//
// Stone = convex plane set (intersection of half-spaces) + analytic inclusion
// primitives + volumetric media. Transport = spectral, 4 hero wavelengths
// sharing path geometry; per-wavelength path split when the rung enables
// dispersion; entry birefringence fork when the rung + species enable it.
// Facets are perfect specular dielectric interfaces (no wear model).
//
// Deterministic Fresnel splitting: at every interior exit the transmitted
// branch immediately evaluates the analytic environment; the reflected / TIR
// branch continues. The first inclusion surface hit splits deterministically
// (reflected + transmitted branches) instead of a Bernoulli choice.
//
// Volume: unified free flight over homogeneous milk + cloud primitives. At a
// scatter event the scattered radiance (every light AND the background,
// through every Fresnel exit until the throughput dies) is read
// DETERMINISTICALLY from the per-frame SH scatter field
// (gem_scatter_field.glsl), convolved analytically with the HG phase function
// (band l scaled by g^l), and the path terminates: the field IS the
// continuation. Higher scattering orders are delivered forward (the medium
// attenuates by absorption only after the sampled event), the same model on
// both sides of the estimator. field_exits = 0 keeps the stochastic HG
// continuation (reference estimator for the physics check).
//
// Structured dimensions use per-pixel Cranley-Patterson-rotated Halton with a
// GLOBAL sample index; PCG covers the remainder.
//
// Batch-ready: instances are laid out on a pixel grid (grid 1x1 = single
// stone). Stones are ranges into shared plane/inclusion/absorption buffers.
//
// CIE CMF analytic fit: Wyman, Sloan, Shirley, JCGT 2013 (multi-lobe).

#include "gem_common.glsl"

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
	float env_filter_rad; // 68  footprint floor for the post-scatter environment
	int field_exits;      // 72  Fresnel exits integrated by the scatter field (0 = field off: stochastic continuation)
	int field_grid;       // 76  scatter-field texels per axis
	int row_origin;       // 80  first image row of this dispatch (host chunks work for TDR safety)
	int field_insts;      // 84  instances stacked along the field's x axis
	float bg_kelvin;      // 88  background spectrum (Planckian; 0 = flat)
	int pad2;             // 92
} pc;

// In-scattered radiance field (SH l<=3 x spectral bands), built per frame by
// gem_scatter_field.glsl. Hardware trilinear filtering does the spatial blend.
layout(set = 0, binding = 7) uniform sampler3D field;

const float WL_MIN = 380.0;
const float WL_RANGE = 400.0;
const float THROUGHPUT_EPS = 0.004;
const int MAX_CLOUD_SPANS = 8;

#define FLAG_DISPERSION  ((pc.flags & 1u) != 0u)
#define FLAG_BIREF       ((pc.flags & 2u) != 0u)
#define FLAG_VOLUME      ((pc.flags & 4u) != 0u)
#define FLAG_FLUOR       ((pc.flags & 16u) != 0u)

// Polarisation modes for Beer-Lambert.
const int POL_UNPOL = 0;
const int POL_O = 1;
const int POL_K = 2;

// ---------------------------------------------------------------- CIE / spectra
float cie_x(float w) {
	float t1 = (w - 442.0) * ((w < 442.0) ? 0.0624 : 0.0374);
	float t2 = (w - 599.8) * ((w < 599.8) ? 0.0264 : 0.0323);
	float t3 = (w - 501.1) * ((w < 501.1) ? 0.0490 : 0.0382);
	return 0.362 * exp(-0.5 * t1 * t1) + 1.056 * exp(-0.5 * t2 * t2) - 0.065 * exp(-0.5 * t3 * t3);
}
float cie_y(float w) {
	float t1 = (w - 568.8) * ((w < 568.8) ? 0.0213 : 0.0247);
	float t2 = (w - 530.9) * ((w < 530.9) ? 0.0613 : 0.0322);
	return 0.821 * exp(-0.5 * t1 * t1) + 0.286 * exp(-0.5 * t2 * t2);
}
float cie_z(float w) {
	float t1 = (w - 437.0) * ((w < 437.0) ? 0.0845 : 0.0278);
	float t2 = (w - 459.0) * ((w < 459.0) ? 0.0385 : 0.0725);
	return 1.217 * exp(-0.5 * t1 * t1) + 0.681 * exp(-0.5 * t2 * t2);
}
vec3 cie_xyz(float w) { return vec3(cie_x(w), cie_y(w), cie_z(w)); }

// Uniaxial extraordinary index for propagation at angle phi to the optic axis
// (ca = |cos phi|). Converges to n_o along the axis.
float n_e_phi(float n_o, float dn, float ca) {
	float n_e = n_o + dn;
	float c2 = ca * ca;
	float s2 = 1.0 - c2;
	float inv2 = c2 / max(n_o * n_o, 1e-6) + s2 / max(n_e * n_e, 1e-6);
	return inversesqrt(max(inv2, 1e-6));
}

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
		vec4(pc.bg_zenith, pc.bg_horizon, pc.bg_below, pc.bg_kelvin), pc.light_count);
}

// ---------------------------------------------------------------- inclusions
float isect_capsule(vec3 ro, vec3 rd, vec3 c, vec3 axis, float half_len, float radius) {
	vec3 pa = c - axis * half_len;
	vec3 ba = axis * (2.0 * half_len);
	vec3 oa = ro - pa;
	float baba = dot(ba, ba), bard = dot(ba, rd), baoa = dot(ba, oa);
	float rdoa = dot(rd, oa), oaoa = dot(oa, oa);
	float a = baba - bard * bard;
	float b = baba * rdoa - baoa * bard;
	float cc = baba * oaoa - baoa * baoa - radius * radius * baba;
	float h = b * b - a * cc;
	if (h < 0.0) { return INF; }
	float t = (-b - sqrt(h)) / max(a, 1e-9);
	float y = baoa + t * bard;
	if (y > 0.0 && y < baba && t > T_EPS) { return t; }
	vec3 oc = (y <= 0.0) ? oa : ro - (pa + ba);
	b = dot(rd, oc);
	cc = dot(oc, oc) - radius * radius;
	h = b * b - cc;
	if (h > 0.0) {
		t = -b - sqrt(h);
		if (t > T_EPS) { return t; }
	}
	return INF;
}

float isect_sphere(vec3 ro, vec3 rd, vec3 c, float radius) {
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float cc = dot(oc, oc) - radius * radius;
	float h = b * b - cc;
	if (h < 0.0) { return INF; }
	float t = -b - sqrt(h);
	return t > T_EPS ? t : INF;
}

float disc_coverage(vec3 hit, vec3 c, vec3 n, float radius, float style, uint seed) {
	vec3 q = hit - c;
	vec3 t1, t2;
	basis(n, t1, t2);
	float x = dot(q, t1);
	float y = dot(q, t2);
	float r = sqrt(x * x + y * y);
	float ang = atan(y, x);
	float irreg = style > 0.5 ? 0.72 : 0.0;
	float wobble = 1.0 + irreg * 0.55 * (
		sin(ang * 3.0 + float(seed % 97u) * 0.11)
		* sin(ang * 5.0 + float(seed % 53u) * 0.07)
		+ 0.4 * sin(ang * 2.0 + float(seed % 29u) * 0.13));
	if (r > radius * max(wobble, 0.12)) { return 0.0; }
	if (style > 0.5) {
		float along = x * 0.82 + y * 0.57;
		float across = -x * 0.57 + y * 0.82;
		float wave = radius * 0.16 * sin(along * 18.0 + float(seed) * 0.01);
		float band = abs(across - wave) / max(radius, 1e-5);
		float taper = (1.0 - smoothstep(0.35, 1.0, r / max(radius, 1e-5)));
		if (band > mix(0.22, 0.08, taper)) { return 0.0; }
	} else {
		float nr = r / max(radius * (0.96 + 0.04 * sin(ang * 2.0 + float(seed % 17u))), 1e-5);
		if (nr < 0.80 || nr > 1.0) { return 0.0; }
	}
	return 1.0;
}

float isect_disc(vec3 ro, vec3 rd, vec3 c, vec3 n, float radius, float style, uint seed) {
	float denom = dot(rd, n);
	if (abs(denom) < 1e-6) { return INF; }
	float t = dot(c - ro, n) / denom;
	if (t <= T_EPS) { return INF; }
	vec3 hit = ro + rd * t;
	if (disc_coverage(hit, c, n, radius, style, seed) <= 0.0) { return INF; }
	return t;
}

bool ellipsoid_span(vec3 ro, vec3 rd, vec3 c, vec3 axis, float r_major, float r_minor,
		float t_max, out float t0, out float t1) {
	vec3 t1b, t2b;
	basis(axis, t1b, t2b);
	float rm = max(r_minor, 1e-5);
	float rM = max(r_major, 1e-5);
	vec3 lo = ro - c;
	vec3 o = vec3(dot(lo, t1b) / rm, dot(lo, t2b) / rm, dot(lo, axis) / rM);
	vec3 d = vec3(dot(rd, t1b) / rm, dot(rd, t2b) / rm, dot(rd, axis) / rM);
	float a = dot(d, d);
	if (a < 1e-12) { return false; }
	float b = dot(o, d);
	float cc = dot(o, o) - 1.0;
	float h = b * b - a * cc;
	if (h < 0.0) { return false; }
	float s = sqrt(h);
	float ia = 1.0 / a;
	t0 = (-b - s) * ia;
	t1 = (-b + s) * ia;
	if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }
	t0 = max(t0, T_EPS);
	t1 = min(t1, t_max);
	return t1 > t0;
}

// Nearest inclusion SURFACE (needle / disc / crystal). Clouds are volumes.
float inclusions_hit(Stone st, vec3 ro, vec3 rd, float t_max, out int hit_prim) {
	hit_prim = -1;
	float best = t_max;
	for (int i = 0; i < st.ranges0.w; i++) {
		Prim pr = prims[st.ranges0.z + i];
		int type = int(pr.a.w);
		if (type == 2) { continue; }
		float t = INF;
		if (type == 0) { t = isect_capsule(ro, rd, pr.a.xyz, pr.b.xyz, pr.b.w, pr.c.x); }
		else if (type == 1) {
			uint seed = uint(abs(dot(pr.a.xyz, vec3(12.9898, 78.233, 37.719))) * 4096.0) + pc.seed;
			t = isect_disc(ro, rd, pr.a.xyz, pr.b.xyz, pr.b.w, pr.d.z, seed);
		} else {
			t = isect_sphere(ro, rd, pr.a.xyz, pr.b.w);
		}
		if (t < best) { best = t; hit_prim = st.ranges0.z + i; }
	}
	return hit_prim >= 0 ? best : INF;
}

vec4 tint_for(vec4 wl, vec3 tint) {
	vec4 o;
	for (int i = 0; i < 4; i++) {
		float w = wl[i];
		float v = w > 580.0 ? tint.r : (w > 490.0 ? tint.g : tint.b);
		o[i] = v;
	}
	return o;
}

// ---------------------------------------------------------------- unified free flight
// Cloud ellipsoid spans along the chord [0, t_max]; densities in stone units.
int gather_clouds(Stone st, vec3 ro, vec3 rd, float t_max,
		out float c_t0[MAX_CLOUD_SPANS], out float c_t1[MAX_CLOUD_SPANS],
		out float c_dens[MAX_CLOUD_SPANS], out int c_prim[MAX_CLOUD_SPANS]) {
	int n = 0;
	float size_mm = st.sell_b_size.w;
	for (int i = 0; i < st.ranges0.w && n < MAX_CLOUD_SPANS; i++) {
		Prim pr = prims[st.ranges0.z + i];
		if (int(pr.a.w) != 2) { continue; }
		float t0, t1;
		if (!ellipsoid_span(ro, rd, pr.a.xyz, pr.b.xyz, pr.b.w, pr.c.x, t_max, t0, t1)) { continue; }
		c_t0[n] = t0;
		c_t1[n] = t1;
		c_dens[n] = max(pr.c.y, 0.0) * size_mm;
		c_prim[n] = st.ranges0.z + i;
		n++;
	}
	return n;
}

float optical_depth(float t, float sigma_h, int n_c, float c_t0[MAX_CLOUD_SPANS], float c_t1[MAX_CLOUD_SPANS], float c_dens[MAX_CLOUD_SPANS]) {
	float tau = sigma_h * t;
	for (int i = 0; i < n_c; i++) {
		tau += c_dens[i] * clamp(t - c_t0[i], 0.0, c_t1[i] - c_t0[i]);
	}
	return tau;
}

// ---------------------------------------------------------------- zoning / absorption
float zoning_scale(Stone st, vec3 p) {
	float contrast = st.scatter_zone.w;
	if (contrast <= 0.001) { return 1.0; }
	float band = sin(dot(p, st.zone_axis_phase.xyz) * st.scatter_zone.z * PI + st.zone_axis_phase.w);
	return 1.0 + contrast * band;
}

// Beer-Lambert. pol_mode: UNPOL = 0.5 To + 0.5 Tk; O = pure o-ray; K = mixed k-ray.
// alpha_k = cos^2(phi) alpha_o + sin^2(phi) alpha_e  (GIA G&G Spring 2021).
vec4 segment_att(Stone st, vec3 pos, vec3 dir, float t, int a_off, bool has_eray, vec4 wl, int pol_mode) {
	float size_mm = st.sell_b_size.w;
	vec3 mid = pos + dir * (t * 0.5);
	float zf = zoning_scale(st, mid) * st.misc.y;
	float L = t * size_mm;
	if (!has_eray) {
		vec4 alpha = vec4(absorb_at(a_off, wl.x), absorb_at(a_off, wl.y),
			absorb_at(a_off, wl.z), absorb_at(a_off, wl.w));
		return exp(-alpha * zf * L);
	}
	float ca = abs(dot(dir, st.optic_fluor.xyz));
	float c2 = ca * ca;
	float s2 = 1.0 - c2;
	vec4 alpha_o, alpha_e, alpha_k;
	for (int i = 0; i < 4; i++) {
		alpha_o[i] = absorb_at(a_off, wl[i]);
		alpha_e[i] = absorb_at(a_off + 81, wl[i]);
		alpha_k[i] = c2 * alpha_o[i] + s2 * alpha_e[i];
	}
	if (pol_mode == POL_O) { return exp(-alpha_o * zf * L); }
	if (pol_mode == POL_K) { return exp(-alpha_k * zf * L); }
	return 0.5 * exp(-alpha_o * zf * L) + 0.5 * exp(-alpha_k * zf * L);
}

void accumulate_fp(inout float fp, float rough, bool reflect_branch) {
	float a = rough * rough;
	float add = reflect_branch ? (2.0 * a) : a;
	fp = sqrt(fp * fp + add * add);
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

// ---------------------------------------------------------------- scatter field
// HG-scattered radiance at x toward the camera path direction `dir` for the
// 4 hero wavelengths, from the precomputed SH field (see gem_scatter_field).
// Convolution with the HG kernel scales SH band l by g^l.
vec4 field_scatter(int inst_idx, vec3 x, vec3 dir, float g, vec4 wl) {
	int gn = pc.field_grid;
	vec3 gp = clamp((x + vec3(FIELD_HALF)) * (float(gn) / (2.0 * FIELD_HALF)), vec3(0.5), vec3(float(gn) - 0.5));
	float u = (float(inst_idx * gn) + gp.x) / float(pc.field_insts * gn);
	float v = gp.y / float(gn);
	float Y[16];
	sh16(dir, Y);
	float gl[4] = float[](1.0, g, g * g, g * g * g);
	vec4 out_rad = vec4(0.0);
	for (int c = 0; c < 4; c++) {
		float fb = clamp((wl[c] - 380.0) / FIELD_BAND_NM - 0.5, 0.0, float(FIELD_BANDS - 1));
		int b0 = int(fb);
		int b1 = min(b0 + 1, FIELD_BANDS - 1);
		float f = fb - float(b0);
		float L = 0.0;
		for (int t = 0; t < 4; t++) {
			float w0 = ((float(b0 * 4 + t) * float(gn)) + gp.z) / float(FIELD_SLABS * gn);
			float w1 = ((float(b1 * 4 + t) * float(gn)) + gp.z) / float(FIELD_SLABS * gn);
			// Explicit LOD: implicit-LOD sampling is undefined outside fragment shaders.
			vec4 coef = mix(textureLod(field, vec3(u, v, w0), 0.0), textureLod(field, vec3(u, v, w1), 0.0), f);
			// Coefficients t*4 .. t*4+3: l = 0 | 1 1 1 | 2 2 2 2 2 | 3 3 3 3 3 3 3
			int k = t * 4;
			L += coef.x * Y[k] * gl[(k == 0) ? 0 : ((k < 4) ? 1 : ((k < 9) ? 2 : 3))];
			L += coef.y * Y[k + 1] * gl[(k + 1 < 4) ? 1 : ((k + 1 < 9) ? 2 : 3)];
			L += coef.z * Y[k + 2] * gl[(k + 2 < 4) ? 1 : ((k + 2 < 9) ? 2 : 3)];
			L += coef.w * Y[k + 3] * gl[(k + 3 < 4) ? 1 : ((k + 3 < 9) ? 2 : 3)];
		}
		out_rad[c] = max(L, 0.0);
	}
	return out_rad;
}

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

	vec3 total_xyz = vec3(0.0);
	float total_cov = 0.0;

	for (uint s = 0u; s < pc.spp; s++) {
		uint n = pc.sample_base + s;
		rng = (uint(pix.x) * 1973u + uint(pix.y) * 9277u + n * 26699u + pc.seed * 30011u) | 1u;
		pcg(rng);
		float xi = qmc(n, 2u, pix_rot);
		vec4 wl = WL_MIN + (vec4(0.0, 1.0, 2.0, 3.0) + xi) * (WL_RANGE / 4.0);
		vec4 n_wl = vec4(
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.x),
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.y),
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.z),
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.w));

		vec2 r2 = qmc2(n, 0u, 1u, pix_rot);
		vec2 ndc = (cell_uv + (r2 - 0.5) / vec2(pc.cell_px)) * 2.0 - 1.0;
		vec3 ro_w = vec3(ndc.x * ortho_half, -ndc.y * ortho_half, 5.0);
		vec3 ro = quat_rot(qc, ro_w);
		vec3 rd = quat_rot(qc, vec3(0.0, 0.0, -1.0));

		float t_near;
		int entry_plane;
		if (!hull_entry(p_off, p_cnt, ro, rd, t_near, entry_plane)) { continue; }
		total_cov += 1.0;

		vec3 p_hit = ro + rd * t_near;
		vec3 n_entry = planes[entry_plane].n_d.xyz;
		float cos_i = clamp(-dot(rd, n_entry), 0.0, 1.0);

		vec4 radiance = vec4(0.0);

		vec4 r_surf = vec4(
			fresnel_diel(cos_i, 1.0 / n_wl.x), fresnel_diel(cos_i, 1.0 / n_wl.y),
			fresnel_diel(cos_i, 1.0 / n_wl.z), fresnel_diel(cos_i, 1.0 / n_wl.w));
		radiance += r_surf * env_radiance(quat_rot(q, reflect(rd, n_entry)), wl, rig_yaw, role_mult, 0.0);

		bool disp = FLAG_DISPERSION && (st.ranges1.y & 2) != 0;
		bool biref = FLAG_BIREF && abs(st.sell_c_biref.w) > 0.015;
		int n_passes = (disp ? 4 : 1) * (biref ? 2 : 1);

		// Structured dimensions shared by all passes of this sample.
		float tau_free0 = -log(max(1e-6, 1.0 - qmc(n, 3u, pix_rot)));
		vec2 u_scat = qmc2(n, 4u, 5u, pix_rot);
		float u_med = qmc(n, 6u, pix_rot);

		for (int pass_i = 0; pass_i < n_passes; pass_i++) {
			int wl_i = disp ? (pass_i % 4) : -1;
			bool eray = biref && (pass_i >= n_passes / 2);
			vec4 mask = disp ? vec4(wl_i == 0 ? 1.0 : 0.0, wl_i == 1 ? 1.0 : 0.0, wl_i == 2 ? 1.0 : 0.0, wl_i == 3 ? 1.0 : 0.0) : vec4(1.0);
			float pass_w = (biref ? 0.5 : 1.0);
			// Shared geometry uses a mid-spectrum index when not splitting.
			float n_o = disp ? n_wl[wl_i] : 0.5 * (n_wl.y + n_wl.z);
			float ca_in = abs(dot(rd, st.optic_fluor.xyz));
			float n_geom = eray ? n_e_phi(n_o, st.sell_c_biref.w, ca_in) : n_o;
			int pol_mode = biref ? (eray ? POL_K : POL_O) : POL_UNPOL;

			float eta_in = 1.0 / n_geom;
			float s2 = eta_in * eta_in * (1.0 - cos_i * cos_i);
			if (s2 >= 1.0) { continue; }
			float ct = sqrt(1.0 - s2);
			vec3 dir = normalize(eta_in * rd + (eta_in * cos_i - ct) * n_entry);
			vec4 throughput = (vec4(1.0) - r_surf) * mask * pass_w;
			vec3 pos = p_hit - n_entry * (T_EPS * 4.0);
			float fp = 0.0;
			float tau_free = tau_free0;
			int scatter_events = 0;
			uint b = 0u;

			// One-slot split stack for the first inclusion surface hit.
			bool has_alt = false;
			vec3 alt_pos = pos, alt_dir = dir;
			vec4 alt_thr = throughput;
			float alt_fp = 0.0, alt_tau = tau_free;
			int alt_scat = 0;
			uint alt_b = 0u;

			for (int branch = 0; branch < 2; branch++) {
				if (branch == 1) {
					if (!has_alt) { break; }
					pos = alt_pos; dir = alt_dir; throughput = alt_thr; fp = alt_fp;
					tau_free = alt_tau; scatter_events = alt_scat; b = alt_b;
				}
				for (; b < pc.max_bounces; b++) {
					float t_exit;
					int exit_plane;
					hull_exit(p_off, p_cnt, pos, dir, t_exit, exit_plane);
					if (t_exit >= INF * 0.5) { break; }

					int hit_prim;
					float t_incl = inclusions_hit(st, pos, dir, t_exit, hit_prim);
					float t_lim = min(t_exit, t_incl);

					// Unified free flight over homogeneous milk + cloud spans.
					float t_scat = INF;
					int scat_medium = -1;  // -1 homogeneous, else cloud prim index
					if (FLAG_VOLUME) {
						float c_t0[MAX_CLOUD_SPANS], c_t1[MAX_CLOUD_SPANS], c_dens[MAX_CLOUD_SPANS];
						int c_prim[MAX_CLOUD_SPANS];
						int n_c = gather_clouds(st, pos, dir, t_lim, c_t0, c_t1, c_dens, c_prim);
						float tau_chord = optical_depth(t_lim, sigma_h, n_c, c_t0, c_t1, c_dens);
						if (tau_chord > 0.0 && tau_free < tau_chord) {
							float lo = 0.0, hi = t_lim;
							for (int it = 0; it < 20; it++) {
								float mid = 0.5 * (lo + hi);
								if (optical_depth(mid, sigma_h, n_c, c_t0, c_t1, c_dens) < tau_free) { lo = mid; } else { hi = mid; }
							}
							t_scat = 0.5 * (lo + hi);
							// Choose the medium at t_scat proportional to local extinction.
							float total = sigma_h;
							for (int i = 0; i < n_c; i++) {
								if (t_scat >= c_t0[i] && t_scat <= c_t1[i]) { total += c_dens[i]; }
							}
							float pick = (scatter_events == 0 ? u_med : rnd(rng)) * total;
							float acc = sigma_h;
							if (pick >= acc) {
								for (int i = 0; i < n_c; i++) {
									if (t_scat >= c_t0[i] && t_scat <= c_t1[i]) {
										acc += c_dens[i];
										if (pick < acc) { scat_medium = c_prim[i]; break; }
									}
								}
							}
						} else {
							tau_free -= tau_chord;
						}
					}

					float t_ev = min(t_lim, t_scat);
					vec4 seg_att = segment_att(st, pos, dir, t_ev, a_off, has_eray, wl, pol_mode);
					throughput *= seg_att;

					if (t_scat < t_lim) {
						// ---- scatter event
						pos += dir * t_scat;
						float g_phase = hg_g;
						vec4 tnt = vec4(1.0);
						if (scat_medium >= 0) {
							Prim pr = prims[scat_medium];
							tnt = tint_for(wl, vec3(pr.c.z, pr.c.w, pr.d.x));
							g_phase = 0.45;
						}
						if (pc.field_exits > 0) {
							// The field integrates every exit of the continuation: the
							// path ends here.
							radiance += throughput * tnt * field_scatter(inst_idx, pos, dir, g_phase, wl);
							break;
						}
						// Field off: stochastic HG continuation (reference estimator).
						vec2 u_dir = (scatter_events == 0 && branch == 0) ? u_scat : vec2(rnd(rng), rnd(rng));
						dir = hg_sample_u(dir, g_phase, u_dir);
						throughput *= tnt;
						scatter_events++;
						tau_free = -log(max(1e-7, 1.0 - rnd(rng)));
					} else if (t_incl < t_exit) {
						pos += dir * t_incl;
						Prim pr = prims[hit_prim];
						int type = int(pr.a.w);
						vec4 tnt = tint_for(wl, vec3(pr.c.z, pr.c.w, pr.d.x));
						float chord_mm = max(pr.c.x, 0.01) * size_mm;
						float dens = clamp(1.0 - exp(-max(pr.c.y, 0.0) * chord_mm), 0.05, 0.95);
						if (type == 3) {
							vec3 n_p = normalize(pos - pr.a.xyz);
							if (dot(n_p, dir) > 0.0) { n_p = -n_p; }
							vec3 sparkle = normalize(reflect(dir, n_p));
							float fp_s = fp;
							accumulate_fp(fp_s, 0.25, true);
							radiance += throughput * tnt * 0.18
								* env_radiance(quat_rot(q, sparkle), wl, rig_yaw, role_mult, fp_s);
							throughput *= mix(vec4(1.0), tnt, 0.22);
							pos += dir * (T_EPS * 8.0);
						} else {
							vec3 n_i;
							float p_reflect;
							float rough;
							if (type == 0) {
								vec3 ap = pr.a.xyz + pr.b.xyz * dot(pos - pr.a.xyz, pr.b.xyz);
								n_i = normalize(pos - ap);
								p_reflect = dens;
								rough = 0.30;
							} else {
								n_i = pr.b.xyz;
								bool veil = pr.d.z > 0.5;
								rough = veil ? 0.58 : 0.42;
								p_reflect = veil ? dens * 0.28 : dens * 0.16;
							}
							if (dot(n_i, dir) > 0.0) { n_i = -n_i; }
							bool do_reflect;
							if (!has_alt) {
								// Deterministic split: transmitted branch parked, reflected continues.
								has_alt = true;
								alt_pos = pos + dir * (T_EPS * 8.0);
								alt_dir = dir;
								alt_thr = throughput * (1.0 - p_reflect);
								alt_fp = fp;
								alt_tau = tau_free;
								alt_scat = scatter_events;
								alt_b = b + 1u;
								throughput *= p_reflect;
								do_reflect = true;
							} else {
								do_reflect = rnd(rng) < p_reflect;
							}
							if (do_reflect) {
								dir = normalize(reflect(dir, n_i));
								accumulate_fp(fp, rough, true);
								throughput *= tnt;
							} else {
								pos += dir * (T_EPS * 8.0);
							}
						}
					} else {
						pos += dir * t_exit;
						// Post-scatter chains (field off only) see the environment
						// through the same footprint floor the field pre-pass uses.
						float fp_env = (scatter_events > 0) ? max(fp, pc.env_filter_rad) : fp;
						surface_exit_at(st, exit_plane, wl, n_wl, n_geom, q, rig_yaw, role_mult,
							fp_env, pos, dir, throughput, radiance);
					}
					if (max(max(throughput.x, throughput.y), max(throughput.z, throughput.w)) < THROUGHPUT_EPS) { break; }
				}
			}
		}

		radiance = min(radiance, vec4(pc.rad_clamp));
		vec3 xyz = (radiance.x * cie_xyz(wl.x) + radiance.y * cie_xyz(wl.y)
			+ radiance.z * cie_xyz(wl.z) + radiance.w * cie_xyz(wl.w)) * pc.spectral_norm;
		total_xyz += xyz;
	}

	accum[idx] += vec4(total_xyz, total_cov);
}
