class_name GemGrade
extends Resource
## Legacy catalog quality recipes, not physical properties or a gemological
## certificate. Cut controls empirical proportions/jitter; crystal controls
## bulk haze/zoning. Clarity and surface recipes remain disabled pending visual
## validation. GemCondition holds explicit realized defects in millimeters.
## Hardness, toughness, clarity and aesthetic rank must not be conflated.

@export var grade_id: StringName
@export_range(0.0, 1.0) var cut := 1.0
@export_range(0.0, 1.0) var clarity := 1.0
@export_range(0.0, 1.0) var surface := 1.0
@export_range(0.0, 1.0) var crystal := 1.0
