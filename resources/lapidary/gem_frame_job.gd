class_name GemFrameJob
extends Resource
## Portable immutable-by-convention input to one optical render and print.
## Animation names/timing are delivery metadata, deliberately absent here.
@export var stone: GemStone
@export var rig: GemLightRig
@export var print_style: GemPrint
@export var game_style: GemStyle
@export var quality: Dictionary = {}
@export var resolution := Vector2i(256, 256)
@export var output_size := Vector2i(128, 128)
@export var samples := 128
@export var sample_seed := 1
@export var orientation := Quaternion.IDENTITY
@export var rig_yaw := 0.0
@export var role_multipliers := Vector4.ONE
@export var ortho_half := 1.25
## Orthographic camera-plane center in world XY, normalized stone units.
@export var camera_offset := Vector2.ZERO
@export var exposure := 1.0
