class_name GemShape
extends Resource
## Material-independent procedural shape recipe. Dimensions are in normalized
## stone units; GemStone.size_mm converts one unit to millimeters.
@export_enum("faceted", "cabochon", "loft") var mode := "faceted"
@export var outline: StringName = &"round"
@export_range(0.2, 8.0) var aspect_ratio := 1.0
@export_range(0.0, 0.45) var corner_radius := 0.1
@export_range(3, 128) var sectors := 8
@export_range(8, 512) var radial_segments := 32
## Custom CCW simple polygon for lofts, including concave outlines.
@export var outline_points := PackedVector2Array()
## Loft sections ordered bottom to top: (height, outline scale).
@export var loft_sections := PackedVector2Array([Vector2(-0.65, 0.05), Vector2(-0.04, 1), Vector2(0.04, 1), Vector2(0.35, 0.55)])
@export_range(0.01, 3.0) var dome_height := 0.6
@export_range(4, 128) var dome_rings := 24

static func faceted_outline(kind: StringName) -> GemShape:
	var shape := GemShape.new()
	shape.outline = kind
	var aspects := {&"oval": 1.0 / 0.78, &"diamond": 1.3, &"rectangle": 1.35, &"marquise": 1.8, &"pear": 1.4}
	var corners := {&"square": 0.12, &"triangle": 0.14, &"diamond": 0.07, &"rectangle": 0.1}
	shape.aspect_ratio = aspects.get(kind, 1.0)
	shape.corner_radius = corners.get(kind, 0.1)
	shape.sectors = 6 if kind == &"triangle" else 8
	return shape

static func cabochon_outline(kind: StringName) -> GemShape:
	var shape := faceted_outline(kind)
	shape.mode = "cabochon"
	shape.radial_segments = 128
	shape.dome_rings = 48
	return shape
