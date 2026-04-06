class_name GemGameplayBakeBackend
extends Node

## Runtime bake backend contract used by GemVisualRegistry.

signal texture_baked(tile_id: StringName, texture: Texture2D, metadata: Dictionary)

var backend_id: StringName = &""


func supports_request(request: Dictionary) -> bool:
	return supports_visual(
		request.get("tile_id", &""),
		request.get("visual", null),
		request.get("cut", null)
	)


func supports_visual(_tile_id: StringName, _visual: GemVisualResource, _cut) -> bool:
	return false


func request_bake(_request: Dictionary) -> void:
	push_error("GemGameplayBakeBackend.request_bake() must be overridden")


func shutdown() -> void:
	pass
