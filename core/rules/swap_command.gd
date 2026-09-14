class_name SwapCommand
extends RefCounted
var origin: Vector2i
var destination: Vector2i

func _init(a: Vector2i = Vector2i.ZERO, b: Vector2i = Vector2i.ZERO) -> void:
	origin = a
	destination = b

func to_dict() -> Dictionary:
	return {"kind": "swap", "origin": origin, "destination": destination}

static func parse(data: Variant) -> SwapCommand:
	if not data is Dictionary or data.size() != 3 or data.get("kind") != "swap" or not data.get("origin") is Vector2i or not data.get("destination") is Vector2i: return null
	return SwapCommand.new(data.origin, data.destination)
