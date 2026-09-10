#version 450
// Lapidary print pass: XYZ accumulation -> display-ready sprite pixels.
// Two modes:
//   raw   — honest display transform (exposure + Reinhard + sRGB), for physics judgment
//   print — the HOUSE PRINT: hue-preserving sprite tonescale, highlight desat,
//           OKLCh chroma governor, optional black floor. Applied identically
//           to baked clips and live draws. It publishes; it never fakes grade
//           or lighting.
//
// The tonescale acts on the maximum RGB component and rescales the pixel, so
// chromaticity (hue AND saturation) survives compression. Per-channel curves
// desaturate toward white as they compress — the "washed out" look.

layout(local_size_x = 8, local_size_y = 8) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Accum { vec4 accum[]; };
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D out_img;

layout(push_constant, std430) uniform P {
	ivec2 resolution;      // 0
	float inv_samples;     // 8
	float exposure;        // 12
	uint raw;              // 16
	float white_point;     // 20
	float contrast;        // 24
	float black_point;     // 28
	float chroma_ceiling;  // 32
	float chroma_soft;     // 36
	float highlight_desat; // 40
	float pad;             // 44
	vec4 m0;               // 48  XYZ -> linear sRGB, columns (includes the rig's
	vec4 m1;               // 64  as-shot white balance: Bradford CAT from the
	vec4 m2;               // 80  rig's spectral neutral to D65)   -> 96
	ivec2 source_resolution; // 96 accumulation dimensions; output can be smaller
	ivec2 padding;           // 104 -> 112
} pc;

float srgb_encode(float c) {
	return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

// OKLab (Ottosson). Linear sRGB in/out.
vec3 srgb_to_oklab(vec3 c) {
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	l = pow(max(l, 0.0), 1.0 / 3.0);
	m = pow(max(m, 0.0), 1.0 / 3.0);
	s = pow(max(s, 0.0), 1.0 / 3.0);
	return vec3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

vec3 oklab_to_srgb(vec3 lab) {
	float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
	float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
	float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
	l = l * l * l;
	m = m * m * m;
	s = s * s * s;
	return vec3(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

// Extended Reinhard with white point, then contrast about mid-grey.
float tonescale(float x) {
	float w2 = pc.white_point * pc.white_point;
	float y = x * (1.0 + x / w2) / (1.0 + x);
	return pow(max(y, 0.0) / 0.18, pc.contrast) * 0.18;
}

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	if (pix.x >= pc.resolution.x || pix.y >= pc.resolution.y) { return; }
	// Positive area reconstruction of the linear, coverage-associated master.
	// Resolve before the nonlinear print; a 2x bake is an exact 2x2 box resolve.
	vec2 scale = vec2(pc.source_resolution) / vec2(pc.resolution);
	vec2 lo = vec2(pix) * scale;
	vec2 hi = vec2(pix + 1) * scale;
	vec4 acc = vec4(0.0);
	for (int y = int(floor(lo.y)); y < int(ceil(hi.y)); y++) {
		for (int x = int(floor(lo.x)); x < int(ceil(hi.x)); x++) {
			vec2 overlap = max(vec2(0.0), min(hi, vec2(x + 1, y + 1)) - max(lo, vec2(x, y)));
			ivec2 src = clamp(ivec2(x, y), ivec2(0), pc.source_resolution - 1);
			acc += accum[src.y * pc.source_resolution.x + src.x] * overlap.x * overlap.y;
		}
	}
	acc /= scale.x * scale.y;
	// Recover conditional radiance before any nonlinear display operation.
	vec3 xyz = acc.w > 0.0 ? acc.xyz / acc.w : vec3(0.0);
	float cov = clamp(acc.w * pc.inv_samples, 0.0, 1.0);

	mat3 xyz_to_rgb = mat3(pc.m0.xyz, pc.m1.xyz, pc.m2.xyz);
	vec3 rgb = max(xyz_to_rgb * xyz, vec3(0.0)) * pc.exposure;

	if (pc.raw != 0u) {
		rgb = rgb / (1.0 + rgb);
	} else {
		// Highlight desaturation: clipped energy goes white-ish smoothly
		// (sensor-like) instead of turning neon.
		float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
		if (lum > 1.0) {
			float f = pc.highlight_desat * (1.0 - 1.0 / lum);
			rgb = mix(rgb, vec3(lum), clamp(f, 0.0, 1.0));
		}
		// Hue- and saturation-preserving tonescale on the max component.
		float m = max(rgb.r, max(rgb.g, rgb.b));
		if (m > 1e-6) {
			rgb *= tonescale(m) / m;
		}
		// Chroma governor in OKLCh: soft ceiling, forbidden neon.
		vec3 lab = srgb_to_oklab(rgb);
		float chroma = length(lab.yz);
		if (chroma > pc.chroma_ceiling) {
			float over = chroma - pc.chroma_ceiling;
			float newc = pc.chroma_ceiling + over * pc.chroma_soft / (pc.chroma_soft + over);
			lab.yz *= newc / max(chroma, 1e-5);
			rgb = clamp(oklab_to_srgb(lab), vec3(0.0), vec3(1.0));
		}
		// Optional black floor (0 = none).
		rgb = pc.black_point + rgb * (1.0 - pc.black_point);
	}

	vec3 enc = vec3(srgb_encode(clamp(rgb.r, 0.0, 1.0)),
		srgb_encode(clamp(rgb.g, 0.0, 1.0)),
		srgb_encode(clamp(rgb.b, 0.0, 1.0)));
	// STRAIGHT alpha (Godot CanvasItem MIX blend expects it). Color stays
	// unmultiplied; coverage-0 pixels are zeroed to keep atlases clean.
	imageStore(out_img, pix, cov > 0.0 ? vec4(enc, cov) : vec4(0.0));
}
