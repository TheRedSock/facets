class_name MergeMoveContext
extends ActionContext
## Successor-only accounting. Legacy ActionContext facts remain byte-identical.
var move_id := 0
var classification := "equilibrium"
var entitlement := 0
var raw_bonus := 0
var uses := {}
var direct_batch := true
var modifier_bonus := 0
var modifier_trigger := "direct"
var modifier_scope := "move"
var modifier_context := "intervention"
var modifier_family := ""
var room_uses := {}
var run_uses := {}

func _init(candidate: RunState, command: RoomCommand, identity: int, origin: String) -> void:
	move_id = identity
	classification = origin
	super(candidate, command)

func emit(kind: String, payload: Dictionary, ancestry: Variant = -1) -> int:
	var id := super.emit(kind, payload, ancestry)
	if id != 0:
		facts.back().root_action_id = move_id
		facts.back().move_context = classification
		facts.back().direct_input_batch = direct_batch
	return id

func settle_increment() -> void:
	var total := mini(int(state.rules.value("craft_gain_cap")), best_craft + raw_bonus) if reward_eligible else 0
	var delta := maxi(0, total - entitlement)
	var old := state.room.craft
	state.room.craft += mini(delta, int(state.rules.value("craft_capacity")) - old)
	entitlement = maxi(entitlement, total)
	emit("craft_settled", {"base_candidate":best_craft,"bonus_candidate":raw_bonus,
		"eligible_award":delta,"gain":state.room.craft-old,"before":old,"after":state.room.craft})

func match_step(value: Dictionary) -> void:
	var first := facts.size()
	super.match_step(value)
	for fact in facts.slice(first):
		if fact.type == "match_committed": MergeReactionScope.reward(self,fact)
	if state.rules.is_p3(): FamilyDispatcher.dispatch(self,facts.slice(first))

func damage_component(component: Dictionary, source_event: int) -> void:
	if not state.rules.is_p3():
		super.damage_component(component,source_event)
		return
	FamilyDispatcher.damage(self,component,source_event)

func capture() -> Dictionary:
	var depths: Array = []
	var ids := _depths.keys(); ids.sort()
	for id in ids: depths.append([id,_depths[id]])
	return {"move_id":move_id,"classification":classification,"entitlement":entitlement,
		"raw_bonus":raw_bonus,"uses":uses.duplicate(true),"cause":cause,"reward_eligible":reward_eligible,
		"best_craft":best_craft,"root":root,"parent":parent,"step":step,"component_index":component_index,
		"segment":segment,"depths":depths,"facts":facts.duplicate(true),"work":budget.work,
		"fact_count":budget.facts,"error":budget.error,"direct_batch":direct_batch,
		"modifier_bonus":modifier_bonus,"modifier_trigger":modifier_trigger,"modifier_scope":modifier_scope,
		"modifier_context":modifier_context,"modifier_family":modifier_family,
		"room_uses":room_uses.duplicate(true),"run_uses":run_uses.duplicate(true)}

static func from_capture(candidate: RunState, data: Dictionary) -> MergeMoveContext:
	var next_event := candidate.next_event
	var result := MergeMoveContext.new(candidate,RoomCommand.begin(candidate.revision),data.move_id,data.classification)
	candidate.next_event = next_event
	for key in ["entitlement","raw_bonus","uses","cause","reward_eligible","best_craft","root","parent","step","component_index","segment","facts","direct_batch","modifier_bonus","modifier_trigger","modifier_scope","modifier_context","modifier_family","room_uses","run_uses"]:
		result.set(key,data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key])
	result._depths.clear()
	for item in data.depths: result._depths[item[0]] = item[1]
	result._journeys.clear()
	result.budget.work = data.work; result.budget.facts = data.fact_count; result.budget.error = data.error
	return result
