class_name GemAssetBatch
extends Resource
## A finite explicit request list, suitable for independent worker packaging.
@export var requests: Array[GemAssetRequest] = []
## Counts requested jobs before deduplication, including retained print requests.
@export_range(1, 65536) var frame_budget := 16384
@export_enum("None:0", "1:1", "2:2", "4:4", "8:8") var geometry_coverage_side := 0
