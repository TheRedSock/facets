class_name GemProjectedCutResource
extends Resource

## Projected 2D render packet derived from the canonical 3D cut model.
##
## Vertices live in unit space [0,1]x[0,1] centered at (0.5, 0.5) so the
## renderer can scale them to tile pixels without depending on the model space.

@export var spec_id: StringName = &""
@export var cut_id: StringName = &""
@export var display_name: String = ""
@export var shape_category: StringName = &""
var geometry_signature: String = ""

## Projection/framing metadata mirrored from the source model variant.
var orthographic_top_roll_degrees: float = 0.0
var orthographic_side_yaw_degrees: float = 0.0
var orthographic_axis_fit_scale: float = 1.0

## Top-visible projected crown facets.
var facet_vertices: Array[PackedVector2Array] = []
var facet_normals: Array[Vector3] = []
var facet_zones: PackedStringArray = PackedStringArray()

## Top-down projected silhouette and facet edges.
var silhouette: PackedVector2Array = PackedVector2Array()
var edge_segments: Array[PackedVector2Array] = []
var edge_facet_a: PackedInt32Array = PackedInt32Array()
var edge_facet_b: PackedInt32Array = PackedInt32Array()

## Projected pavilion extinction fragments derived from true 3D pavilion facets.
var pavilion_vertices: Array[PackedVector2Array] = []
var pavilion_normals: Array[Vector3] = []
var pavilion_source_indices: PackedInt32Array = PackedInt32Array()
var pavilion_target_indices: PackedInt32Array = PackedInt32Array()

## Pre-computed per-facet constants for the 2D renderer.
var facet_centroids: PackedVector2Array = PackedVector2Array()
var facet_jitter: PackedFloat32Array = PackedFloat32Array()
var zone_brilliance_weights: PackedFloat32Array = PackedFloat32Array()


func facet_count() -> int:
	return facet_vertices.size()


func pavilion_count() -> int:
	return pavilion_vertices.size()


func clear_pavilion() -> void:
	pavilion_vertices.clear()
	pavilion_normals.clear()
	pavilion_source_indices = PackedInt32Array()
	pavilion_target_indices = PackedInt32Array()


func add_facet(vertices: PackedVector2Array, normal: Vector3, zone: String = "") -> void:
	if vertices.size() < 3:
		return
	facet_vertices.append(vertices)
	facet_normals.append(normal.normalized())
	facet_zones.append(zone)


func add_pavilion_fragment(
	vertices: PackedVector2Array,
	normal: Vector3,
	source_facet: int = -1,
	target_facet: int = -1,
) -> void:
	if vertices.size() < 3:
		return
	pavilion_vertices.append(vertices)
	pavilion_normals.append(normal.normalized())
	pavilion_source_indices.append(source_facet)
	pavilion_target_indices.append(target_facet)


func add_edge(from_pt: Vector2, to_pt: Vector2, facet_a: int = -1, facet_b: int = -1) -> void:
	edge_segments.append(PackedVector2Array([from_pt, to_pt]))
	edge_facet_a.append(facet_a)
	edge_facet_b.append(facet_b)
