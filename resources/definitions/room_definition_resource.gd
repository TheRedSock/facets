class_name RoomDefinitionResource
extends Resource

@export var room_id := "open_seam"
@export var layout: BoardLayoutResource
@export var work := 16
@export var craft := 1
@export var obstacles: Array[Dictionary] = []
@export var marked_ids: Array[String] = []
