class_name GemCutResource
extends Resource

## Defines the 2D faceted geometry of a gemstone cut.
##
## Vertices are in unit space [0,1]x[0,1] centered at (0.5, 0.5).
## Multiply by cell_size to get pixel coordinates at render time.
## Facet normals are pseudo-3D Vector3 values used for lighting.

@export var cut_id: StringName = &""
@export var display_name: String = ""
@export var shape_category: StringName = &""  # e.g., "round", "square", "triangle"

## Facet data — parallel arrays. Each index describes one polygon facet.
var facet_vertices: Array[PackedVector2Array] = []
var facet_normals: Array[Vector3] = []
var facet_zones: PackedStringArray = PackedStringArray()

## Outer boundary for silhouette outline.
var silhouette: PackedVector2Array = PackedVector2Array()

## Visible edge lines between facets (each is a 2-point segment).
var edge_segments: Array[PackedVector2Array] = []


func facet_count() -> int:
	return facet_vertices.size()


## Appends a facet polygon with its pseudo-3D normal and zone tag.
func add_facet(vertices: PackedVector2Array, normal: Vector3, zone: String = "") -> void:
	facet_vertices.append(vertices)
	facet_normals.append(normal)
	facet_zones.append(zone)


## Appends a visible edge segment between two points.
func add_edge(from_pt: Vector2, to_pt: Vector2) -> void:
	edge_segments.append(PackedVector2Array([from_pt, to_pt]))
