class_name GemGrade
extends Resource
## Catalog quality labels, not physical properties or a gemological certificate.
## None of these axes alter optics or geometry. A future accepted grade recipe
## must first realize explicit material/condition/cut inputs for inspection.
## Hardness, toughness, clarity and aesthetic rank must not be conflated.

@export var grade_id: StringName
@export_range(0.0, 1.0) var cut := 1.0
@export_range(0.0, 1.0) var clarity := 1.0
@export_range(0.0, 1.0) var surface := 1.0
@export_range(0.0, 1.0) var crystal := 1.0
