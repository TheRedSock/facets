class_name GemStylePipeline
extends RefCounted
## Deterministic CPU display pass. No randomness, geometry, lighting or grades.
## Tint/saturation operate in linear sRGB; contrast/bands/contour in encoded sRGB.
## A separable square erosion defines an INNER contour without changing coverage.
static func apply(source: Image, style: GemStyle) -> Image:
	if source == null or source.is_compressed() or source.get_format() != Image.FORMAT_RGBA8:
		return null
	if style != null and not style.validate().is_empty():
		return null
	if style == null or style.is_identity():
		return source.duplicate()
	var width := source.get_width()
	var height := source.get_height()
	var pixels := source.get_data()
	var erosion := PackedFloat32Array()
	if style.contour_pixels > 0 and style.contour_opacity > 0:
		erosion = _erode_alpha(pixels, width, height, style.contour_pixels)
	var tint := style.tint.srgb_to_linear()
	for i in width * height:
		var offset := i * 4
		if pixels[offset + 3] == 0:
			pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0
			continue
		var color := Color(pixels[offset] / 255.0, pixels[offset + 1] / 255.0, pixels[offset + 2] / 255.0).srgb_to_linear()
		color *= tint
		var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
		color = Color(luminance, luminance, luminance).lerp(color, style.saturation).clamp().linear_to_srgb()
		for axis in 3:
			color[axis] = clampf((color[axis] - 0.5) * style.contrast + 0.5, 0, 1)
		if style.luminance_bands > 0:
			var tone := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			var level := roundf(tone * (style.luminance_bands - 1)) / (style.luminance_bands - 1)
			if tone > 1e-8:
				color = (color * (level / tone)).clamp()
		if not erosion.is_empty():
			var weight := 1.0 - erosion[i] / float(pixels[offset + 3])
			color = color.lerp(style.contour_color, clampf(weight, 0, 1) * style.contour_opacity)
		for axis in 3:
			pixels[offset + axis] = int(roundf(clampf(color[axis], 0, 1) * 255))
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)

static func _erode_alpha(pixels: PackedByteArray, width: int, height: int, radius: int) -> PackedFloat32Array:
	var horizontal := PackedFloat32Array()
	horizontal.resize(width * height)
	var result := PackedFloat32Array()
	result.resize(width * height)
	for y in height:
		for x in width:
			var minimum := 255.0
			for dx in range(-radius, radius + 1):
				minimum = minf(minimum, pixels[4 * (y * width + x + dx) + 3] if x + dx >= 0 and x + dx < width else 0)
			horizontal[y * width + x] = minimum
	for y in height:
		for x in width:
			var minimum := 255.0
			for dy in range(-radius, radius + 1):
				minimum = minf(minimum, horizontal[(y + dy) * width + x] if y + dy >= 0 and y + dy < height else 0)
			result[y * width + x] = minimum
	return result
