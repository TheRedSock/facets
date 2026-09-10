class_name GemArtifactStore
extends RefCounted
## Immutable content blobs + atomically published recipe records. Workers may
## resume from missing/corrupt objects. Checksums are verified before consumption.
var root: String
const MAX_BLOB_BYTES := 512 * 1024 * 1024

func _init(path := "res://generated/gemfactory") -> void:
	root = path

static func valid_key(key: String) -> bool:
	if key.length() != 64:
		return false
	for character in key:
		if not character in "0123456789abcdef":
			return false
	return true

func publish(key: String, payload: PackedByteArray, metadata: Dictionary) -> bool:
	var guard := GemStoreGuard.enter(root, "publish")
	if guard == null:
		return false
	var result := _publish_active(key, payload, metadata)
	guard.release()
	return result

func _publish_active(key: String, payload: PackedByteArray, metadata: Dictionary) -> bool:
	if not valid_key(key) or payload.is_empty() or payload.size() > MAX_BLOB_BYTES:
		return false
	var marker_path := root.path_join("store.json")
	if not FileAccess.file_exists(marker_path):
		if not atomic_write(marker_path, '{"kind":"lapidary_artifact_store","schema":1}'.to_utf8_buffer()):
			return false
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
	if not marker is Dictionary or marker.get("kind") != "lapidary_artifact_store" or marker.get("schema") != 1:
		return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	var digest := hash.finish().hex_encode()
	var relative := "objects/%s/%s.blob" % [digest.left(2), digest]
	var object_path := root.path_join(relative)
	if not FileAccess.file_exists(object_path) or FileAccess.get_sha256(object_path) != digest:
		if not atomic_write(object_path, payload):
			return false
	var record := metadata.duplicate(true)
	record.merge({"schema": 1, "recipe": key, "object": relative, "sha256": digest, "bytes": payload.size()}, true)
	return atomic_write(root.path_join("recipes/" + key + ".json"), JSON.stringify(record, "\t").to_utf8_buffer())

func read(key: String) -> Dictionary:
	if not valid_key(key):
		return {}
	var record_path := root.path_join("recipes/" + key + ".json")
	if not FileAccess.file_exists(record_path):
		return {}
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	if not record is Dictionary or record.get("schema") != 1 or record.get("recipe") != key:
		return {}
	var digest: String = record.get("sha256", "")
	if not valid_key(digest):
		return {}
	var relative := "objects/%s/%s.blob" % [digest.left(2), digest]
	if record.get("object") != relative:
		return {}
	var path := root.path_join(relative)
	var bytes := int(record.get("bytes", 0))
	if bytes <= 0 or bytes > MAX_BLOB_BYTES or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != bytes:
		return {}
	var payload := file.get_buffer(bytes)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	if hash.finish().hex_encode() != digest:
		return {}
	return {"metadata": record, "payload": payload}

static func atomic_write(path: String, bytes: PackedByteArray) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return false
	var temporary := absolute + ".%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error == OK

static func encode_linear(image: Image) -> PackedByteArray:
	assert(image.get_format() == Image.FORMAT_RGBAF)
	var header := StreamPeerBuffer.new()
	header.put_u32(0x315A5947) # GYZ1, associated scene-linear XYZ+coverage float32
	header.put_u32(image.get_width())
	header.put_u32(image.get_height())
	header.put_u32(image.get_data().size())
	var bytes := header.data_array
	bytes.append_array(image.get_data().compress(FileAccess.COMPRESSION_ZSTD))
	return bytes

static func decode_linear(bytes: PackedByteArray) -> Image:
	if bytes.size() < 16:
		return null
	var header := StreamPeerBuffer.new()
	header.data_array = bytes.slice(0, 16)
	if header.get_u32() != 0x315A5947:
		return null
	var width := header.get_u32()
	var height := header.get_u32()
	var length := header.get_u32()
	if width < 1 or height < 1 or width > 8192 or height > 8192 or length != width * height * 16 or length > MAX_BLOB_BYTES:
		return null
	var raw := bytes.slice(16).decompress(length, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != length:
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, raw)
