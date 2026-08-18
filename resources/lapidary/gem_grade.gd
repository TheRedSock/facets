class_name GemGrade
extends Resource
## The impurity/grade system: four axes, all mapped to physical mechanisms
## by the stone compiler. 1.0 = exceptional, 0.0 = ruinous.
##
## cut     -> pavilion angle error vs solved ideal (real windowing), crown/table
##            error, per-plane meeting jitter, edge rounding, girdle unevenness
## clarity -> inclusion count/size/depth from the SPECIES vocabulary
## surface -> polish roughness, scratch field, abrasion, dirt film
## crystal -> volumetric milkiness (scatter), growth zoning strength

@export var grade_id: StringName
@export_range(0.0, 1.0) var cut := 1.0
@export_range(0.0, 1.0) var clarity := 1.0
@export_range(0.0, 1.0) var surface := 1.0
@export_range(0.0, 1.0) var crystal := 1.0
