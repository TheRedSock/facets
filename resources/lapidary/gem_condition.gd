class_name GemCondition
extends Resource
## Explicit specimen condition. Grade is a recipe/selection label; these fields
## describe realized physical features and remain stable under lighting/pose.
@export var defects: Array[GemDefect] = []
## Statistical microfacet slope parameters, independent of mesh tessellation.
## Surface transport support is gated until its energy and visual checks pass.
@export_range(0.0, 1.0) var polish_alpha_u := 0.0
@export_range(0.0, 1.0) var polish_alpha_v := 0.0
@export var polish_direction := Vector3.RIGHT
