class_name GemBakeStylizer
extends RefCounted

## Stylizer v7 — Image-space post-processing pipeline for offline traced gameplay bakes.
##
## Pass pipeline (execution order):
##  1. Haze               — clarity overlay for low-tier gems
##  2. Shadow Lift         — soft Hermite toe curve on luminance
##  3. Adaptive Contrast   — S-curve centered on image-specific midpoint
##  4. LGG Color Grade     — ASC CDL lift/gamma/gain (skip if neutral)
##  5. Warmth              — color temperature shift (skip if ~0.0)
##  6. Vibrance            — OKLCh chroma boost with vibrance weighting
##  7. Hue Shift           — OKLCh hue rotation (skip if ~0.0)
##  8. Clarity             — unsharp mask at facet-scale radius
##  9. Specular Punch      — multiplicative highlight boost
## 10. Brilliance          — specular peak enhancement + micro-glow
## 11. Edge Definition     — Sobel-guided local-color edge darkening
## 12. Bloom               — separable Gaussian, soft-knee threshold
## 13. Mix                 — lerp(original, result, stylize_mix)
##
## stylize_visual_quality modulates passes 3, 6, 8, 9, 11, 12.


# =============================================================================
# Main entry point
# =============================================================================

static func apply(image: Image, visual: GemVisualResource, request: Dictionary = {}) -> Image:
	if image == null or visual == null:
		return image
	var mix := clampf(visual.stylize_mix, 0.0, 1.0)
	if mix <= 0.0001:
		return image

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return image

	var pixel_count := width * height
	var vq := clampf(visual.stylize_visual_quality, 0.0, 1.0)

	# Unpack image into parallel arrays.
	var rgb: Array[Vector3] = []
	rgb.resize(pixel_count)
	var alpha := PackedFloat32Array()
	alpha.resize(pixel_count)
	for y in height:
		for x in width:
			var idx := _index(x, y, width)
			var pixel := image.get_pixel(x, y)
			rgb[idx] = Vector3(pixel.r, pixel.g, pixel.b)
			alpha[idx] = pixel.a

	# Preserve original for final mix.
	var original_rgb: Array[Vector3] = []
	original_rgb.resize(pixel_count)
	for idx in pixel_count:
		original_rgb[idx] = rgb[idx]

	# --- Pass 1: Haze ---
	_pass_haze(rgb, alpha, width, height, visual.stylize_haze, mix)

	# --- Pass 2: Shadow Lift ---
	_pass_shadow_lift(rgb, alpha, width, height, visual.stylize_shadow_lift, mix)

	# --- Pass 3: Adaptive Contrast ---
	_pass_contrast(rgb, alpha, width, height, visual.stylize_contrast, mix, vq)

	# --- Pass 4: LGG Color Grade ---
	var lift := Vector3(visual.stylize_lift_r, visual.stylize_lift_g, visual.stylize_lift_b)
	var gamma := Vector3(visual.stylize_gamma_r, visual.stylize_gamma_g, visual.stylize_gamma_b)
	var gain := Vector3(visual.stylize_gain_r, visual.stylize_gain_g, visual.stylize_gain_b)
	_pass_lgg(rgb, alpha, width, height, lift, gamma, gain)

	# --- Pass 5: Warmth ---
	_pass_warmth(rgb, alpha, width, height, visual.stylize_warmth, mix)

	# --- Passes 6+7: Vibrance + Hue Shift (combined OKLab round-trip) ---
	_pass_vibrance_and_hue(rgb, alpha, width, height,
		visual.stylize_vibrance, visual.stylize_hue_shift, mix, vq)

	# --- Pass 8: Clarity ---
	_pass_clarity(rgb, alpha, width, height, visual.stylize_clarity, mix, vq)

	# --- Pass 9: Specular Punch ---
	_pass_specular_punch(rgb, alpha, width, height, visual.stylize_specular_punch, mix, vq)

	# --- Pass 10: Brilliance ---
	_pass_brilliance(rgb, alpha, width, height, visual.stylize_brilliance, mix)

	# --- Pass 11: Edge Definition ---
	_pass_edge_definition(rgb, alpha, width, height, visual.stylize_edge_definition, mix, vq)

	# --- Pass 12: Bloom ---
	_pass_bloom(rgb, alpha, width, height,
		visual.stylize_bloom_gain, visual.stylize_bloom_threshold, mix, vq)

	# --- Pass 13: Mix ---
	for idx in pixel_count:
		rgb[idx] = original_rgb[idx].lerp(rgb[idx], mix)

	return _build_image_from_rgb_alpha(rgb, alpha, width, height)


# =============================================================================
# Pass implementations
# =============================================================================

# -- Pass 1: Haze --
# Simulates reduced optical clarity for low-tier gems by blending the interior
# toward a softened, desaturated, lifted version of itself.

static func _pass_haze(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float,
) -> void:
	if amount <= 0.0001:
		return
	var max_dim := maxi(w, h)
	var haze_radius := maxi(roundi(float(max_dim) * 0.04), 2)
	var haze_blur := _gaussian_blur_rgb(rgb, alpha, w, h, haze_radius, true)
	var effective := amount * mix
	for idx in rgb.size():
		var a := alpha[idx]
		if a <= 0.0001:
			continue
		# Build haze target: desaturated + lifted.
		var blurred: Vector3 = haze_blur[idx]
		var haze_target := _adjust_saturation(blurred, -0.6)
		haze_target = haze_target * 0.85 + Vector3(0.15, 0.15, 0.15)
		# Interior mask: preserve silhouette edges.
		var mask := smoothstep(0.15, 0.8, a)
		rgb[idx] = rgb[idx].lerp(haze_target, mask * effective)


# -- Pass 2: Shadow Lift --
# Cubic Hermite toe curve that smoothly recovers shadow readability.

static func _pass_shadow_lift(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float,
) -> void:
	var toe := amount * mix
	if toe <= 0.0001:
		return
	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var luma := _luma(rgb[idx])
		if luma >= toe or luma <= 0.0001:
			continue
		var t := luma / toe
		var remapped := toe * (3.0 * t * t - 2.0 * t * t * t)
		rgb[idx] = _set_luma(rgb[idx], remapped)


# -- Pass 3: Adaptive Contrast --
# S-curve centered on the image's actual tonal midpoint, not a fixed 0.5.
# Modulated by visual_quality.

static func _pass_contrast(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float, vq: float,
) -> void:
	if amount <= 0.0001:
		return
	var effective := amount * mix * lerpf(0.7, 1.0, vq)

	# Build 256-bin luma histogram (opaque pixels only).
	var bins := PackedInt32Array()
	bins.resize(256)
	bins.fill(0)
	var opaque_count := 0
	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var bin := clampi(int(floor(_luma(rgb[idx]) * 255.0)), 0, 255)
		bins[bin] += 1
		opaque_count += 1

	if opaque_count < 4:
		return

	# Find p15, p85 percentiles.
	var p15_target := int(floor(float(opaque_count) * 0.15))
	var p85_target := int(floor(float(opaque_count) * 0.85))
	var cumulative := 0
	var p15 := 0.5
	var p85 := 0.5
	var found_p15 := false
	var found_p85 := false
	for i in 256:
		cumulative += bins[i]
		if not found_p15 and cumulative >= p15_target:
			p15 = float(i) / 255.0
			found_p15 = true
		if not found_p85 and cumulative >= p85_target:
			p85 = float(i) / 255.0
			found_p85 = true
			break

	var midpoint := (p15 + p85) * 0.5
	var spread := maxf(p85 - p15, 0.05)

	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var luma := _luma(rgb[idx])
		var centered := (luma - midpoint) / spread
		var contrasted := midpoint + centered * spread * (1.0 + effective * 0.85)
		contrasted += signf(centered) * pow(absf(centered), 1.3) * effective * 0.12
		rgb[idx] = _set_luma(rgb[idx], clampf(contrasted, 0.0, 1.0))


# -- Pass 4: LGG Color Grade --
# ASC CDL-style per-channel lift/gamma/gain. Skips entirely when all neutral.

static func _pass_lgg(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, lift: Vector3, gamma: Vector3, gain: Vector3,
) -> void:
	# Check if all 9 values are near zero.
	var epsilon := 0.0001
	if (absf(lift.x) < epsilon and absf(lift.y) < epsilon and absf(lift.z) < epsilon
		and absf(gamma.x) < epsilon and absf(gamma.y) < epsilon and absf(gamma.z) < epsilon
		and absf(gain.x) < epsilon and absf(gain.y) < epsilon and absf(gain.z) < epsilon):
		return

	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var c: Vector3 = rgb[idx]
		# Per-channel: lifted → gained → gamma-corrected.
		c.x = _lgg_channel(c.x, lift.x, gamma.x, gain.x)
		c.y = _lgg_channel(c.y, lift.y, gamma.y, gain.y)
		c.z = _lgg_channel(c.z, lift.z, gamma.z, gain.z)
		rgb[idx] = _clamp_rgb(c)


static func _lgg_channel(v: float, l: float, g: float, gn: float) -> float:
	var lifted := v + l
	var gained := lifted * (1.0 + gn)
	var exponent := 1.0 / (1.0 + g)
	return pow(maxf(gained, 0.0), exponent)


# -- Pass 5: Warmth --
# Per-gem color temperature shift. Warm = boost red, reduce blue.

static func _pass_warmth(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float,
) -> void:
	var effective := amount * mix
	if absf(effective) <= 0.0001:
		return
	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var c: Vector3 = rgb[idx]
		var r_shift := effective * 0.06 * (1.0 - c.x)
		var b_shift := -effective * 0.06 * (1.0 - c.z)
		var g_comp := -effective * 0.02 * (1.0 - c.y)
		rgb[idx] = _clamp_rgb(c + Vector3(r_shift, g_comp, b_shift))


# -- Passes 6+7: Vibrance + Hue Shift (combined OKLab round-trip) --
# Single OKLab conversion handles both chroma boost and hue rotation.

static func _pass_vibrance_and_hue(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, vibrance: float, hue_shift_deg: float,
	mix: float, vq: float,
) -> void:
	var effective_vib := vibrance * mix * lerpf(0.5, 1.25, vq)
	var shift_rad := deg_to_rad(hue_shift_deg)
	var do_vibrance := effective_vib > 0.0001
	var do_hue := absf(hue_shift_deg) > 0.01
	if not do_vibrance and not do_hue:
		return

	var max_c := 0.37
	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var lab := _srgb_to_oklab(rgb[idx])
		var ok_c := sqrt(lab.y * lab.y + lab.z * lab.z)
		var ok_h := atan2(lab.z, lab.y)

		if do_vibrance and ok_c > 0.0001:
			var chroma_ratio := clampf(ok_c / max_c, 0.0, 1.0)
			var boost := effective_vib * (1.0 - chroma_ratio * 0.7)
			ok_c *= (1.0 + boost)

		if do_hue:
			ok_h += shift_rad

		lab.y = ok_c * cos(ok_h)
		lab.z = ok_c * sin(ok_h)
		rgb[idx] = _clamp_rgb(_oklab_to_srgb(lab))


# -- Pass 8: Clarity --
# Unsharp mask at facet-scale radius. Modulated by visual_quality.

static func _pass_clarity(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float, vq: float,
) -> void:
	if amount <= 0.0001:
		return
	var effective := amount * mix * lerpf(0.6, 1.0, vq)
	var max_dim := maxi(w, h)
	var radius := maxi(roundi(float(max_dim) * 0.02), 2)
	var blurred := _gaussian_blur_rgb(rgb, alpha, w, h, radius, true)

	for idx in rgb.size():
		if alpha[idx] <= 0.0001:
			continue
		var detail: Vector3 = rgb[idx] - blurred[idx]
		rgb[idx] = _clamp_rgb(rgb[idx] + detail * effective)


# -- Pass 9: Specular Punch --
# Multiplicative highlight brightness boost. Color-preserving.
# Modulated by visual_quality.

static func _pass_specular_punch(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float, vq: float,
) -> void:
	if amount <= 0.0001:
		return
	var effective := amount * mix * lerpf(0.15, 1.0, vq)
	var threshold := 0.65

	for idx in rgb.size():
		var a := alpha[idx]
		if a <= 0.0001:
			continue
		var luma := _luma(rgb[idx])
		var mask := smoothstep(threshold, 1.0, luma) * smoothstep(0.08, 0.7, a)
		var boost := 1.0 + effective * 0.4 * mask
		rgb[idx] = _clamp_rgb(rgb[idx] * boost)


# -- Pass 10: Brilliance --
# Enhances specular "life" for high-tier gems by boosting existing specular
# peaks and adding optional micro-glow around them.

static func _pass_brilliance(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float,
) -> void:
	if amount <= 0.0001:
		return
	var effective := amount * mix
	var pixel_count := w * h

	# Build peak mask: bright + relatively unsaturated pixels.
	var peak_mask := PackedFloat32Array()
	peak_mask.resize(pixel_count)
	for idx in pixel_count:
		var a := alpha[idx]
		if a <= 0.0001:
			peak_mask[idx] = 0.0
			continue
		var luma := _luma(rgb[idx])
		var chroma := _chroma(rgb[idx])
		peak_mask[idx] = smoothstep(0.7, 0.95, luma) * smoothstep(0.3, 0.0, chroma)
		peak_mask[idx] *= smoothstep(0.1, 0.8, a)

	# Multiplicative peak boost.
	for idx in pixel_count:
		if peak_mask[idx] <= 0.0001:
			continue
		var boost := 1.0 + effective * 0.6 * peak_mask[idx]
		rgb[idx] = _clamp_rgb(rgb[idx] * boost)

	# Micro-glow around peaks (only when amount is significant).
	if effective > 0.3:
		var glow_seed: Array[Vector3] = []
		glow_seed.resize(pixel_count)
		for idx in pixel_count:
			glow_seed[idx] = rgb[idx] * peak_mask[idx]
		var glow := _gaussian_blur_rgb(glow_seed, peak_mask, w, h, 2, false)
		var glow_strength := effective * 0.3
		for idx in pixel_count:
			if alpha[idx] <= 0.0001:
				continue
			rgb[idx] = _clamp_rgb(rgb[idx] + glow[idx] * glow_strength)


# -- Pass 11: Edge Definition --
# Sobel-guided local-color edge darkening. Modulated by visual_quality.

static func _pass_edge_definition(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, amount: float, mix: float, vq: float,
) -> void:
	if amount <= 0.0001:
		return
	var effective := amount * mix * lerpf(0.5, 1.0, vq)
	var edge_mask := _sobel_magnitude(rgb, alpha, w, h)

	for idx in rgb.size():
		var a := alpha[idx]
		if a <= 0.0001:
			continue
		var edge_val := edge_mask[idx]
		if edge_val <= 0.0001:
			continue
		# Local ink: darkened + slightly desaturated local pixel.
		var local_ink := _adjust_saturation(rgb[idx], -0.15) * 0.3
		var blend_amount := effective * edge_val * smoothstep(0.1, 0.8, a)
		rgb[idx] = rgb[idx].lerp(local_ink, blend_amount)


# -- Pass 12: Bloom --
# Soft glow around highlights. Modulated by visual_quality via smoothstep.

static func _pass_bloom(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, gain: float, threshold: float, mix: float, vq: float,
) -> void:
	if gain <= 0.0001:
		return
	var effective_gain := gain * mix * lerpf(0.0, 1.0, smoothstep(0.3, 0.7, vq))
	if effective_gain <= 0.0001:
		return

	var max_dim := maxi(w, h)
	var bloom_radius := maxi(roundi(float(max_dim) * 0.06), 3)
	var knee := 0.1
	var pixel_count := w * h

	# Extract bloom seed with soft knee.
	var bloom_seed: Array[Vector3] = []
	bloom_seed.resize(pixel_count)
	var bloom_weights := PackedFloat32Array()
	bloom_weights.resize(pixel_count)
	for idx in pixel_count:
		var a := alpha[idx]
		if a <= 0.0001:
			bloom_seed[idx] = Vector3.ZERO
			bloom_weights[idx] = 0.0
			continue
		var luma := _luma(rgb[idx])
		var weight := smoothstep(threshold - knee, threshold + knee, luma)
		weight *= smoothstep(0.1, 0.8, a)
		bloom_seed[idx] = rgb[idx] * weight
		bloom_weights[idx] = weight

	# Separable Gaussian blur on the seed.
	var bloom := _gaussian_blur_rgb(bloom_seed, bloom_weights, w, h, bloom_radius, false)

	# Additive color-preserving blend.
	for idx in pixel_count:
		if alpha[idx] <= 0.0001:
			continue
		rgb[idx] = _clamp_rgb(rgb[idx] + bloom[idx] * effective_gain)


# =============================================================================
# OKLab / OKLCh color space utilities
# =============================================================================

static func _srgb_to_oklab(c: Vector3) -> Vector3:
	# sRGB → linear.
	var rl := _srgb_comp_to_linear(c.x)
	var gl := _srgb_comp_to_linear(c.y)
	var bl := _srgb_comp_to_linear(c.z)
	# Linear RGB → LMS (cone response).
	var l := 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl
	var m := 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl
	var s := 0.0883024619 * rl + 0.2220049494 * gl + 0.6736926867 * bl
	# Cube root (LMS → LMS').
	l = _cbrt(l)
	m = _cbrt(m)
	s = _cbrt(s)
	# LMS' → OKLab.
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
	)


static func _oklab_to_srgb(lab: Vector3) -> Vector3:
	# OKLab → LMS'.
	var l := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
	# Cube (LMS' → LMS).
	l = l * l * l
	m = m * m * m
	s = s * s * s
	# LMS → linear RGB.
	var rl := +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	var gl := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	var bl := -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	# Linear → sRGB.
	return Vector3(
		_linear_comp_to_srgb(rl),
		_linear_comp_to_srgb(gl),
		_linear_comp_to_srgb(bl),
	)


static func _srgb_comp_to_linear(v: float) -> float:
	if v <= 0.04045:
		return v / 12.92
	return pow((v + 0.055) / 1.055, 2.4)


static func _linear_comp_to_srgb(v: float) -> float:
	if v <= 0.0031308:
		return maxf(v * 12.92, 0.0)
	return clampf(1.055 * pow(maxf(v, 0.0), 1.0 / 2.4) - 0.055, 0.0, 1.0)


static func _cbrt(x: float) -> float:
	if x >= 0.0:
		return pow(x, 1.0 / 3.0)
	return -pow(-x, 1.0 / 3.0)


# =============================================================================
# Gaussian blur approximation (3-pass box blur, alpha-weighted)
# =============================================================================
# Replaces the exact separable Gaussian with a 3-pass iterated box blur that
# approximates the Gaussian kernel.  Complexity drops from O(w*h*radius) per
# separable pass to O(w*h) per pass using a sliding-window accumulator.
# At 512px draw size with bloom radius ~31, this is ~10x faster.

static func _gaussian_blur_rgb(
	rgb: Array[Vector3], weights: PackedFloat32Array,
	w: int, h: int, radius: int, fallback_to_source: bool,
) -> Array[Vector3]:
	var count := rgb.size()
	var result: Array[Vector3] = []
	result.resize(count)
	if radius <= 0:
		for idx in count:
			result[idx] = rgb[idx] if fallback_to_source else Vector3.ZERO
		return result

	# Compute box radius for 3-pass approximation of Gaussian(sigma).
	# sigma = radius / 2.5 (matches the 3-sigma coverage of the old kernel).
	# For N box passes with width W: N*(W²-1)/12 = sigma²
	# W = sqrt(12*sigma²/N + 1), rounded to nearest odd integer.
	var sigma := float(radius) / 2.5
	var box_w_f := sqrt(12.0 * sigma * sigma / 3.0 + 1.0)
	var box_w_i := roundi(box_w_f)
	if box_w_i % 2 == 0:
		box_w_i += 1
	var box_r := maxi((box_w_i - 1) / 2, 1)

	# Premultiply: P = rgb * weight, then blur P and w independently.
	# Reconstruct at the end: result = blurred_P / blurred_w.
	var premul: Array[Vector3] = []
	premul.resize(count)
	var w_buf := weights.duplicate()
	for idx in count:
		premul[idx] = rgb[idx] * weights[idx]

	# 3 passes of separable (H+V) box blur.
	for _pass in 3:
		premul = _box_blur_h_vec3(premul, w, h, box_r)
		premul = _box_blur_v_vec3(premul, w, h, box_r)
		w_buf = _box_blur_h_float(w_buf, w, h, box_r)
		w_buf = _box_blur_v_float(w_buf, w, h, box_r)

	# Reconstruct from premultiplied data.
	for idx in count:
		if w_buf[idx] > 0.0001:
			result[idx] = premul[idx] / w_buf[idx]
		elif fallback_to_source:
			result[idx] = rgb[idx]
		else:
			result[idx] = Vector3.ZERO

	return result


# -- Sliding-window box blur helpers --
# Each processes one axis (H or V) in a single O(w*h) pass.

static func _box_blur_h_vec3(src: Array[Vector3], w: int, h: int, r: int) -> Array[Vector3]:
	var count := src.size()
	var dst: Array[Vector3] = []
	dst.resize(count)
	for y in h:
		var base := y * w
		var sum := Vector3.ZERO
		var initial_right := mini(r, w - 1)
		for i in range(0, initial_right + 1):
			sum += src[base + i]
		var wc := initial_right + 1
		for x in w:
			dst[base + x] = sum / float(wc)
			var add_x := x + r + 1
			if add_x < w:
				sum += src[base + add_x]
				wc += 1
			var rem_x := x - r
			if rem_x >= 0:
				sum -= src[base + rem_x]
				wc -= 1
	return dst


static func _box_blur_v_vec3(src: Array[Vector3], w: int, h: int, r: int) -> Array[Vector3]:
	var count := src.size()
	var dst: Array[Vector3] = []
	dst.resize(count)
	for x in w:
		var sum := Vector3.ZERO
		var initial_bottom := mini(r, h - 1)
		for i in range(0, initial_bottom + 1):
			sum += src[i * w + x]
		var wc := initial_bottom + 1
		for y in h:
			dst[y * w + x] = sum / float(wc)
			var add_y := y + r + 1
			if add_y < h:
				sum += src[add_y * w + x]
				wc += 1
			var rem_y := y - r
			if rem_y >= 0:
				sum -= src[rem_y * w + x]
				wc -= 1
	return dst


static func _box_blur_h_float(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var dst := PackedFloat32Array()
	dst.resize(src.size())
	for y in h:
		var base := y * w
		var sum := 0.0
		var initial_right := mini(r, w - 1)
		for i in range(0, initial_right + 1):
			sum += src[base + i]
		var wc := initial_right + 1
		for x in w:
			dst[base + x] = sum / float(wc)
			var add_x := x + r + 1
			if add_x < w:
				sum += src[base + add_x]
				wc += 1
			var rem_x := x - r
			if rem_x >= 0:
				sum -= src[base + rem_x]
				wc -= 1
	return dst


static func _box_blur_v_float(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var dst := PackedFloat32Array()
	dst.resize(src.size())
	for x in w:
		var sum := 0.0
		var initial_bottom := mini(r, h - 1)
		for i in range(0, initial_bottom + 1):
			sum += src[i * w + x]
		var wc := initial_bottom + 1
		for y in h:
			dst[y * w + x] = sum / float(wc)
			var add_y := y + r + 1
			if add_y < h:
				sum += src[add_y * w + x]
				wc += 1
			var rem_y := y - r
			if rem_y >= 0:
				sum -= src[rem_y * w + x]
				wc -= 1
	return dst


# =============================================================================
# Sobel edge detection
# =============================================================================

static func _sobel_magnitude(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int,
) -> PackedFloat32Array:
	var count := w * h
	var result := PackedFloat32Array()
	result.resize(count)

	for y in h:
		for x in w:
			var idx := _index(x, y, w)
			if alpha[idx] <= 0.0001:
				result[idx] = 0.0
				continue
			# Sample 3x3 luma neighbourhood.
			var tl := _sample_luma(rgb, alpha, w, h, x - 1, y - 1)
			var tc := _sample_luma(rgb, alpha, w, h, x,     y - 1)
			var tr := _sample_luma(rgb, alpha, w, h, x + 1, y - 1)
			var ml := _sample_luma(rgb, alpha, w, h, x - 1, y)
			var mr := _sample_luma(rgb, alpha, w, h, x + 1, y)
			var bl := _sample_luma(rgb, alpha, w, h, x - 1, y + 1)
			var bc := _sample_luma(rgb, alpha, w, h, x,     y + 1)
			var br := _sample_luma(rgb, alpha, w, h, x + 1, y + 1)
			# Sobel kernels.
			var gx := (-tl + tr) + (-2.0 * ml + 2.0 * mr) + (-bl + br)
			var gy := (-tl - 2.0 * tc - tr) + (bl + 2.0 * bc + br)
			var mag := sqrt(gx * gx + gy * gy) * 2.0  # Scale for visibility.
			result[idx] = clampf(mag, 0.0, 1.0) * smoothstep(0.05, 0.8, alpha[idx])

	return result


static func _sample_luma(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int, x: int, y: int,
) -> float:
	if x < 0 or x >= w or y < 0 or y >= h:
		return 0.0
	var idx := _index(x, y, w)
	if alpha[idx] <= 0.0001:
		return 0.0
	return _luma(rgb[idx])


# =============================================================================
# Shared utilities
# =============================================================================

static func _build_image_from_rgb_alpha(
	rgb: Array[Vector3], alpha: PackedFloat32Array,
	w: int, h: int,
) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for idx in rgb.size():
		var c: Vector3 = rgb[idx]
		var a := alpha[idx] if idx < alpha.size() else 1.0
		var bi := idx * 4
		bytes[bi] = int(round(clampf(c.x, 0.0, 1.0) * 255.0))
		bytes[bi + 1] = int(round(clampf(c.y, 0.0, 1.0) * 255.0))
		bytes[bi + 2] = int(round(clampf(c.z, 0.0, 1.0) * 255.0))
		bytes[bi + 3] = int(round(clampf(a, 0.0, 1.0) * 255.0))
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)


static func _adjust_saturation(color: Vector3, amount: float) -> Vector3:
	if is_zero_approx(amount):
		return color
	var luma := _luma(color)
	var gray := Vector3.ONE * luma
	return gray.lerp(color, 1.0 + amount)


static func _set_luma(color: Vector3, target_luma: float) -> Vector3:
	var current_luma := _luma(color)
	if current_luma <= 0.0001:
		return Vector3.ONE * target_luma
	return _clamp_rgb(color * (target_luma / current_luma))


static func _index(x: int, y: int, w: int) -> int:
	return y * w + x


static func _luma(color: Vector3) -> float:
	return color.dot(Vector3(0.2126, 0.7152, 0.0722))


static func _chroma(color: Vector3) -> float:
	return maxf(color.x, maxf(color.y, color.z)) - minf(color.x, minf(color.y, color.z))


static func _clamp_rgb(color: Vector3) -> Vector3:
	return Vector3(
		clampf(color.x, 0.0, 1.0),
		clampf(color.y, 0.0, 1.0),
		clampf(color.z, 0.0, 1.0),
	)
