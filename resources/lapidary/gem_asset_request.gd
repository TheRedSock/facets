class_name GemAssetRequest
extends Resource
## One explicitly named delivery variant. No implicit product of seeds or rigs.
@export var asset_id: StringName
## Choose an explicit specimen OR a recipe/preset/seed.
@export var stone: GemStone
@export var recipe: GemSpecimenRecipe
@export var preset_id: StringName
@export var specimen_seed := 1
@export var clips: Array[GemClip] = []
@export var rig: GemLightRig
@export var print_style: GemPrint
@export var game_style: GemStyle
@export var presentation: GemPresentation = GemPresentation.new()
@export_enum("interact", "preview", "clip_bake", "hero", "reference") var rung := "clip_bake"
## Zero uses the quality rung. Output size is independent of render resolution.
@export var resolution := Vector2i.ZERO
@export var output_size := Vector2i.ZERO
@export var samples := 0
## Numerical transport overrides, admitted by the frame job validator.
## res/out/spp belong in the explicit fields above.
@export var policy_overrides: Dictionary = {}
## Preserve unstyled offline inputs without adding delivery references.
@export var retain_prints := false
