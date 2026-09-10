// Lapidary kernel — shared declarations (host-included into every compute
// shader via `#include "gem_common.glsl"`; no #version here).
//
// Buffer layouts are defined in KERNEL_CONTRACT.md.

struct Plane { vec4 n_d; vec4 aux; };          // aux: zone, polish (unused by kernel v3), reserved
struct Light { vec4 dir_cos; vec4 spd_pow; };  // spd_pow: spectrum offset, power, cos_inner, role(0key..3bounce,4blocker)
struct Stone {
	vec4 sell_b_size;      // sellmeier B xyz, size_mm
	vec4 sell_c_biref;     // sellmeier C xyz (um^2), signed birefringence dn
	vec4 scatter_zone;     // sigma_per_mm, hg_g, zoning_freq, zoning_contrast
	vec4 zone_axis_phase;  // zoning axis xyz, phase
	vec4 optic_fluor;      // optic axis xyz, fluorescence strength
	vec4 misc;             // fluor_nm (disabled), absorb_scale, nested_volume_present, rough_present
	ivec4 ranges0;         // plane_offset, plane_count, reserved, reserved
	ivec4 ranges1;         // absorb_offset, stone_flags (bit0 has_eray, bit1 dispersion_strong), pad, pad
};

struct Inst {
	vec4 quat;         // stone->world
	vec4 rig;          // rig_yaw (radians), ortho_half, key_mult, fill_mult
	vec4 rig2;         // rim_mult, bounce_mult, outside-bound camera distance, pad
	ivec4 which;       // stone_index, pad x3
};

layout(set = 0, binding = 0, std430) restrict readonly buffer Planes  { Plane planes[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer Lights  { Light lights[]; };
layout(set = 0, binding = 2, std430) restrict readonly buffer Absorb  { float absorb_mm[]; };
layout(set = 0, binding = 3, std430) restrict buffer Accum            { vec4 accum[]; };
// CIE tables: xbar/ybar/zbar/D65 at 1 nm over 380..780, shared by host and GPU.
layout(set = 0, binding = 4, std430) readonly buffer Standards { vec4 standard_spectra[]; };
layout(set = 0, binding = 5, std430) restrict readonly buffer Stones  { Stone stones[]; };
layout(set = 0, binding = 6, std430) restrict readonly buffer Insts   { Inst insts[]; };

layout(set = 0, binding = 15, std430) readonly buffer EmissionSpectra { float emission_spectra[]; };

const float T_EPS = 1e-5;
const float INF = 1e30;
const float PI = 3.14159265;
const float TAU = 6.2831853;

// ---------------------------------------------------------------- RNG / QMC
uint pcg(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}
float rnd(inout uint s) { return float(pcg(s)) * (1.0 / 4294967296.0); }

float radical_inverse(uint n, uint base) {
	float inv = 1.0 / float(base);
	float digit = inv;
	float result = 0.0;
	uint nn = n;
	for (int i = 0; i < 24; i++) {
		if (nn == 0u) { break; }
		result += float(nn % base) * digit;
		nn /= base;
		digit *= inv;
	}
	return result;
}

// Per-pixel Cranley-Patterson rotation of Halton sample n, dimension dim.
// The rotation is fixed per pixel; n is the GLOBAL sample index so every
// dispatch extends one low-discrepancy sequence.
float qmc(uint n, uint dim, vec2 pix_rot) {
	const uint bases[8] = uint[](2u, 3u, 5u, 7u, 11u, 13u, 17u, 19u);
	float rot = (dim == 0u) ? pix_rot.x : ((dim == 1u) ? pix_rot.y :
		fract(pix_rot.x * float(dim + 1u) * 0.6180339887 + pix_rot.y * float(dim) * 0.3819660113));
	return fract(radical_inverse(n + 1u, bases[dim]) + rot);
}
vec2 qmc2(uint n, uint d0, uint d1, vec2 pix_rot) { return vec2(qmc(n, d0, pix_rot), qmc(n, d1, pix_rot)); }

// ---------------------------------------------------------------- math
vec3 quat_rot(vec4 q, vec3 v) { return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v); }
vec4 quat_conj(vec4 q) { return vec4(-q.xyz, q.w); }
vec3 rot_y(vec3 v, float a) {
	float c = cos(a), s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void basis(vec3 n, out vec3 t1, out vec3 t2) {
	t1 = normalize(cross(n, abs(n.z) < 0.9 ? vec3(0, 0, 1) : vec3(1, 0, 0)));
	t2 = cross(n, t1);
}

// Unpolarised Fresnel reflectance; eta = n_incident / n_transmitted.
float fresnel_diel(float cos_i, float eta) {
	float s2 = eta * eta * (1.0 - cos_i * cos_i);
	if (s2 >= 1.0) { return 1.0; }
	float ct = sqrt(1.0 - s2);
	float rs = (eta * cos_i - ct) / (eta * cos_i + ct);
	float rp = (cos_i - eta * ct) / (cos_i + eta * ct);
	return 0.5 * (rs * rs + rp * rp);
}

float sellmeier(vec3 B, vec3 C, float wl_nm) {
	float l2 = (wl_nm * 1e-3) * (wl_nm * 1e-3);
	float s = 1.0;
	for (int i=0; i<3; ++i) { if (B[i] != 0.0) { s += B[i] * l2 / (l2 - C[i]); } }
	return sqrt(max(s, 1.0));
}

// ---------------------------------------------------------------- spectra
vec4 standard_spectrum(float wavelength) {
	if (wavelength < 380.0 || wavelength > 780.0) { return vec4(0.0); }
	float position = wavelength - 380.0;
	int index = int(position);
	return mix(standard_spectra[index], standard_spectra[min(index + 1, 400)], position - float(index));
}
vec3 cie_xyz(float wavelength) { return standard_spectrum(wavelength).xyz; }

float emission_at(float wavelength, int offset) {
	float position = clamp(wavelength - 380.0, 0.0, 400.0);
	int index = int(position);
	return mix(emission_spectra[offset + index], emission_spectra[offset + min(index + 1, 400)], position - float(index));
}
vec4 emission4(vec4 wl, float offset) {
	int index = int(offset);
	return vec4(emission_at(wl.x, index), emission_at(wl.y, index), emission_at(wl.z, index), emission_at(wl.w, index));
}

float absorb_at(int base, float wl_nm) {
	float f = clamp(wl_nm - 380.0, 0.0, 400.0);
	int i = int(f);
	return mix(absorb_mm[base + i], absorb_mm[base + min(i + 1, 400)], f - float(i));
}

float role_multiplier(float role, vec4 role_mult) {
	int r = int(role + 0.5);
	if (r == 0) { return role_mult.x; }
	if (r == 1) { return role_mult.y; }
	if (r == 2) { return role_mult.z; }
	if (r == 3) { return role_mult.w; }
	return 1.0;
}

// ---------------------------------------------------------------- environment
float cone_omega(float ci, float co) { return TAU * ((1.0 - ci) + 0.5 * (ci - co)); }

// Analytic rig radiance for 4 wavelengths. bg = (zenith, horizon, below,
// spectrum offset): all sources address the same compiled emission table.
// `fp` widens every cone by the angular footprint (flux-conserving: radiance
// scaled by the ratio of effective solid angles). Blockers always apply;
// with_lights = false returns the background only.
vec4 env_radiance_ex(vec3 dir, vec4 wl, float rig_yaw, vec4 role_mult, float fp,
		bool with_lights, vec4 bg, uint light_count) {
	float up = dir.y;
	float bgv = (up >= 0.0)
		? mix(bg.y, bg.x, smoothstep(0.0, 0.85, up))
		: mix(bg.y, bg.z, smoothstep(0.0, 0.6, -up));
	vec4 rad = emission4(wl, bg.w) * bgv;
	float blocker = 1.0;
	for (uint li = 0u; li < light_count; li++) {
		Light L = lights[li];
		vec3 ldir = rot_y(L.dir_cos.xyz, rig_yaw);
		float d = dot(dir, ldir);
		float cos_outer = L.dir_cos.w;
		float cos_inner = L.spd_pow.z;
		float role = L.spd_pow.w;
		float flux = 1.0;
		if (fp > 1e-5) {
			float R = acos(clamp(cos_outer, -1.0, 1.0));
			float Rf = min(R + fp, PI);
			float Ri = acos(clamp(cos_inner, -1.0, 1.0));
			float co_f = cos(Rf);
			float ci_f = cos(min(Ri + fp * 0.5, Rf));
			flux = cone_omega(cos_inner, cos_outer) / max(cone_omega(ci_f, co_f), 1e-8);
			cos_outer = co_f;
			cos_inner = ci_f;
		}
		float w = smoothstep(cos_outer, cos_inner, d);
		if (w <= 0.0) { continue; }
		if (role > 3.5) {
			blocker *= 1.0 - clamp(L.spd_pow.y, 0.0, 1.0) * w * flux;
			continue;
		}
		if (!with_lights) { continue; }
		float mult = role_multiplier(role, role_mult);
		rad += emission4(wl, L.spd_pow.x) * (L.spd_pow.y * w * mult * flux);
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

bool hull_inside(int off, int count, vec3 p, float margin) {
	for (int i = 0; i < count; i++) {
		if (dot(planes[off + i].n_d.xyz, p) > planes[off + i].n_d.w - margin) { return false; }
	}
	return true;
}
