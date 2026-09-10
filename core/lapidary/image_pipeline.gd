class_name GemImagePipeline
extends RefCounted
## Filter in linear light with associated alpha. Display images are straight
## sRGB; linear master images carry coverage-weighted XYZ and need no display
## conversion. Never resize encoded straight-alpha sprite data directly.

static func resize_display(source: Image, width: int, height: int) -> Image:
	var linear := Image.create_empty(source.get_width(), source.get_height(), false, Image.FORMAT_RGBAF)
	for y in source.get_height():
		for x in source.get_width():
			var c := source.get_pixel(x, y).srgb_to_linear()
			linear.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
	# Bilinear area-preserving 2x reduction has positive weights: no alpha
	# overshoot or negative lobes along bright transparent facet boundaries.
	linear.resize(width, height, Image.INTERPOLATE_BILINEAR)
	var output := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var c := linear.get_pixel(x, y)
			if c.a > 1.0e-8:
				output.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a).linear_to_srgb())
	return output
