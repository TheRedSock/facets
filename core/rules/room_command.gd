class_name RoomCommand
extends RefCounted
## Admitted v2 commands carry the identities selected at a specific revision.
var data: Dictionary

func _init(value: Dictionary) -> void:
	data = GameValue.freeze(value)

func to_dict() -> Dictionary:
	return data.duplicate(true)

func as_swap() -> SwapCommand:
	return SwapCommand.new(data.origin,data.destination)

static func begin(revision: int) -> RoomCommand:
	return RoomCommand.new({"kind":"begin_room","revision":revision})

static func exchange(state: RunState, a: Vector2i, b: Vector2i, tool: bool = false) -> RoomCommand:
	var first := state.board.get_tile(a)
	var second := state.board.get_tile(b)
	return RoomCommand.new({"kind":"action.exchange" if tool else "swap","revision":state.revision,
		"origin":a,"destination":b,"origin_id":first.instance_id if first != null else "",
		"destination_id":second.instance_id if second != null else ""})

static func target(state: RunState, kind: String, cell: Vector2i, layer: String = "gem") -> RoomCommand:
	var obstacle := state.board.obstacle_at(cell)
	var tile := state.board.get_tile(cell)
	return RoomCommand.new({"kind":kind,"revision":state.revision,"cell":cell,"layer":layer,
		"target_id":obstacle.get("id","") if layer == "obstacle" else (tile.instance_id if tile != null else "")})

static func parse(value: Variant) -> RoomCommand:
	if not value is Dictionary or not value.get("revision") is int or value.revision < 0 or value.revision > 1000000000: return null
	match value.get("kind"):
		"begin_room":
			if not StateAdmission.exact(value,["kind","revision"]): return null
		"swap", "action.exchange":
			if not StateAdmission.exact(value,["kind","revision","origin","destination","origin_id","destination_id"]): return null
			if not value.origin is Vector2i or not value.destination is Vector2i or not GameValue.valid_id(value.origin_id) or not GameValue.valid_id(value.destination_id): return null
		"action.clear_target", "action.promote_target":
			if not StateAdmission.exact(value,["kind","revision","cell","layer","target_id"]): return null
			if not value.cell is Vector2i or value.layer not in ["obstacle","lock","gem"] or not GameValue.valid_id(value.target_id): return null
		_: return null
	return RoomCommand.new(value)
