class_name MergeMoveContext
extends ActionContext
## Successor-only accounting. Legacy ActionContext facts remain byte-identical.
var move_id := 0
var classification := "equilibrium"
var entitlement := 0
var raw_bonus := 0
var uses := {}

func _init(candidate: RunState, command: RoomCommand, identity: int, origin: String) -> void:
	move_id = identity
	classification = origin
	super(candidate, command)

func emit(kind: String, payload: Dictionary, ancestry: Variant = -1) -> int:
	var id := super.emit(kind, payload, ancestry)
	if id != 0:
		facts.back().root_action_id = move_id
		facts.back().move_context = classification
	return id

func settle_increment() -> void:
	var total := mini(int(state.rules.value("craft_gain_cap")), best_craft + raw_bonus) if reward_eligible else 0
	var delta := maxi(0, total - entitlement)
	var old := state.room.craft
	state.room.craft += mini(delta, int(state.rules.value("craft_capacity")) - old)
	entitlement = maxi(entitlement, total)
	emit("craft_settled", {"base_candidate":best_craft,"bonus_candidate":raw_bonus,
		"eligible_award":delta,"gain":state.room.craft-old,"before":old,"after":state.room.craft})

func capture() -> Dictionary:
	var depths: Array = []
	var ids := _depths.keys(); ids.sort()
	for id in ids: depths.append([id,_depths[id]])
	return {"move_id":move_id,"classification":classification,"entitlement":entitlement,
		"raw_bonus":raw_bonus,"uses":uses.duplicate(true),"cause":cause,"reward_eligible":reward_eligible,
		"best_craft":best_craft,"root":root,"parent":parent,"step":step,"component_index":component_index,
		"segment":segment,"depths":depths,"facts":facts.duplicate(true),"work":budget.work,
		"fact_count":budget.facts,"error":budget.error}

static func from_capture(candidate: RunState, data: Dictionary) -> MergeMoveContext:
	var next_event := candidate.next_event
	var result := MergeMoveContext.new(candidate,RoomCommand.begin(candidate.revision),data.move_id,data.classification)
	candidate.next_event = next_event
	for key in ["entitlement","raw_bonus","uses","cause","reward_eligible","best_craft","root","parent","step","component_index","segment","facts"]:
		result.set(key,data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key])
	result._depths.clear()
	for item in data.depths: result._depths[item[0]] = item[1]
	result._journeys.clear()
	result.budget.work = data.work; result.budget.facts = data.fact_count; result.budget.error = data.error
	return result
