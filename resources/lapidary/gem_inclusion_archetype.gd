class_name GemInclusionArchetype
extends Resource
## One species-typical inclusion form (corundum silk, beryl jardin veil,
## quartz milky cloud, olivine lily pad...). Grade picks density; the
## archetype defines what the inclusion IS.

enum Form { NEEDLE, PLATELET, VEIL, CLOUD, CRYSTAL, FINGERPRINT }

@export var archetype_id: StringName
@export var form := Form.NEEDLE
## Size range in millimeters (primitive length or radius).
@export var size_mm_range := Vector2(0.05, 0.5)
## Length/width for needles; diameter/thickness for platelets.
@export var aspect := 12.0
## Crystallographically locked orientations (e.g. corundum silk at 60 degrees).
## Empty = random orientation.
@export var orientation_axes: Array[Vector3] = []
## Scatter density inside the primitive (per mm).
@export var scatter_density := 4.0
## Broad-band tint of the scatterer (approximation; documented in KERNEL_CONTRACT.md).
@export var tint := Color.WHITE
## Relative pick probability within the species vocabulary.
@export var weight := 1.0
## Depth bias: 0 = uniform, 1 = prefers center of the stone.
@export var center_bias := 0.0
