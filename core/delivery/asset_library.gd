class_name GemAssetLibrary
extends RefCounted
## Read-only game consumer. Opening a library reads metadata only. Texture pages
## are decoded/uploaded on demand; returned AtlasTextures preserve original size.
## The LRU budget bounds cache ownership. Active views retain their own texture
## references, so callers must also bound the simultaneous visible working set.
var root: String
var manifest: Dictionary = {}
var cache_budget_bytes := 32 * 1024 * 1024
var cache_bytes := 0
var page_loads := 0
var _pages := {}
var _clock := 0
var _allocations:Dictionary={}
var _resident:Dictionary={}
var last_error := ""

func open(path: String) -> bool:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "Library does not exist: " + path
		return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not valid_manifest(value):
		last_error = "Invalid delivery manifest"
		return false
	if not codec_supported(value["codec"]):
		last_error = "GPU does not support delivery codec: " + str(value["codec"])
		return false
	root = path.get_base_dir()
	manifest = value
	_pages.clear()
	cache_bytes = 0
	page_loads = 0
	return true

static func codec_supported(codec: String) -> bool:
	return codec == "webp_lossless" or (codec == "bc7" and RenderingServer.has_os_feature("bptc")) or (codec == "astc4x4" and RenderingServer.has_os_feature("astc"))

## Validate all dimensions and references before allocating or uploading pages.
## A failed replacement leaves the previously opened library intact.
static func valid_manifest(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema") != 1:
		return false
	for field in ["pages", "frames", "clips"]:
		if not value.get(field) is Dictionary or value[field].is_empty():
			return false
	if value.get("codec") not in ["webp_lossless", "bc7", "astc4x4"]:
		return false
	for key: String in value["pages"]:
		var info: Variant = value["pages"][key]
		if not info is Dictionary or not GemDeliveryFormat.valid_key(key) or info.get("path") != "pages/" + key + ".gpage" or not info.get("sha256") is String or not GemDeliveryFormat.valid_key(info["sha256"]) or info.get("codec") != value["codec"]:
			return false
		if not _integers([info.get("width"), info.get("height"), info.get("bytes"), info.get("gpu_bytes"), info.get("format")]):
			return false
		var w := int(info["width"])
		var h := int(info["height"])
		if w < 4 or h < 4 or w > 8192 or h > 8192 or w % 4 != 0 or h % 4 != 0 or info["bytes"] <= 0 or info["bytes"] > 512 * 1024 * 1024:
			return false
		var format: int = {"webp_lossless": Image.FORMAT_RGBA8, "bc7": Image.FORMAT_BPTC_RGBA, "astc4x4": Image.FORMAT_ASTC_4x4}[info["codec"]]
		var gpu_bytes := w * h * (4 if info["codec"] == "webp_lossless" else 1)
		if info["format"] != format or info["gpu_bytes"] != gpu_bytes or (info["codec"] != "webp_lossless" and info["bytes"] != gpu_bytes):
			return false
	for key: String in value["frames"]:
		var item: Variant = value["frames"][key]
		if not GemDeliveryFormat.valid_key(key) or not item is Dictionary or not value["pages"].has(item.get("page")):
			return false
		for field in ["rect", "size", "offset"]:
			if not item.get(field) is Array or item[field].size() != (4 if field == "rect" else 2) or not _integers(item[field]):
				return false
		var r: Array = item["rect"]
		var s: Array = item["size"]
		var o: Array = item["offset"]
		var p: Dictionary = value["pages"][item["page"]]
		if r[0] < 0 or r[1] < 0 or r[2] < 1 or r[3] < 1 or r[0] + r[2] > p["width"] or r[1] + r[3] > p["height"] or s[0] > 8192 or s[1] > 8192 or o[0] < 0 or o[1] < 0 or o[0] + r[2] > s[0] or o[1] + r[3] > s[1]:
			return false
	var referenced_frames:Dictionary={}
	for sequence: Variant in value["clips"].values():
		if not sequence is Dictionary or not sequence.get("frames") is Array or sequence["frames"].is_empty() or not sequence.get("loop") is bool:
			return false
		var fps: Variant = sequence.get("fps")
		if not (fps is float or fps is int) or not is_finite(float(fps)) or fps <= 0 or fps > 1000:
			return false
		for key: Variant in sequence["frames"]:
			if not key is String or not value["frames"].has(key):
				return false
			referenced_frames[key]=true
	if referenced_frames.size()!=value["frames"].size():return false
	var referenced_pages:Dictionary={}
	for frame:Dictionary in value["frames"].values():referenced_pages[frame["page"]]=true
	if referenced_pages.size()!=value["pages"].size():return false
	return true

static func _integers(values: Array) -> bool:
	for value: Variant in values:
		if not (value is int or value is float) or not is_finite(float(value)) or value != floor(float(value)):
			return false
	return true

func clip_info(key: String) -> Dictionary:
	var info: Dictionary = manifest.get("clips", {}).get(key, {})
	if info.is_empty():
		return {}
	return {"frames": info["frames"].size(), "fps": info["fps"], "loop": info["loop"]}

func frame(clip: String, frame_index: int) -> AtlasTexture:
	var sequence: Dictionary = manifest.get("clips", {}).get(clip, {})
	var frames: Array = sequence.get("frames", [])
	if frames.is_empty() or frame_index < 0 or frame_index >= frames.size():
		return null
	var item: Dictionary = manifest["frames"].get(frames[frame_index], {})
	if item.is_empty():
		return null
	var page := load_page(item["page"])
	if page == null:
		return null
	var rect: Array = item["rect"]
	var size: Array = item["size"]
	var offset: Array = item["offset"]
	var texture := AtlasTexture.new()
	texture.atlas = page
	texture.region = Rect2(rect[0], rect[1], rect[2], rect[3])
	texture.margin = Rect2(offset[0], offset[1], size[0] - rect[2], size[1] - rect[3])
	return texture

func load_page(key: String) -> Texture2D:
	_clock += 1
	var info: Dictionary = manifest.get("pages", {}).get(key, {})
	if not GemDeliveryFormat.valid_key(key) or info.is_empty() or info.get("path") != "pages/" + key + ".gpage":
		return _page_error("Unknown delivery page: "+key)
	if _pages.has(key):
		_pages[key]["used"] = _clock
		return _pages[key]["texture"]
	# Prefetch/view ownership can outlive LRU ownership. Reuse that live upload.
	if _resident.has(key):
		var live:Texture2D=_resident[key].get_ref()
		if live!=null:return live
		_resident.erase(key)
	var path := root.path_join(info["path"])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(info["bytes"]):
		return _page_error("Missing or truncated delivery page: "+path)
	var bytes := file.get_buffer(file.get_length())
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode() != info["sha256"]:
		return _page_error("Delivery page checksum mismatch: "+path)
	if GemDeliveryFormat.page_key(Vector2i(info["width"], info["height"]), int(info["format"]), String(info["codec"]), bytes) != key:
		return _page_error("Delivery page identity mismatch: "+path)
	var image: Image
	if info["codec"] == "webp_lossless":
		image = Image.new()
		if image.load_webp_from_buffer(bytes) != OK:
			return _page_error("Cannot decode delivery page: "+path)
	else:
		image = Image.create_from_data(info["width"], info["height"], false, info["format"], bytes)
	if image == null or image.get_width() != info["width"] or image.get_height() != info["height"] or image.get_format() != info["format"]:
		return _page_error("Delivery page dimensions/format mismatch: "+path)
	var texture := ImageTexture.create_from_image(image)
	var needed: int = info["gpu_bytes"]
	_allocations[texture.get_instance_id()]={"reference":weakref(texture),"bytes":needed}
	_resident[key]=weakref(texture)
	while cache_bytes + needed > cache_budget_bytes and not _pages.is_empty():
		var oldest: String = _pages.keys()[0]
		for candidate: String in _pages:
			if _pages[candidate]["used"] < _pages[oldest]["used"]:
				oldest = candidate
		cache_bytes -= _pages[oldest]["bytes"]
		_pages.erase(oldest)
	if needed <= cache_budget_bytes:
		_pages[key] = {"texture": texture, "bytes": needed, "used": _clock}
		cache_bytes += needed
	page_loads += 1
	return texture

func required_pages(clips:Array[String])->Array[String]:
	var pages:Array[String]=[]
	for clip in clips:
		for frame_key in manifest.get("clips",{}).get(clip,{}).get("frames",[]):
			var key:String=manifest.frames[frame_key].page
			if key not in pages:pages.append(key)
	return pages

func memory_report()->Dictionary:
	var resident:=0
	for key in _resident.keys():
		if _resident[key].get_ref()==null:_resident.erase(key)
	for id in _allocations.keys():
		if _allocations[id].reference.get_ref()==null:_allocations.erase(id)
		else:resident+=int(_allocations[id].bytes)
	return {"resident_texture_bytes":resident,"resident_pages":_allocations.size(),"cache_owned_bytes":cache_bytes,"outside_cache_bytes":resident-cache_bytes,"cache_budget_bytes":cache_budget_bytes}

func clear_cache()->void:
	_pages.clear();cache_bytes=0

## Projected residency after retaining every requested page, including existing
## active references. Does not count a page twice when it already has an upload.
func projected_resident_bytes(keys:Array[String])->int:
	var total:int=memory_report().resident_texture_bytes
	for key in keys:
		if not _resident.has(key) or _resident[key].get_ref()==null:total+=int(manifest.pages[key].gpu_bytes)
	return total

func _page_error(message:String)->Texture2D:
	last_error=message;return null
