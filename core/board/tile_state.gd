class_name TileState
extends RefCounted

var instance_id: String = ""

## Unique identifier for this gem type (e.g., &"quartz", &"amethyst").
var tile_id: StringName = &"debug_tile"

## The match group determines which tiles can match together.
## Tiles with the same match_group form valid matches.
## Defaults to tile_id, but can be overridden for special mechanics.
var match_group: StringName = &""

## Current tier of this tile (1-8 for standard gems, 0 for hazards, 9 for transcendents).
var tier: int = 1

## Family tags for synergy mechanics (e.g., &"quartz", &"corundum").
var family_tags: Array[StringName] = []

## Status flags for on-board effects (e.g., "polished", "protected").
var status_flags: Dictionary = {}

## Whether this tile is protected from destruction.
var protected: bool = false

## Per-tile gravity override. ZERO = use cell gravity. Non-zero = override.
var gravity_override: Vector2i = Vector2i.ZERO

## Whether this tile cannot be moved by gravity or player swap.
var immovable: bool = false

## Whether this tile is excluded from match detection.
var unmatchable: bool = false

## The tile_id this tile merges into when upgraded (next in the gem ladder).
## Empty means this is the top tier — upgrades just increment tier.
var merge_target_id: StringName = &""


## Returns the effective match group. Falls back to tile_id if match_group is empty.
func get_match_group() -> StringName:
	if match_group != &"":
		return match_group
	return tile_id


static func create(id: StringName, gem_tier: int, group: StringName = &"") -> TileState:
	var tile := TileState.new()
	tile.tile_id = id
	tile.tier = gem_tier
	tile.match_group = group
	return tile


static func from_debug_tier(value: int) -> TileState:
	var tile := TileState.new()
	tile.tier = value
	tile.tile_id = StringName("debug_tier_%d" % value)
	# For debug tiles, match_group defaults to tile_id via get_match_group()
	return tile


func duplicate_tile() -> TileState:
	var tile := TileState.new()
	tile.instance_id = instance_id
	tile.tile_id = tile_id
	tile.match_group = match_group
	tile.tier = tier
	tile.family_tags = family_tags.duplicate()
	tile.status_flags = status_flags.duplicate(true)
	tile.protected = protected
	tile.gravity_override = gravity_override
	tile.immovable = immovable
	tile.unmatchable = unmatchable
	tile.merge_target_id = merge_target_id
	return tile


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"tile_id": String(tile_id),
		"match_group": String(get_match_group()),
		"tier": tier,
		"family_tags": family_tags.duplicate(),
		"status_flags": status_flags.duplicate(true),
		"protected": protected,
		"gravity_override": {"x": gravity_override.x, "y": gravity_override.y},
		"immovable": immovable,
		"unmatchable": unmatchable,
		"merge_target_id": String(merge_target_id),
	}
