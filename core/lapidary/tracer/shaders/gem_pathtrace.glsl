#version 450
// Lapidary gem path tracer — kernel v1.
//
// Stone = convex plane set (intersection of half-spaces) + analytic inclusion
// primitives + volumetric media. Transport = spectral, 4 hero wavelengths
// sharing path geometry; per-wavelength path split when the rung enables
// dispersion; entry birefringence fork when the rung + species enable it.
//
// Deterministic Fresnel splitting: at every interior exit the transmitted
// branch immediately evaluates the analytic environment; the reflected / TIR
// branch continues. HG scatter (homogeneous volume or cloud primitive) is
// the same bet: at most one event, then the remaining chord to the hull
// evaluates the analytic rig (NEE). Needle/platelet silk is rough-specular
// and does not consume that slot.
// Stochastic parts: AA jitter, hero-lambda stratification, GGX wear,
// the scatter direction, inclusion hits.
//
// Batch-ready: instances are laid out on a pixel grid (grid 1x1 = single
// stone). Stones are ranges into shared plane/inclusion/absorption buffers.
//
// CIE CMF analytic fit: Wyman, Sloan, Shirley, JCGT 2013 (multi-lobe).

layout(local_size_x = 8, local_size_y = 8) in;

struct Plane { vec4 n_d; vec4 aux; };          // aux: zone, roughness, reserved
struct Light { vec4 dir_cos; vec4 kel_pow; };  // kel_pow: kelvin, power, cos_inner, role(0 emit,1 blocker)
struct Prim  { vec4 a; vec4 b; vec4 c; vec4 d; };
// Prim: a = center.xyz, type (0 needle,1 platelet,2 cloud,3 crystal)
//       b = axis.xyz, r0 (half-length / radius)
//       c = r1, scatter_density, tint.r, tint.g
//       d = tint.b, reserved x3

struct Stone {
	vec4 sell_b_size;      // sellmeier B xyz, size_mm
	vec4 sell_c_biref;     // sellmeier C xyz (um^2), birefringence dn
	vec4 scatter_zone;     // sigma_per_mm, hg_g, zoning_freq, zoning_contrast
	vec4 zone_axis_phase;  // zoning axis xyz, phase
	vec4 optic_fluor;      // optic axis xyz, fluorescence strength
	vec4 wear0;            // roughness_boost, scratch_density, scratch_aniso, abrasion
	vec4 wear1;            // dirt, edge_round, fluor_nm, absorb_scale
	ivec4 ranges0;         // plane_offset, plane_count, incl_offset, incl_count
	ivec4 ranges1;         // absorb_offset, stone_flags (bit0 has_eray), pad, pad
};

struct Inst {
	vec4 quat;         // stone->world
	vec4 rig;          // rig_yaw (radians), ortho_half, key_mult, fill_mult
	vec4 rig2;         // rim_mult, bounce_mult, pad, pad
	ivec4 which;       // stone_index, pad x3
};

layout(set = 0, binding = 0, std430) restrict readonly buffer Planes  { Plane planes[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer Lights  { Light lights[]; };
layout(set = 0, binding = 2, std430) restrict readonly buffer Absorb  { float absorb_mm[]; };
layout(set = 0, binding = 3, std430) restrict buffer Accum            { vec4 accum[]; };
layout(set = 0, binding = 4, std430) restrict readonly buffer Prims   { Prim prims[]; };
layout(set = 0, binding = 5, std430) restrict readonly buffer Stones  { Stone stones[]; };
layout(set = 0, binding = 6, std430) restrict readonly buffer Insts   { Inst insts[]; };

layout(push_constant, std430) uniform Params {
	ivec2 resolution;     // 0
	uint frame;           // 8
	uint spp;             // 12
	uint seed;            // 16
	uint max_bounces;     // 20
	uint flags;           // 24  bit0 dispersion_split, bit1 birefringence, bit2-3 volume_mode, bit4 fluorescence
	uint light_count;     // 28
	ivec2 grid;           // 32  cols, rows
	ivec2 cell_px;        // 40
	float bg_zenith;      // 48
	float bg_horizon;     // 52
	float bg_below;       // 56
	float spectral_norm;  // 60
	float rad_clamp;      // 64  per-sample radiance ceiling (firefly control; rung policy)
	float pad0;           // 68
	float pad1;           // 72
	float pad2;           // 76 -> 80
} pc;

const float WL_MIN = 380.0;
const float WL_RANGE = 400.0;
const float T_EPS = 1e-5;
const float THROUGHPUT_EPS = 0.004;
const float INF = 1e30;

#define FLAG_DISPERSION  ((pc.flags & 1u) != 0u)
#define FLAG_BIREF       ((pc.flags & 2u) != 0u)
#define VOLUME_MODE      int((pc.flags >> 2u) & 3u)
#define FLAG_FLUOR       ((pc.flags & 16u) != 0u)

// ---------------------------------------------------------------- RNG
uint pcg(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}
float rnd(inout uint s) { return float(pcg(s)) * (1.0 / 4294967296.0); }

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

float planck_rel(float wl, float kelvin) {
	float c2 = 1.4388e7;
	float r = 560.0 / wl;
	return r * r * r * r * r * (exp(c2 / (560.0 * kelvin)) - 1.0) / max(exp(c2 / (wl * kelvin)) - 1.0, 1e-12);
}

float sellmeier(vec3 B, vec3 C, float wl_nm) {
	float l2 = (wl_nm * 1e-3) * (wl_nm * 1e-3);
	float s = 1.0 + B.x * l2 / (l2 - C.x) + B.y * l2 / (l2 - C.y);
	if (B.z > 0.0) { s += B.z * l2 / (l2 - C.z); }
	return sqrt(max(s, 1.0));
}

float absorb_at(int base, float wl_nm) {
	float f = clamp((wl_nm - 380.0) / 5.0, 0.0, 80.0);
	int i = int(f);
	return mix(absorb_mm[base + i], absorb_mm[base + min(i + 1, 80)], f - float(i));
}

// ---------------------------------------------------------------- math
vec3 quat_rot(vec4 q, vec3 v) { return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v); }
vec4 quat_conj(vec4 q) { return vec4(-q.xyz, q.w); }
vec3 rot_y(vec3 v, float a) {
	float c = cos(a), s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

float fresnel_diel(float cos_i, float eta) {
	float s2 = eta * eta * (1.0 - cos_i * cos_i);
	if (s2 >= 1.0) { return 1.0; }
	float ct = sqrt(1.0 - s2);
	float rs = (eta * cos_i - ct) / (eta * cos_i + ct);
	float rp = (cos_i - eta * ct) / (cos_i + eta * ct);
	return 0.5 * (rs * rs + rp * rp);
}

void basis(vec3 n, out vec3 t1, out vec3 t2) {
	t1 = normalize(cross(n, abs(n.z) < 0.9 ? vec3(0, 0, 1) : vec3(1, 0, 0)));
	t2 = cross(n, t1);
}

// GGX normal perturbation (isotropic, alpha = roughness^2).
vec3 ggx_perturb(vec3 n, float rough, inout uint rng) {
	if (rough <= 0.001) { return n; }
	float a = rough * rough;
	float x1 = rnd(rng), x2 = rnd(rng);
	float ct = sqrt((1.0 - x1) / (1.0 + (a * a - 1.0) * x1));
	float st = sqrt(max(0.0, 1.0 - ct * ct));
	float phi = 6.2831853 * x2;
	vec3 t1, t2;
	basis(n, t1, t2);
	return normalize(t1 * (st * cos(phi)) + t2 * (st * sin(phi)) + n * ct);
}

// Henyey-Greenstein direction sample.
vec3 hg_sample(vec3 dir, float g, inout uint rng) {
	float x1 = rnd(rng), x2 = rnd(rng);
	float ct;
	if (abs(g) < 0.01) {
		ct = 1.0 - 2.0 * x1;
	} else {
		float sq = (1.0 - g * g) / (1.0 - g + 2.0 * g * x1);
		ct = (1.0 + g * g - sq * sq) / (2.0 * g);
	}
	float st = sqrt(max(0.0, 1.0 - ct * ct));
	float phi = 6.2831853 * x2;
	vec3 t1, t2;
	basis(dir, t1, t2);
	return normalize(t1 * (st * cos(phi)) + t2 * (st * sin(phi)) + dir * ct);
}

// ---------------------------------------------------------------- environment
vec4 env_radiance(vec3 dir, vec4 wl, float rig_yaw, vec4 role_mult) {
	float up = dir.y;
	float bg = (up >= 0.0)
		? mix(pc.bg_horizon, pc.bg_zenith, smoothstep(0.0, 0.85, up))
		: mix(pc.bg_horizon, pc.bg_below, smoothstep(0.0, 0.6, -up));
	vec4 rad = vec4(bg);
	float blocker = 1.0;
	for (uint li = 0u; li < pc.light_count; li++) {
		Light L = lights[li];
		vec3 ldir = rot_y(L.dir_cos.xyz, rig_yaw);
		float d = dot(dir, ldir);
		float w = smoothstep(L.dir_cos.w, L.kel_pow.z, d);
		if (w <= 0.0) { continue; }
		if (L.kel_pow.w > 0.5) {
			blocker *= 1.0 - clamp(L.kel_pow.y, 0.0, 1.0) * w;
			continue;
		}
		float mult = li == 0u ? role_mult.x : (li == 1u ? role_mult.y : (li == 2u ? role_mult.z : role_mult.w));
		vec4 spd = vec4(planck_rel(wl.x, L.kel_pow.x), planck_rel(wl.y, L.kel_pow.x),
			planck_rel(wl.z, L.kel_pow.x), planck_rel(wl.w, L.kel_pow.x));
		rad += spd * (L.kel_pow.y * w * mult);
	}
	return rad * blocker;
}

// ---------------------------------------------------------------- hull
bool hull_entry(int off, int count, vec3 ro, vec3 rd, out float t_near, out int near_plane) {
	t_near = -INF;
	float t_far = INF;
	near_plane = -1;
	for (int i = 0; i < count; i++) {
		vec3 n = planes[off + i].n_d.xyz;
		float d = planes[off + i].n_d.w;
		float denom = dot(n, rd);
		float dist = d - dot(n, ro);
		if (abs(denom) < 1e-9) {
			if (dist < 0.0) { return false; }
			continue;
		}
		float t = dist / denom;
		if (denom < 0.0) {
			if (t > t_near) { t_near = t; near_plane = off + i; }
		} else {
			t_far = min(t_far, t);
		}
		if (t_near > t_far) { return false; }
	}
	return near_plane >= 0 && t_near > T_EPS;
}

void hull_exit(int off, int count, vec3 ro, vec3 rd, out float t_exit, out int exit_plane) {
	t_exit = INF;
	exit_plane = off;
	for (int i = 0; i < count; i++) {
		vec3 n = planes[off + i].n_d.xyz;
		float denom = dot(n, rd);
		if (denom <= 1e-9) { continue; }
		float t = (planes[off + i].n_d.w - dot(n, ro)) / denom;
		if (t > T_EPS && t < t_exit) { t_exit = t; exit_plane = off + i; }
	}
}

// Edge rounding as shading: near a neighboring half-space boundary, bend the
// normal toward that plane's normal. Silhouette untouched.
vec3 rounded_normal(int off, int count, vec3 p, int hit_plane, float radius) {
	vec3 n = planes[hit_plane].n_d.xyz;
	if (radius <= 0.0005) { return n; }
	vec3 acc = n;
	for (int i = 0; i < count; i++) {
		if (off + i == hit_plane) { continue; }
		float slack = planes[off + i].n_d.w - dot(planes[off + i].n_d.xyz, p);
		if (slack < radius) {
			float w = 1.0 - clamp(slack / radius, 0.0, 1.0);
			acc += planes[off + i].n_d.xyz * (w * w * 0.6);
		}
	}
	return normalize(acc);
}

// ---------------------------------------------------------------- wear
// Procedural scratch field in facet-local UV. Returns extra roughness.
float scratch_field(Stone st, int plane_idx, vec3 p, vec3 n, uint seed_mix) {
	float density = st.wear0.y;
	if (density <= 0.01) { return 0.0; }
	vec3 t1, t2;
	basis(n, t1, t2);
	vec2 uv = vec2(dot(p, t1), dot(p, t2));
	float total = 0.0;
	uint h = uint(plane_idx) * 7919u + seed_mix * 31u + 977u;
	// Sparse individual scratches, not a woven fabric: few lines, hairline
	// width, angles clustered around a per-facet wipe direction.
	int lines = int(clamp(density * 0.5, 1.0, 6.0));
	float wipe = float(pcg(h)) * (6.2831853 / 4294967296.0);
	for (int k = 0; k < lines; k++) {
		float ang = wipe + (float(pcg(h)) * (1.0 / 4294967296.0) - 0.5) * 1.1;
		float freq = 12.0 + float(pcg(h) & 127u) * 0.9;
		float phase = float(pcg(h)) * (6.2831853 / 4294967296.0);
		float s = sin((uv.x * cos(ang) + uv.y * sin(ang)) * freq + phase);
		total += smoothstep(0.9975, 1.0, abs(s));
	}
	// Abrasion patches: broad low-frequency roughness blotches.
	float ab = st.wear0.w;
	if (ab > 0.005) {
		float blotch = sin(uv.x * 9.1 + float(h & 15u)) * sin(uv.y * 7.3 + float(h & 31u));
		total += ab * smoothstep(0.2, 0.9, blotch);
	}
	return clamp(total, 0.0, 1.0) * 0.30;
}

float surface_roughness(Stone st, int plane_idx, vec3 p, vec3 n, uint seed_mix) {
	return clamp(planes[plane_idx].aux.y + st.wear0.x + scratch_field(st, plane_idx, p, n, seed_mix), 0.0, 0.6);
}

// ---------------------------------------------------------------- inclusions
// Analytic ray tests. Returns t or INF.
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
	// caps
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

float isect_disc(vec3 ro, vec3 rd, vec3 c, vec3 n, float radius, float half_th) {
	float denom = dot(rd, n);
	if (abs(denom) < 1e-6) { return INF; }
	float t = dot(c - ro, n) / denom;
	if (t <= T_EPS) { return INF; }
	vec3 q = ro + rd * t - c;
	if (dot(q, q) - pow(dot(q, n), 2.0) > radius * radius) { return INF; }
	return t; // thin: half_th folded into scatter probability
}

float isect_ellipsoid(vec3 ro, vec3 rd, vec3 c, vec3 axis, float r_major, float r_minor) {
	vec3 t1, t2;
	basis(axis, t1, t2);
	vec3 lo = ro - c;
	vec3 o = vec3(dot(lo, t1) / r_minor, dot(lo, t2) / r_minor, dot(lo, axis) / r_major);
	vec3 d = vec3(dot(rd, t1) / r_minor, dot(rd, t2) / r_minor, dot(rd, axis) / r_major);
	float a = dot(d, d), b = dot(o, d), cc = dot(o, o) - 1.0;
	float h = b * b - a * cc;
	if (h < 0.0) { return INF; }
	float t = (-b - sqrt(h)) / max(a, 1e-9);
	return t > T_EPS ? t : INF;
}

float inclusions_hit(Stone st, vec3 ro, vec3 rd, float t_max, out int hit_prim) {
	hit_prim = -1;
	float best = t_max;
	for (int i = 0; i < st.ranges0.w; i++) {
		Prim pr = prims[st.ranges0.z + i];
		int type = int(pr.a.w);
		float t = INF;
		if (type == 0) { t = isect_capsule(ro, rd, pr.a.xyz, pr.b.xyz, pr.b.w, pr.c.x); }
		else if (type == 1) { t = isect_disc(ro, rd, pr.a.xyz, pr.b.xyz, pr.b.w, pr.c.x); }
		else if (type == 2) { t = isect_ellipsoid(ro, rd, pr.a.xyz, pr.b.xyz, pr.b.w, pr.c.x); }
		else { t = isect_sphere(ro, rd, pr.a.xyz, pr.b.w); }
		if (t < best) { best = t; hit_prim = st.ranges0.z + i; }
	}
	return hit_prim >= 0 ? best : INF;
}

// Broad-band tint applied per hero wavelength (documented approximation:
// R drives >580nm, G 490-580, B <490).
vec4 tint_for(vec4 wl, vec3 tint) {
	vec4 o;
	for (int i = 0; i < 4; i++) {
		float w = wl[i];
		float v = w > 580.0 ? tint.r : (w > 490.0 ? tint.g : tint.b);
		o[i] = v;
	}
	return o;
}

// ---------------------------------------------------------------- zoning
float zoning_scale(Stone st, vec3 p) {
	float contrast = st.scatter_zone.w;
	if (contrast <= 0.001) { return 1.0; }
	float band = sin(dot(p, st.zone_axis_phase.xyz) * st.scatter_zone.z * 3.14159 + st.zone_axis_phase.w);
	return 1.0 + contrast * band;
}

// Beer-Lambert over a chord. Zoning sampled at the midpoint.
vec4 segment_att(Stone st, vec3 pos, vec3 dir, float t, int a_off, bool has_eray, vec4 wl) {
	float size_mm = st.sell_b_size.w;
	vec3 mid = pos + dir * (t * 0.5);
	float zf = zoning_scale(st, mid) * st.wear1.w;
	vec4 alpha;
	if (has_eray) {
		float ca = abs(dot(dir, st.optic_fluor.xyz));
		float mix_e = ca * ca;
		for (int i = 0; i < 4; i++) {
			alpha[i] = mix(absorb_at(a_off, wl[i]), absorb_at(a_off + 81, wl[i]), mix_e);
		}
	} else {
		alpha = vec4(absorb_at(a_off, wl.x), absorb_at(a_off, wl.y), absorb_at(a_off, wl.z), absorb_at(a_off, wl.w));
	}
	return exp(-alpha * zf * (t * size_mm));
}

// After an HG scatter (homogeneous volume or cloud primitive): remaining
// chord to the hull, then the analytic rig. Continues only the TIR/reflect
// branch. One HG event per path — milk is σ, not bounce count.
void scatter_nee(Stone st, int p_off, int p_cnt, int a_off, bool has_eray,
		vec4 wl, vec4 n_wl, float n_geom, vec4 q, float rig_yaw, vec4 role_mult, vec4 dirt_tint,
		inout vec3 pos, inout vec3 dir, inout vec4 throughput, inout vec4 radiance,
		inout float fluor_absorbed, inout uint rng) {
	float t_nee;
	int nee_plane;
	hull_exit(p_off, p_cnt, pos, dir, t_nee, nee_plane);
	vec4 att_n = segment_att(st, pos, dir, t_nee, a_off, has_eray, wl);
	if (FLAG_FLUOR && st.optic_fluor.w > 0.0) {
		vec4 pump = smoothstep(vec4(620.0), vec4(480.0), wl);
		fluor_absorbed += dot(throughput * (vec4(1.0) - att_n), pump);
	}
	throughput *= att_n;
	pos += dir * t_nee;
	float rough = surface_roughness(st, nee_plane, pos, planes[nee_plane].n_d.xyz, pc.seed);
	vec3 en = rounded_normal(p_off, p_cnt, pos, nee_plane, st.wear1.y);
	en = ggx_perturb(en, rough, rng);
	if (dot(dir, en) < 0.02) { en = planes[nee_plane].n_d.xyz; }
	float ci = clamp(dot(dir, en), 0.0, 1.0);
	float s2o = n_geom * n_geom * (1.0 - ci * ci);
	if (s2o < 1.0) {
		vec4 r_exit = vec4(
			fresnel_diel(ci, n_wl.x), fresnel_diel(ci, n_wl.y),
			fresnel_diel(ci, n_wl.z), fresnel_diel(ci, n_wl.w));
		float cto = sqrt(1.0 - s2o);
		vec3 dout = normalize(n_geom * dir - (n_geom * ci - cto) * en);
		radiance += throughput * (vec4(1.0) - r_exit) * dirt_tint
			* env_radiance(quat_rot(q, dout), wl, rig_yaw, role_mult);
		throughput *= r_exit;
	}
	dir = normalize(reflect(dir, en));
	if (dot(dir, planes[nee_plane].n_d.xyz) > 0.0) {
		dir = normalize(reflect(dir, planes[nee_plane].n_d.xyz));
	}
	pos -= planes[nee_plane].n_d.xyz * (T_EPS * 4.0);
}

// ================================================================= main
void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	if (pix.x >= pc.resolution.x || pix.y >= pc.resolution.y) { return; }
	uint idx = uint(pix.y) * uint(pc.resolution.x) + uint(pix.x);

	// Which instance does this pixel belong to?
	int col = min(pix.x / pc.cell_px.x, pc.grid.x - 1);
	int row = min(pix.y / pc.cell_px.y, pc.grid.y - 1);
	Inst inst = insts[row * pc.grid.x + col];
	Stone st = stones[inst.which.x];
	vec2 cell_uv = vec2(pix - ivec2(col, row) * pc.cell_px) / vec2(pc.cell_px);

	uint rng = (uint(pix.x) * 1973u + uint(pix.y) * 9277u + pc.frame * 26699u + pc.seed * 30011u) | 1u;
	vec4 q = inst.quat;
	vec4 qc = quat_conj(q);
	vec4 role_mult = vec4(inst.rig.z, inst.rig.w, inst.rig2.x, inst.rig2.y);
	float rig_yaw = inst.rig.x;
	int p_off = st.ranges0.x;
	int p_cnt = st.ranges0.y;
	int a_off = st.ranges1.x;
	bool has_eray = (st.ranges1.y & 1) != 0;
	float size_mm = st.sell_b_size.w;
	float sigma = st.scatter_zone.x;
	float hg_g = st.scatter_zone.y;

	vec3 total_xyz = vec3(0.0);
	float total_cov = 0.0;

	for (uint s = 0u; s < pc.spp; s++) {
		float xi = rnd(rng);
		vec4 wl = WL_MIN + (vec4(0.0, 1.0, 2.0, 3.0) + xi) * (WL_RANGE / 4.0);
		vec4 n_wl = vec4(
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.x),
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.y),
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.z),
			sellmeier(st.sell_b_size.xyz, st.sell_c_biref.xyz, wl.w));

		// Camera ray (ortho, cell-local), into stone space.
		vec2 ndc = (cell_uv + (vec2(rnd(rng), rnd(rng)) - 0.5) / vec2(pc.cell_px)) * 2.0 - 1.0;
		vec3 ro_w = vec3(ndc.x * inst.rig.y, -ndc.y * inst.rig.y, 5.0);
		vec3 ro = quat_rot(qc, ro_w);
		vec3 rd = quat_rot(qc, vec3(0.0, 0.0, -1.0));

		float t_near;
		int entry_plane;
		if (!hull_entry(p_off, p_cnt, ro, rd, t_near, entry_plane)) { continue; }
		total_cov += 1.0;

		vec3 p_hit = ro + rd * t_near;
		float entry_rough = surface_roughness(st, entry_plane, p_hit, planes[entry_plane].n_d.xyz, pc.seed);
		vec3 n_entry = rounded_normal(p_off, p_cnt, p_hit, entry_plane, st.wear1.y);
		n_entry = ggx_perturb(n_entry, entry_rough, rng);
		if (dot(n_entry, rd) > -0.02) { n_entry = planes[entry_plane].n_d.xyz; }
		float cos_i = clamp(-dot(rd, n_entry), 0.0, 1.0);

		vec4 radiance = vec4(0.0);
		float fluor_absorbed = 0.0;

		// Surface reflection lobe.
		vec4 r_surf = vec4(
			fresnel_diel(cos_i, 1.0 / n_wl.x), fresnel_diel(cos_i, 1.0 / n_wl.y),
			fresnel_diel(cos_i, 1.0 / n_wl.z), fresnel_diel(cos_i, 1.0 / n_wl.w));
		radiance += r_surf * env_radiance(quat_rot(q, reflect(rd, n_entry)), wl, rig_yaw, role_mult);

		// Dirt film: broadband loss + brownish bias at entry.
		vec4 dirt_tint = vec4(1.0);
		if (st.wear1.x > 0.005) {
			vec4 dirt_a = vec4(0.9, 0.75, 0.55, 0.45); // more loss at short wavelengths
			dirt_tint = mix(vec4(1.0), dirt_a, clamp(st.wear1.x, 0.0, 1.0));
		}

		// Pass setup: dispersion split -> 4 single-lambda passes;
		// birefringence -> x2 passes with n_o / n_e.
		bool disp = FLAG_DISPERSION && (st.ranges1.y & 2) != 0;
		bool biref = FLAG_BIREF && st.sell_c_biref.w > 0.015;
		int n_passes = (disp ? 4 : 1) * (biref ? 2 : 1);

		for (int pass_i = 0; pass_i < n_passes; pass_i++) {
			int wl_i = disp ? (pass_i % 4) : -1;
			bool eray = biref && (pass_i >= n_passes / 2);
			vec4 mask = disp ? vec4(wl_i == 0 ? 1.0 : 0.0, wl_i == 1 ? 1.0 : 0.0, wl_i == 2 ? 1.0 : 0.0, wl_i == 3 ? 1.0 : 0.0) : vec4(1.0);
			float pass_w = (biref ? 0.5 : 1.0);
			float n_geom = disp ? n_wl[wl_i] : n_wl.x;
			if (eray) { n_geom += st.sell_c_biref.w; }

			float eta_in = 1.0 / n_geom;
			float s2 = eta_in * eta_in * (1.0 - cos_i * cos_i);
			if (s2 >= 1.0) { continue; }
			float ct = sqrt(1.0 - s2);
			vec3 dir = normalize(eta_in * rd + (eta_in * cos_i - ct) * n_entry);
			vec4 throughput = (vec4(1.0) - r_surf) * dirt_tint * mask * pass_w;
			vec3 pos = p_hit - planes[entry_plane].n_d.xyz * (T_EPS * 4.0);
			int scatter_events = 0;

			for (uint b = 0u; b < pc.max_bounces; b++) {
				float t_exit;
				int exit_plane;
				hull_exit(p_off, p_cnt, pos, dir, t_exit, exit_plane);

				int hit_prim;
				float t_incl = inclusions_hit(st, pos, dir, t_exit, hit_prim);

				float t_scat = INF;
				int vol_mode = VOLUME_MODE;
				// One scatter event even in VOLUME_FULL: a random walk of HG
				// events is the quartz noise source. Milk reads from sigma, not
				// from bounce count. VOLUME_OFF still skips scatter entirely.
				bool vol_allowed = vol_mode != 0 && scatter_events == 0;
				if (sigma > 0.001 && vol_allowed) {
					t_scat = -log(max(1e-6, 1.0 - rnd(rng))) / (sigma * size_mm);
				}

				float t_ev = min(t_exit, min(t_incl, t_scat));

				vec4 seg_att = segment_att(st, pos, dir, t_ev, a_off, has_eray, wl);
				if (FLAG_FLUOR && st.optic_fluor.w > 0.0) {
					vec4 pump = smoothstep(vec4(620.0), vec4(480.0), wl);
					fluor_absorbed += dot(throughput * (vec4(1.0) - seg_att), pump);
				}
				throughput *= seg_att;

				if (t_scat <= t_incl && t_scat <= t_exit) {
					pos += dir * t_scat;
					dir = hg_sample(dir, hg_g, rng);
					scatter_events++;
					scatter_nee(st, p_off, p_cnt, a_off, has_eray, wl, n_wl, n_geom, q,
						rig_yaw, role_mult, dirt_tint, pos, dir, throughput, radiance,
						fluor_absorbed, rng);
				} else if (t_incl < t_exit) {
					// Inclusion interaction. Needles (rutile silk) and platelets are
					// rough-SPECULAR reflectors off their geometry — silk reads as
					// bright streaks, not as diffuse fog. Clouds stay HG scatter.
					pos += dir * t_incl;
					Prim pr = prims[hit_prim];
					int type = int(pr.a.w);
					vec4 tnt = tint_for(wl, vec3(pr.c.z, pr.c.w, pr.d.x));
					float dens = clamp(pr.c.y * 0.30, 0.1, 0.95);
					if (type == 3) {
						vec3 n_p = normalize(pos - pr.a.xyz);
						dir = normalize(reflect(dir, ggx_perturb(n_p, 0.25, rng)));
						throughput *= tnt * 0.9;
					} else if (type == 0) {
						vec3 ap = pr.a.xyz + pr.b.xyz * dot(pos - pr.a.xyz, pr.b.xyz);
						vec3 n_cyl = normalize(pos - ap);
						if (dot(n_cyl, dir) > 0.0) { n_cyl = -n_cyl; }
						if (rnd(rng) < dens) {
							dir = normalize(reflect(dir, ggx_perturb(n_cyl, 0.30, rng)));
							throughput *= tnt;
						} else {
							pos += dir * (T_EPS * 8.0);
						}
					} else if (type == 1) {
						vec3 n_dsc = pr.b.xyz;
						if (dot(n_dsc, dir) > 0.0) { n_dsc = -n_dsc; }
						if (rnd(rng) < dens) {
							dir = normalize(reflect(dir, ggx_perturb(n_dsc, 0.22, rng)));
							throughput *= tnt;
						} else {
							pos += dir * (T_EPS * 8.0);
						}
					} else {
						// Cloud / fingerprint (kernel type 2). Same one-HG+NEE
						// contract as volume milk — a cloud random-walk is the
						// remaining quartz grain at 160 spp.
						if (scatter_events == 0 && rnd(rng) < dens) {
							dir = hg_sample(dir, 0.45, rng);
							throughput *= tnt;
							scatter_events++;
							scatter_nee(st, p_off, p_cnt, a_off, has_eray, wl, n_wl, n_geom, q,
								rig_yaw, role_mult, dirt_tint, pos, dir, throughput, radiance,
								fluor_absorbed, rng);
						} else {
							pos += dir * (T_EPS * 8.0);
						}
					}
				} else {
					// Hull exit: deterministic Fresnel split.
					pos += dir * t_exit;
					float rough = surface_roughness(st, exit_plane, pos, planes[exit_plane].n_d.xyz, pc.seed);
					vec3 en = rounded_normal(p_off, p_cnt, pos, exit_plane, st.wear1.y);
					en = ggx_perturb(en, rough, rng);
					if (dot(dir, en) < 0.02) { en = planes[exit_plane].n_d.xyz; }
					float ci = clamp(dot(dir, en), 0.0, 1.0);
					float s2o = n_geom * n_geom * (1.0 - ci * ci);
					if (s2o < 1.0) {
						vec4 r_exit = vec4(
							fresnel_diel(ci, n_wl.x), fresnel_diel(ci, n_wl.y),
							fresnel_diel(ci, n_wl.z), fresnel_diel(ci, n_wl.w));
						float cto = sqrt(1.0 - s2o);
						vec3 dout = normalize(n_geom * dir - (n_geom * ci - cto) * en);
						radiance += throughput * (vec4(1.0) - r_exit) * dirt_tint
							* env_radiance(quat_rot(q, dout), wl, rig_yaw, role_mult);
						throughput *= r_exit;
					}
					dir = normalize(reflect(dir, en));
					if (dot(dir, planes[exit_plane].n_d.xyz) > 0.0) {
						dir = normalize(reflect(dir, planes[exit_plane].n_d.xyz));
					}
					pos -= planes[exit_plane].n_d.xyz * (T_EPS * 4.0);
				}
				if (max(max(throughput.x, throughput.y), max(throughput.z, throughput.w)) < THROUGHPUT_EPS) { break; }
			}
		}

		radiance = min(radiance, vec4(pc.rad_clamp));
		vec3 xyz = (radiance.x * cie_xyz(wl.x) + radiance.y * cie_xyz(wl.y)
			+ radiance.z * cie_xyz(wl.z) + radiance.w * cie_xyz(wl.w)) * pc.spectral_norm;
		if (FLAG_FLUOR && st.optic_fluor.w > 0.0 && fluor_absorbed > 0.0) {
			// Daylight fluorescence: pump-band losses re-emitted at the
			// authored line. Strength on the chromophore is the yield lever;
			// do not multiply by an extra gain (that was a matte wash on ruby).
			float pump = min(fluor_absorbed, 1.0);
			pump *= pump * (3.0 - 2.0 * pump); // ease-in: weak paths glow weakly
			xyz += cie_xyz(st.wear1.z) * (pump * st.optic_fluor.w * pc.spectral_norm);
		}
		total_xyz += xyz;
	}

	accum[idx] += vec4(total_xyz, total_cov);
}
