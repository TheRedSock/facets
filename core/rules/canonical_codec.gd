class_name CanonicalCodec
extends RefCounted
## FAC1: null=0, bool=1, i64=2, UTF8=3, Vector2i=4, array=5, map=6.
## Lengths are nonnegative i64. StringName normalizes to string. No objects/floats.
const MAX_BYTES := 16777216
const MAX_COUNT := 100000
const MAX_DEPTH := 32
var _bytes := PackedByteArray()
var _cursor := 0
var _error := ""
var _nodes := 0
var _writer := StreamPeerBuffer.new()
var _strings := {}

static func encode(value: Variant) -> PackedByteArray:
	var codec := CanonicalCodec.new()
	codec._writer.put_data("FAC1".to_ascii_buffer())
	codec._write(value, 0)
	return codec._writer.data_array if codec._error.is_empty() else PackedByteArray()

static func digest(value: Variant) -> String:
	var bytes := encode(value)
	if bytes.is_empty(): return ""
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	return hash.finish().hex_encode()

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 5 or bytes.size() > MAX_BYTES or bytes.slice(0,4).get_string_from_ascii() != "FAC1": return {"ok": false, "code": "codec_header"}
	var codec := CanonicalCodec.new()
	codec._bytes = bytes; codec._cursor = 4
	var value: Variant = codec._read(0)
	if not codec._error.is_empty(): return {"ok": false, "code": codec._error}
	if codec._cursor != bytes.size(): return {"ok": false, "code": "codec_trailing"}
	# Reject overlong/noncanonical UTF8 and any alternate representation.
	if encode(value) != bytes: return {"ok": false, "code": "codec_noncanonical"}
	return {"ok": true, "value": value}

func _integer(value: int) -> void:
	_writer.put_64(value)

func _write(value: Variant, depth: int) -> void:
	_nodes += 1
	if not _error.is_empty(): return
	if depth > MAX_DEPTH or _nodes > 1000000 or _writer.get_position() > MAX_BYTES: _error = "codec_limit"; return
	match typeof(value):
		TYPE_NIL: _writer.put_u8(0)
		TYPE_BOOL: _writer.put_u8(1); _writer.put_u8(1 if value else 0)
		TYPE_INT: _writer.put_u8(2); _integer(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var string := str(value)
			if not _strings.has(string): _strings[string] = string.to_utf8_buffer()
			var bytes: PackedByteArray = _strings[string]
			if bytes.size() > 1048576: _error = "codec_string_limit"; return
			_writer.put_u8(3); _integer(bytes.size()); _writer.put_data(bytes)
		TYPE_VECTOR2I:
			_writer.put_u8(4); _integer(value.x); _integer(value.y)
		TYPE_ARRAY:
			if value.size() > MAX_COUNT: _error = "codec_count"; return
			_writer.put_u8(5); _integer(value.size())
			for item in value: _write(item, depth + 1)
		TYPE_DICTIONARY:
			if value.size() > MAX_COUNT: _error = "codec_count"; return
			var keys: Array = value.keys()
			for key in keys:
				if not (key is String or key is StringName): _error = "codec_map_key"; return
			# Unicode scalar order equals lexicographic UTF-8 byte order. Normalize
			# once, then use the native string sort rather than encoding per compare.
			for i in keys.size(): keys[i] = str(keys[i])
			keys.sort()
			_writer.put_u8(6); _integer(keys.size())
			var seen := {}
			for key in keys:
				if seen.has(str(key)): _error = "codec_duplicate_key"; return
				seen[str(key)] = true
				_write(str(key), depth + 1); _write(value[key], depth + 1)
		_: _error = "codec_type"
	if _writer.get_position() > MAX_BYTES: _error = "codec_limit"

func _take(count: int) -> bool:
	if count < 0 or count > _bytes.size() - _cursor: _error = "codec_truncated"; return false
	return true

func _read_integer() -> int:
	if not _take(8): return 0
	var value := _bytes.decode_s64(_cursor); _cursor += 8
	return value

func _read(depth: int) -> Variant:
	_nodes += 1
	if not _error.is_empty(): return null
	if depth > MAX_DEPTH or _nodes > 1000000: _error = "codec_limit"; return null
	if not _take(1): return null
	var tag := _bytes[_cursor]; _cursor += 1
	match tag:
		0: return null
		1:
			if not _take(1): return null
			var value := _bytes[_cursor]; _cursor += 1
			if value > 1: _error = "codec_boolean"
			return value == 1
		2: return _read_integer()
		3:
			var length := _read_integer()
			if length > 1048576 or not _take(length): _error = "codec_string_length"; return null
			var bytes := _bytes.slice(_cursor,_cursor + length); _cursor += length
			if not _valid_utf8(bytes): _error = "codec_utf8"; return null
			var string := bytes.get_string_from_utf8()
			if string.to_utf8_buffer() != bytes: _error = "codec_utf8"
			return string
		4:
			var x := _read_integer(); var y := _read_integer()
			if x < -2147483648 or x > 2147483647 or y < -2147483648 or y > 2147483647: _error = "codec_vector_range"
			return Vector2i(x,y)
		5, 6:
			var length := _read_integer()
			if length < 0 or length > MAX_COUNT or length > _bytes.size() - _cursor: _error = "codec_count"; return null
			if tag == 5:
				var array: Array = []
				for i in length:
					array.append(_read(depth + 1))
					if not _error.is_empty(): return null
				return array
			var map := {}
			var previous := ""
			for i in length:
				var key: Variant = _read(depth + 1)
				if not key is String: _error = "codec_map_key"; return null
				var ordered: String = key.to_utf8_buffer().hex_encode()
				if i > 0 and ordered <= previous: _error = "codec_key_order"; return null
				previous = ordered
				map[key] = _read(depth + 1)
				if not _error.is_empty(): return null
			return map
	_error = "codec_type"
	return null

static func _valid_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	while i < bytes.size():
		var first := bytes[i]; i += 1
		if first < 128: continue
		var count := 0; var scalar := 0; var minimum := 0
		if first >= 194 and first <= 223: count = 1; scalar = first & 31; minimum = 128
		elif first >= 224 and first <= 239: count = 2; scalar = first & 15; minimum = 2048
		elif first >= 240 and first <= 244: count = 3; scalar = first & 7; minimum = 65536
		else: return false
		if bytes.size() - i < count: return false
		for j in count:
			var next := bytes[i]; i += 1
			if next < 128 or next > 191: return false
			scalar = (scalar << 6) | (next & 63)
		if scalar < minimum or scalar > 1114111 or (scalar >= 55296 and scalar <= 57343): return false
	return true
