class_name GemDeliveryFormat
extends RefCounted
## Delivery wire identity, independent of authored resource graphs and the factory.
static func valid_key(key:String)->bool:
	if key.length()!=64:return false
	for character in key:
		if character not in "0123456789abcdef":return false
	return true

static func page_key(size:Vector2i,format:int,codec:String,bytes:PackedByteArray)->String:
	# Exact v1 wire encoding. This is a fixed page record, not a Resource graph.
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(["array",["delivery-page-v1",size,format,codec,bytes]]))
	return context.finish().hex_encode()
