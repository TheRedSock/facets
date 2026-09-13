class_name GemTilePresentation
extends Resource
## Logical game identity is separate from an asset's physical/authored identity.
@export var tile_id:StringName
@export var asset_id:StringName
@export var roles:Dictionary[StringName,StringName]={}
