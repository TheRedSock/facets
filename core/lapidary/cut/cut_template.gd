class_name GemCutTemplate
extends Resource
## Declarative convex facet program. The stone's faceted GemShape supplies
## the authored girdle; every upper/lower termination is an ordinary group.
@export var cut_id: StringName
@export var parameters: Dictionary = {}
@export var groups: Array[GemFacetGroup] = []
