#version 450
// Lapidary print pass: XYZ accumulation -> display-ready sprite pixels.
// Two modes:
//   raw   — honest display transform (exposure + Reinhard + sRGB), for physics judgment
//   print — the HOUSE PRINT: sprite tonescale, highlight desat, OKLCh chroma
//           governor, black floor. Applied identically to baked clips and live
//           draws. It publishes; it never fakes grade or lighting.

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
	float pad;             // 44 -> 48
} pc;

const mat3 XYZ_TO_SRGB = mat3(
	3.2406, -0.9689, 0.0557,
	-1.5372, 1.8758, -0.2040,
	-0.4986, 0.0415, 1.0570);

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

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	if (pix.x >= pc.resolution.x || pix.y >= pc.resolution.y) { return; }
	vec4 acc = accum[uint(pix.y) * uint(pc.resolution.x) + uint(pix.x)];
	vec3 xyz = acc.xyz * pc.inv_samples;
	float cov = clamp(acc.w * pc.inv_samples, 0.0, 1.0);

	vec3 rgb = max(XYZ_TO_SRGB * xyz, vec3(0.0)) * pc.exposure;

	if (pc.raw != 0u) {
		rgb = rgb / (1.0 + rgb);
	} else {
		// Highlight desaturation before tone: clipped energy goes white-ish
		// smoothly instead of hue-skewing.
		float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
		if (lum > 1.0) {
			float f = pc.highlight_desat * (1.0 - 1.0 / lum);
			rgb = mix(rgb, vec3(lum), clamp(f, 0.0, 1.0));
		}
		// Extended Reinhard with white point (per channel, then contrast about mid-gray).
		float w2 = pc.white_point * pc.white_point;
		rgb = rgb * (vec3(1.0) + rgb / w2) / (vec3(1.0) + rgb);
		rgb = pow(max(rgb, vec3(0.0)) / 0.18, vec3(pc.contrast)) * 0.18;
		// Chroma governor in OKLCh: soft ceiling, forbidden neon.
		vec3 lab = srgb_to_oklab(clamp(rgb, vec3(0.0), vec3(1.0)));
		float chroma = length(lab.yz);
		if (chroma > pc.chroma_ceiling) {
			float over = chroma - pc.chroma_ceiling;
			float newc = pc.chroma_ceiling + over * pc.chroma_soft / (pc.chroma_soft + over);
			lab.yz *= newc / max(chroma, 1e-5);
			rgb = clamp(oklab_to_srgb(lab), vec3(0.0), vec3(1.0));
		}
		// Board black floor.
		rgb = pc.black_point + rgb * (1.0 - pc.black_point);
	}

	vec3 enc = vec3(srgb_encode(clamp(rgb.r, 0.0, 1.0)),
		srgb_encode(clamp(rgb.g, 0.0, 1.0)),
		srgb_encode(clamp(rgb.b, 0.0, 1.0)));
	// STRAIGHT alpha (Godot CanvasItem MIX blend expects it). Color stays
	// unmultiplied; coverage-0 pixels are zeroed to keep atlases clean.
	imageStore(out_img, pix, cov > 0.0 ? vec4(enc, cov) : vec4(0.0));
}
