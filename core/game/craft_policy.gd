class_name CraftPolicy
extends RefCounted

static func settle(context: ActionContext) -> void:
	var state := context.state
	var award := mini(int(state.rules.value("craft_gain_cap")),context.best_craft) if context.reward_eligible else 0
	var gain := mini(award,int(state.rules.value("craft_capacity"))-state.room.craft)
	var old := state.room.craft
	state.room.craft += gain
	context.emit("craft_settled",{"base_candidate":context.best_craft,"bonus_candidate":0,
		"eligible_award":award,"gain":gain,"before":old,"after":state.room.craft})
