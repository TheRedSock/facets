class_name GemPagePacker
extends RefCounted
## Delivery pages are grouped by specimen, bounded, trimmed, and pixel-deduped.
## Masters/checkpoints never ship. Mipmaps are intentionally absent: resolution
## variants reuse masters and avoid cross-frame bleeding in atlas mip chains.
var store: GemArtifactStore
var output: String
var page_edge := 512
var codec := "webp_lossless"
var maximum_composite_rmse_lsb := 3.0
var maximum_alpha_rmse_lsb := 2.0
var last_error := ""
const PAD := 2

func _init(source: GemArtifactStore, destination: String) -> void:
	store = source
	output = destination

func pack(clips: Dictionary) -> Dictionary:
	var guard := GemStoreGuard.enter(store.root, "delivery-pack")
	if guard == null:
		return _fail("Artifact store is undergoing maintenance")
	var result := _pack_active(clips)
	guard.release()
	return result

func _pack_active(clips: Dictionary) -> Dictionary:
	last_error = ""
	if page_edge < 16 or page_edge > 8192 or page_edge % 4 != 0 or codec not in ["webp_lossless", "bc7", "astc4x4"]:
		return _fail("Invalid page size or compression profile")
	var banks := {}
	var index := {"schema": 1, "codec": codec, "pages": {}, "frames": {}, "clips": clips.duplicate(true)}
	for clip_key: String in clips:
		var bank := clip_key.get_slice("/", 0)
		if not banks.has(bank):
			banks[bank] = {}
		for id: String in clips[clip_key]["frames"]:
			banks[bank][id] = true
	var bank_keys := banks.keys()
	bank_keys.sort()
	for bank: String in bank_keys:
		var frame_keys: Array = banks[bank].keys()
		frame_keys.sort()
		var page := Image.create(page_edge, page_edge, false, Image.FORMAT_RGBA8)
		var placement := {"x": 0, "y": 0, "row_h": 0, "used_w": 0, "used_h": 0, "entries": {}}
		var pixels := {}
		for key: String in frame_keys:
			if index["frames"].has(key):
				continue
			var record := store.read(key)
			if record.is_empty() or record["metadata"].get("kind") != "display":
				return _fail("Missing or corrupt rendered frame: " + key)
			var image := Image.new()
			if image.load_webp_from_buffer(record["payload"]) != OK:
				return _fail("Cannot decode rendered frame: " + key)
			image.convert(Image.FORMAT_RGBA8)
			var pixel_key := GemContentIdentity.digest([image.get_size(), image.get_data()])
			if pixels.has(pixel_key):
				index["frames"][key] = index["frames"][pixels[pixel_key]]
				continue
			var trim := image.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
			if trim.size == Vector2i.ZERO:
				trim = Rect2i(0, 0, 1, 1)
			var crop := image.get_region(trim)
			var needed := crop.get_size() + Vector2i.ONE * PAD * 2
			if needed.x > page_edge or needed.y > page_edge:
				return _fail("Frame exceeds page limit; select a larger page profile")
			if placement["x"] + needed.x > page_edge:
				placement["x"] = 0
				placement["y"] += placement["row_h"]
				placement["row_h"] = 0
			if placement["y"] + needed.y > page_edge:
				if not _publish_page(page, placement, index):
					return {}
				page = Image.create(page_edge, page_edge, false, Image.FORMAT_RGBA8)
				placement = {"x": 0, "y": 0, "row_h": 0, "used_w": 0, "used_h": 0, "entries": {}}
			var position := Vector2i(placement["x"] + PAD, placement["y"] + PAD)
			crop = bleed_rgb(crop, 3)
			page.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), position)
			# Transparent padding inherits boundary RGB, preserving straight-alpha
			# bilinear filtering while keeping coverage zero outside the frame.
			for y in range(-PAD, crop.get_height() + PAD):
				for x in range(-PAD, crop.get_width() + PAD):
					if x >= 0 and y >= 0 and x < crop.get_width() and y < crop.get_height():
						continue
					var color := crop.get_pixel(clampi(x, 0, crop.get_width() - 1), clampi(y, 0, crop.get_height() - 1))
					color.a = 0.0
					page.set_pixelv(position + Vector2i(x, y), color)
			var frame := {"page": "", "rect": [position.x, position.y, crop.get_width(), crop.get_height()],
				"offset": [trim.position.x, trim.position.y], "size": [image.get_width(), image.get_height()]}
			index["frames"][key] = frame
			placement["entries"][key] = frame
			pixels[pixel_key] = key
			placement["x"] += needed.x
			placement["row_h"] = maxi(placement["row_h"], needed.y)
			placement["used_w"] = maxi(placement["used_w"], placement["x"])
			placement["used_h"] = maxi(placement["used_h"], placement["y"] + needed.y)
		if not placement["entries"].is_empty() and not _publish_page(page, placement, index):
			return {}
	var disk_bytes := 0
	var gpu_bytes := 0
	for page: Dictionary in index["pages"].values():
		disk_bytes += page["bytes"]
		gpu_bytes += page["gpu_bytes"]
	index["statistics"] = {"page_count": index["pages"].size(), "disk_bytes": disk_bytes, "all_pages_gpu_bytes": gpu_bytes, "frame_count": index["frames"].size()}
	if not GemArtifactStore.atomic_write(output.path_join("library.json"), JSON.stringify(index, "\t").to_utf8_buffer()):
		return _fail("Cannot publish delivery library")
	return index

func _publish_page(source: Image, placement: Dictionary, index: Dictionary) -> bool:
	var size := Vector2i(int(ceil(placement["used_w"] / 4.0)) * 4, int(ceil(placement["used_h"] / 4.0)) * 4)
	var page := source.get_region(Rect2i(Vector2i.ZERO, size))
	var bytes: PackedByteArray
	var format := Image.FORMAT_RGBA8
	var gpu_bytes := size.x * size.y * 4
	var quality := {"composite_rmse_lsb": 0.0, "alpha_rmse_lsb": 0.0}
	if codec == "webp_lossless":
		bytes = page.save_webp_to_buffer(false)
	else:
		var original := page.get_data()
		var error := page.compress(Image.COMPRESS_BPTC if codec == "bc7" else Image.COMPRESS_ASTC)
		if error != OK:
			_fail("Selected GPU texture encoder unavailable: " + codec)
			return false
		bytes = page.get_data()
		format = page.get_format()
		gpu_bytes = bytes.size()
		var decoded: Image = page.duplicate()
		if decoded.decompress() != OK:
			_fail("Cannot validate compressed page")
			return false
		decoded.convert(Image.FORMAT_RGBA8)
		# Gate each occupied frame separately. Empty atlas space must not dilute
		# errors in small stones or allow one poor frame to hide among good ones.
		var uncompressed := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, original)
		for frame: Dictionary in placement["entries"].values():
			var r: Array = frame["rect"]
			var rect := Rect2i(r[0], r[1], r[2], r[3])
			var measured := compression_error(uncompressed.get_region(rect).get_data(), decoded.get_region(rect).get_data())
			for metric: String in measured:
				quality[metric] = maxf(quality[metric], measured[metric])
		if quality["composite_rmse_lsb"] > maximum_composite_rmse_lsb or quality["alpha_rmse_lsb"] > maximum_alpha_rmse_lsb:
			_fail("Compression exceeds delivery error budget: %s" % quality)
			return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var payload_hash := hash.finish().hex_encode()
	# Raw block payloads do not encode dimensions: identical bytes can represent
	# different page shapes. Include the interpretation in page identity.
	var key := GemContentIdentity.digest(["delivery-page-v1", size, format, codec, bytes])
	var relative := "pages/" + key + ".gpage"
	if bytes.is_empty() or not GemArtifactStore.atomic_write(output.path_join(relative), bytes):
		_fail("Cannot publish delivery page")
		return false
	index["pages"][key] = {"path": relative, "width": size.x, "height": size.y, "format": format,
		"codec": codec, "bytes": bytes.size(), "gpu_bytes": gpu_bytes, "sha256": payload_hash, "quality": quality}
	for frame: Dictionary in placement["entries"].values():
		frame["page"] = key
	return true

static func bleed_rgb(source: Image, radius: int) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var bytes := source.get_data()
	var filled := PackedByteArray()
	filled.resize(width * height)
	for i in filled.size():
		filled[i] = 1 if bytes[i * 4 + 3] > 0 else 0
	for step in radius:
		var next := filled.duplicate()
		for y in height:
			for x in width:
				var i := y * width + x
				if filled[i]:
					continue
				for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var p := Vector2i(x, y) + direction
					if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
						continue
					var neighbor := p.y * width + p.x
					if filled[neighbor]:
						for channel in 3:
							bytes[i * 4 + channel] = bytes[neighbor * 4 + channel]
						next[i] = 1
						break
		filled = next
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)

## Ship only the manifest and its referenced pages. Orphans, optical masters,
## checkpoints and source jobs cannot enter a game pack through this inventory.
static func write_game_pack(library_path: String, destination: String) -> Error:
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(library_path))
	if not GemAssetLibrary.valid_manifest(index):
		return ERR_INVALID_DATA
	var temporary := destination + ".%d.tmp" % OS.get_process_id()
	var packer := PCKPacker.new()
	var error := packer.pck_start(temporary)
	if error != OK:
		return error
	var files := {"library.json": library_path}
	for info: Dictionary in index["pages"].values():
		var path := library_path.get_base_dir().path_join(info["path"])
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != info["sha256"]:
			return ERR_FILE_CORRUPT
		files[info["path"]] = path
	var names := files.keys()
	names.sort()
	for relative: String in names:
		error = packer.add_file("res://gem-assets/" + relative, files[relative])
		if error != OK:
			return error
	error = packer.flush()
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))

static func compression_error(original: PackedByteArray, decoded: PackedByteArray) -> Dictionary:
	if original.size() != decoded.size():
		return {"composite_rmse_lsb": INF, "alpha_rmse_lsb": INF}
	var rgb_error := 0.0
	var alpha_error := 0.0
	for i in original.size() / 4:
		var a := original[i * 4 + 3] / 255.0
		var b := decoded[i * 4 + 3] / 255.0
		alpha_error += pow(original[i * 4 + 3] - decoded[i * 4 + 3], 2)
		for channel in 3:
			var black := original[i * 4 + channel] * a - decoded[i * 4 + channel] * b
			var white := black + 255.0 * (b - a)
			rgb_error += maxf(black * black, white * white)
	return {"composite_rmse_lsb": sqrt(rgb_error / maxf(original.size() / 4.0 * 3.0, 1)), "alpha_rmse_lsb": sqrt(alpha_error / maxf(original.size() / 4.0, 1))}

func _fail(message: String) -> Dictionary:
	last_error = message
	push_error(message)
	return {}
