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

## Parallel arrays identifying which two facets share each edge.
## edge_facet_a[i] is the first facet index, edge_facet_b[i] is the second.
## Boundary edges (only one facet) have edge_facet_b[i] == -1.
var edge_facet_a: PackedInt32Array = PackedInt32Array()
var edge_facet_b: PackedInt32Array = PackedInt32Array()

## Cut-specific pavilion overlay tuning copied from the generation profile.
var pavilion_sector_count: int = 0
var pavilion_rotation_fraction: float = 0.5
var pavilion_scale: float = 0.88
var pavilion_normal_z_scale: float = 0.6

## Pavilion extinction overlay — clipped fragments of projected pavilion facets
## visible through each crown facet.  Drawn as a semi-transparent dark overlay
## to simulate the geometric extinction patterns seen inside real gems.
var pavilion_vertices: Array[PackedVector2Array] = []
var pavilion_normals: Array[Vector3] = []
var pavilion_source_indices: PackedInt32Array = PackedInt32Array()
var pavilion_target_indices: PackedInt32Array = PackedInt32Array()

## Pre-computed per-facet constants (populated during cut finalization).
## These avoid redundant computation in the rendering pipeline.
## facet_centroids: centroid position of each facet in [0,1] unit space.
## facet_jitter: deterministic ±4% brightness variation per facet from centroid hash.
## zone_brilliance_weights: float encoding of zone type for brilliance multiplier
##   (e.g. table=0.5, star=0.25, bezel=0.0, girdle=-0.4, step=-0.2).
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


## Appends a facet polygon with its pseudo-3D normal and zone tag.
func add_facet(vertices: PackedVector2Array, normal: Vector3, zone: String = "") -> void:
	facet_vertices.append(vertices)
	facet_normals.append(normal)
	facet_zones.append(zone)


## Appends a pavilion extinction fragment with its normal.
func add_pavilion_fragment(
	vertices: PackedVector2Array,
	normal: Vector3,
	source_facet: int = -1,
	target_facet: int = -1,
) -> void:
	pavilion_vertices.append(vertices)
	pavilion_normals.append(normal)
	pavilion_source_indices.append(source_facet)
	pavilion_target_indices.append(target_facet)


## Appends a visible edge segment between two points with optional facet adjacency.
func add_edge(from_pt: Vector2, to_pt: Vector2, facet_a: int = -1, facet_b: int = -1) -> void:
	edge_segments.append(PackedVector2Array([from_pt, to_pt]))
	edge_facet_a.append(facet_a)
	edge_facet_b.append(facet_b)
