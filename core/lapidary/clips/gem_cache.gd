class_name GemCache
extends RefCounted
## Disk cache for baked gem clips.
##
## Layout (per root):
##   <root>/v<LOOK_VERSION>/<stone_fingerprint>/<clip_id>@<rung_name>.webp
##   <root>/v<LOOK_VERSION>/<stone_fingerprint>/<clip_id>@<rung_name>.json
## The .webp is a lossless horizontal frame strip (frames * w x h); the sidecar
## carries playback metadata plus the full cache key.
##
## Read chain: user:// (runtime bakes) first, then res://generated/gemcache
## (dev fast path written by tools/package_clips.gd; hidden from the editor
## importer via .gdignore — read through FileAccess, never ResourceLoader).
##
## Invalidation is key-mismatch-as-miss: the key embeds stone and clip
## fingerprints, so any visual-affecting change makes the stale file unreadable
## and the next bake overwrites it in place. Bumping LOOK_VERSION retires every
## cache at once (foreign-GPU caches regenerate rather than diffing).

const LOOK_VERSION := 13
const USER_ROOT := "user://gemcache"
const GENERATED_ROOT := "res://generated/gemcache"


## Identity of one baked artifact (unversioned; see versioned_key).
static func cache_key(stone: GemStone, clip: GemClip, rung: int) -> String:
	var digest := GemContentIdentity.digest([stone, clip, GemRenderIdentity.context(rung)])
	return "%s@%s" % [digest, GemRung.rung_name(rung)]


## Full identity including the look-version root.
static func versioned_key(stone: GemStone, clip: GemClip, rung: int, look := LOOK_VERSION) -> String:
	return "v%d/%s" % [look, cache_key(stone, clip, rung)]


static func strip_path(root: String, stone: GemStone, clip: GemClip, rung: int) -> String:
	return _base_path(root, stone, clip, rung) + ".webp"


static func sidecar_path(root: String, stone: GemStone, clip: GemClip, rung: int) -> String:
	return _base_path(root, stone, clip, rung) + ".json"


static func _base_path(root: String, stone: GemStone, clip: GemClip, rung: int) -> String:
	return "%s/v%d/%s/%s@%s" % [root, LOOK_VERSION, stone.fingerprint(),
		String(clip.clip_id), GemRung.rung_name(rung)]


# ------------------------------------------------------------------ write

## Writes strip + sidecar. `frames` must share one size/format (RGBA8 baker
## output). Returns false on any I/O failure.
static func write(stone: GemStone, clip: GemClip, rung: int, frames: Array,
		meta: Dictionary = {}, root := USER_ROOT) -> bool:
	if frames.is_empty():
		return false
	var strip := assemble_strip(frames)
	if strip == null:
		return false
	var f0: Image = frames[0]

	var dir := ProjectSettings.globalize_path(_base_path(root, stone, clip, rung)).get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_warning("GemCache: cannot create %s (%s)" % [dir, error_string(err)])
		return false
	if root.begins_with("res://"):
		_ensure_gdignore(root)

	var bytes := strip.save_webp_to_buffer(false)
	if bytes.is_empty():
		return false
	if not _atomic_write(strip_path(root, stone, clip, rung), bytes):
		return false

	var sidecar := {
		"key": cache_key(stone, clip, rung),
		"payload_sha256": _bytes_hash(bytes),
		"payload_bytes": bytes.size(),
		"look_version": LOOK_VERSION,
		"fps": clip.fps,
		"frames": frames.size(),
		"loop": clip.loop,
		"frame_w": f0.get_width(),
		"frame_h": f0.get_height(),
		"baked_at": Time.get_datetime_string_from_system(true),
		"device": RenderingServer.get_video_adapter_name(),
		"rung": GemRung.rung_name(rung),
		"meta": meta,
	}
	return _atomic_write(sidecar_path(root, stone, clip, rung), JSON.stringify(sidecar, "\t").to_utf8_buffer())


static func _bytes_hash(bytes: PackedByteArray) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()


static func _atomic_write(path: String, bytes: PackedByteArray) -> bool:
	var temporary := path + ".%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error == OK


## Horizontal strip: frames * w x h, RGBA8.
static func assemble_strip(frames: Array) -> Image:
	var f0: Image = frames[0]
	var w := f0.get_width()
	var h := f0.get_height()
	var strip := Image.create_empty(w * frames.size(), h, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var f: Image = frames[i]
		if f.get_width() != w or f.get_height() != h:
			push_warning("GemCache: frame %d size mismatch" % i)
			return null
		if f.get_format() != Image.FORMAT_RGBA8:
			f = f.duplicate()
			f.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(f, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	return strip


static func slice_frames(strip: Image, frame_w: int, frame_h: int, count: int) -> Array[Image]:
	var out: Array[Image] = []
	for i in count:
		out.append(strip.get_region(Rect2i(i * frame_w, 0, frame_w, frame_h)))
	return out


# ------------------------------------------------------------------ read

## Returns {strip: Image, frames, fps, loop, frame_w, frame_h, meta, source}
## or {} on miss / stale key / decode failure.
static func read(stone: GemStone, clip: GemClip, rung: int) -> Dictionary:
	for root in [USER_ROOT, GENERATED_ROOT]:
		var hit := _read_from(root, stone, clip, rung)
		if not hit.is_empty():
			return hit
	return {}


## A cache hit must be readable, including its payload. Corruption is a miss.
static func has(stone: GemStone, clip: GemClip, rung: int) -> bool:
	return not read(stone, clip, rung).is_empty()


## Deletes the user:// artifact for one stone x clip x rung (dev utility;
## normal invalidation is automatic through key mismatch).
static func invalidate(stone: GemStone, clip: GemClip, rung: int) -> void:
	for path in [strip_path(USER_ROOT, stone, clip, rung), sidecar_path(USER_ROOT, stone, clip, rung)]:
		var global := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global):
			DirAccess.remove_absolute(global)


static func _read_from(root: String, stone: GemStone, clip: GemClip, rung: int) -> Dictionary:
	var sidecar := _load_sidecar(root, stone, clip, rung)
	if sidecar.is_empty():
		return {}
	var bytes := FileAccess.get_file_as_bytes(strip_path(root, stone, clip, rung))
	if bytes.size() != int(sidecar.get("payload_bytes", -1)) or _bytes_hash(bytes) != sidecar.get("payload_sha256", ""):
		return {}
	var strip := Image.new()
	if strip.load_webp_from_buffer(bytes) != OK:
		push_warning("GemCache: corrupt strip at %s" % strip_path(root, stone, clip, rung))
		return {}
	var frame_count := int(sidecar["frames"])
	var frame_w := int(sidecar["frame_w"])
	var frame_h := int(sidecar["frame_h"])
	if strip.get_width() != frame_w * frame_count or strip.get_height() != frame_h:
		push_warning("GemCache: strip/sidecar dimension mismatch at %s" % strip_path(root, stone, clip, rung))
		return {}
	return {
		"strip": strip,
		"frames": frame_count,
		"fps": float(sidecar["fps"]),
		"loop": bool(sidecar["loop"]),
		"frame_w": frame_w,
		"frame_h": frame_h,
		"meta": sidecar.get("meta", {}),
		"source": root,
	}


## Sidecar parse + key validation. {} when missing or stale.
static func _load_sidecar(root: String, stone: GemStone, clip: GemClip, rung: int) -> Dictionary:
	var path := sidecar_path(root, stone, clip, rung)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	var sidecar: Dictionary = parsed
	if String(sidecar.get("key", "")) != cache_key(stone, clip, rung):
		return {} # stale: stone or clip fingerprint changed since this bake
	if int(sidecar.get("look_version", -1)) != LOOK_VERSION:
		return {}
	for field in ["frames", "frame_w", "frame_h", "fps"]:
		if not sidecar.has(field) or not (sidecar[field] is float or sidecar[field] is int) or not is_finite(float(sidecar[field])) or float(sidecar[field]) <= 0.0:
			return {}
	if not sidecar.has("loop") or not FileAccess.file_exists(strip_path(root, stone, clip, rung)):
		return {}
	return sidecar


## The generated root is read through FileAccess only; keep the editor
## importer away from thousands of cache WebPs. Dev fast path only — an
## exported build must ship required clips differently (or bake on first run).
static func _ensure_gdignore(root: String) -> void:
	var path := ProjectSettings.globalize_path(root + "/.gdignore")
	if FileAccess.file_exists(path):
		return
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("")
		fa.close()
