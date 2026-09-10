class_name GemStone
extends Resource
## The instance format. This is what a tile references and what BOTH board
## consumers (sprite clips, live 3D) are fed. Everything else is derived.

@export var stone_id: StringName        # == tile_id (t1_quartz ... t8_diamond)
@export var material: GemMaterial = GemMaterial.new()
@export var condition: GemCondition = GemCondition.new()
@export var cut: Resource               # GemCutTemplate (owned by core/lapidary/cut/)
@export var shape: GemShape = GemShape.new()
@export var grade: GemGrade
## Deterministic seed: inclusions, wear and jitter are stable across
## preview, bake and replays.
@export var seed := 1
## Stone-space-unit -> millimeter scale (stone space has girdle RADIUS = 1),
## i.e. size_mm 5.0 = 10 mm girdle diameter. Beer-Lambert paths use it directly;
## authored absorption curves are co-tuned with these sizes.
@export var size_mm := 4.0
## Optional optic-axis override in stone space. ZERO = use species.optic_axis_stone.
@export var optic_axis_override := Vector3.ZERO


## Stable identity for cache keys. Any visual-affecting change lands here.
func fingerprint() -> String:
	return preload("res://resources/lapidary/content_identity.gd").digest(self)

## Grade labels and catalog names do not require new optical masters. Full
## fingerprint() still tracks the authored record for editing/provenance.
func transport_inputs() -> Dictionary:
	return {"material": material, "condition": condition, "cut": cut, "shape": shape,
		"seed": seed, "size_mm": size_mm, "optic_axis_override": optic_axis_override}
