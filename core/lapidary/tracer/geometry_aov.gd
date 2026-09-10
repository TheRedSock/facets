class_name GemGeometryAov
extends RefCounted
## Primary visible boundary data, not refracted/internal appearance layers.
## Position/object normal and camera-forward distance use the representative
## nearest-center covered subpixel. IDs are discrete, never interpolated.
const STRIDE := 48
var width := 0
var height := 0
var coverage_side := 4
var data := PackedByteArray()

func record(x: int, y: int) -> Dictionary:
	if x < 0 or y < 0 or x >= width or y >= height or data.size() != width * height * STRIDE:
		return {}
	var offset := (y * width + x) * STRIDE
	return {"position_mm": Vector3(data.decode_float(offset), data.decode_float(offset + 4), data.decode_float(offset + 8)),
		"depth_mm": data.decode_float(offset + 12),
		"normal_object": Vector3(data.decode_float(offset + 16), data.decode_float(offset + 20), data.decode_float(offset + 24)),
		"coverage": data.decode_float(offset + 28), "instance": data.decode_s32(offset + 32),
		"facet": data.decode_s32(offset + 36), "region": data.decode_s32(offset + 40), "material": data.decode_s32(offset + 44)}

func normal_image() -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var value := record(x, y)
			var normal: Vector3 = value.normal_object * 0.5 + Vector3.ONE * 0.5
			image.set_pixel(x, y, Color(normal.x, normal.y, normal.z, value.coverage))
	return image

## Standalone lossless diagnostic payload. Content-addressed storage can wrap
## this byte string; it is not a game texture codec or a linear color master.
func encode() -> PackedByteArray:
	if data.size() != width * height * STRIDE or width < 1 or height < 1 or width > 8192 or height > 8192 or coverage_side not in [1, 2, 4, 8] or data.size() > GemArtifactStore.MAX_BLOB_BYTES:
		return PackedByteArray()
	var header := PackedByteArray()
	header.resize(20)
	header.encode_u32(0, 0x314f4147) # GAO1, little endian.
	header.encode_u32(4, width)
	header.encode_u32(8, height)
	header.encode_u32(12, coverage_side)
	header.encode_u32(16, data.size())
	header.append_array(data.compress(FileAccess.COMPRESSION_ZSTD))
	return header

static func decode(payload: PackedByteArray) -> GemGeometryAov:
	if payload.size() < 20 or payload.decode_u32(0) != 0x314f4147:
		return null
	var w := int(payload.decode_u32(4))
	var h := int(payload.decode_u32(8))
	var side := int(payload.decode_u32(12))
	var length := int(payload.decode_u32(16))
	if w < 1 or h < 1 or w > 8192 or h > 8192 or side not in [1, 2, 4, 8] or length != w * h * STRIDE or length > GemArtifactStore.MAX_BLOB_BYTES:
		return null
	var raw := payload.slice(20).decompress(length, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != length:
		return null
	for offset in range(0, length, STRIDE):
		for component in 8:
			if not is_finite(raw.decode_float(offset + component * 4)):
				return null
		var coverage := raw.decode_float(offset + 28)
		if coverage < 0 or coverage > 1 or coverage * side * side != roundf(coverage * side * side):
			return null
		if coverage > 0:
			var normal := Vector3(raw.decode_float(offset + 16), raw.decode_float(offset + 20), raw.decode_float(offset + 24))
			if absf(normal.length_squared() - 1) > 0.001 or raw.decode_float(offset + 12) <= 0:
				return null
			if raw.decode_s32(offset + 32) < 0 or raw.decode_s32(offset + 40) < 0 or raw.decode_s32(offset + 44) < 0:
				return null
		else:
			for component in range(8, 12):
				if raw.decode_s32(offset + component * 4) != -1:
					return null
	var result := GemGeometryAov.new()
	result.width = w
	result.height = h
	result.coverage_side = side
	result.data = raw
	return result
