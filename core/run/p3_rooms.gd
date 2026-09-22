class_name P3Rooms
extends RefCounted
## Authored P3 room layouts, frozen before expedition reference replay capture.
const SPECS := {
	"open_seam":{"work":16,"objective":"clear_marked_rubble","rubble":[Vector2i(2,2),Vector2i(5,3),Vector2i(2,5),Vector2i(5,6)],"outlets":[],"minimum_tier":0,"demand":0},
	"deep_seam":{"work":16,"objective":"clear_marked_rubble","rubble":[Vector2i(4,1),Vector2i(2,2),Vector2i(5,3),Vector2i(2,5),Vector2i(6,5),Vector2i(5,6)],"outlets":[],"minimum_tier":0,"demand":0},
	"commission":{"work":16,"objective":"extract","rubble":[],"outlets":[Vector2i(2,7),Vector2i(5,7)],"minimum_tier":3,"demand":3},
	"vault":{"work":20,"objective":"extract","rubble":[Vector2i(2,6),Vector2i(5,6)],"outlets":[Vector2i(2,7),Vector2i(5,7)],"minimum_tier":5,"demand":1}
}

static func definition(id: String, catalog: GameCatalog) -> Dictionary:
	if not SPECS.has(id): return StateAdmission.fail("unknown_room")
	var spec: Dictionary = SPECS[id]
	var board := BoardState.new(Vector2i(8,8)); board.room_board = true
	var marked: Array = []
	for index in spec.rubble.size():
		var key := id+"/rubble/"+str(index)
		board.obstacles[key] = {"id":key,"cell":spec.rubble[index],"kind":"rubble","durability":2}
		if spec.objective == "clear_marked_rubble": marked.append(key)
	return RoomDefinition.admit({"schema":2,"id":id,"initial_board":board.to_dict(),"work":spec.work,"craft":1,
		"objective":spec.objective,"marked_ids":marked,"outlets":spec.outlets,"minimum_tier":spec.minimum_tier,"demand":spec.demand,
		"outlet_requires_clear":true,"outlet_requires_unlocked":true},catalog)
