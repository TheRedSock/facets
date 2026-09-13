class_name TileDefinitionResource
extends Resource

@export var tile_id: StringName
@export var display_name: String = ""
@export_range(0, 99, 1) var tier: int = 1
@export var match_group: StringName = &""  # Defaults to tile_id if empty
@export var family_tags: Array[StringName] = []

## The tile_id of the gem this tile merges into (next tier in the chain).
@export var merge_target_id: StringName = &""

## Whether this tile is protectable by default.
@export var can_be_protected: bool = true
