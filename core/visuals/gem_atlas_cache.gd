class_name GemAtlasCache
extends RefCounted

## Tile IDs allowed for the active run (sorted, unique). Empty means no run scoping
## is active — callers typically treat that as "all gameplay gems may be loaded".
var _active_tile_ids: PackedStringArray = PackedStringArray()


func set_active_tile_ids(tile_scope: PackedStringArray) -> void:
	_active_tile_ids = tile_scope


func clear() -> void:
	_active_tile_ids = PackedStringArray()


func get_active_tile_ids() -> PackedStringArray:
	return _active_tile_ids


func is_run_scope_active() -> bool:
	return not _active_tile_ids.is_empty()


## Rough BC7 / BPTC VRAM: 16 bytes per 4×4 block per array layer.
static func estimate_bc7_atlas_bytes(layer_count: int, width: int, height: int) -> int:
	@warning_ignore("INTEGER_DIVISION")
	var bw := (maxi(width, 1) + 3) / 4
	@warning_ignore("INTEGER_DIVISION")
	var bh := (maxi(height, 1) + 3) / 4
	return maxi(0, layer_count) * bw * bh * 16


func estimate_bytes_for_pair(
	lighting_layers: int,
	rotation_layers: int,
	width: int,
	height: int,
) -> int:
	return (
		estimate_bc7_atlas_bytes(lighting_layers, width, height)
		+ estimate_bc7_atlas_bytes(rotation_layers, width, height)
	)
