class_name ActionContext
extends RefCounted
## One atomic room command owns costs, effects, ancestry and all resolution limits.
var state: RunState
var budget: ResolutionBudget
var facts: Array = []
var cause := "normal_swap"
var reward_eligible := true
var best_craft := 0
var root := 0
var parent := 0
var step := -1
var component_index := 0
var segment := 0
var _depths := {}
var _journeys := {}

func _init(candidate: RunState, command: RoomCommand) -> void:
	state = candidate
	budget = ResolutionBudget.new(state.rules)
	cause = "normal_swap" if command.data.kind == "swap" else ("setup" if command.data.kind == "begin_room" else "tool")
	reward_eligible = cause == "normal_swap"
	root = emit("action_started",{"command":command.to_dict(),"cost":1 if cause == "normal_swap" else 0},null)
	parent = root

func emit(kind: String, payload: Dictionary, ancestry: Variant = -1) -> int:
	if not budget.spend(0,1): return 0
	var id := state.next_event
	state.next_event += 1
	var prior: Variant = parent if ancestry is int and ancestry == -1 else ancestry
	var fact := payload.duplicate(true)
	fact.merge({"type":kind,"event_id":id,"root_action_id":state.next_action,
		"parent_event_id":prior,"causal_depth":0 if prior == null else int(_depths.get(prior,0))+1,
		"cause":cause,"reward_eligible":reward_eligible,"step":step})
	_depths[id] = fact.causal_depth
	facts.append(fact)
	return id

func removed(source: Dictionary, cell: Vector2i, reason: String, survivor: String = "", ancestry: int = -1) -> void:
	var removal := state.next_removal
	state.next_removal += 1
	var payload := {"instance_id":source.instance_id,"cell":cell,"source":source,
		"reason":reason,"survivor_id":survivor,"removal_id":removal}
	var id := emit("tile_removed",payload,ancestry)
	if reason == "merge_consumption": emit("tile_consumed",payload,id)
	if reason == "terminal_recovery": state.terminal_recovered["8"] = state.terminal_recovered.get("8",0)+1
	# A consumed occupant cannot leave an orphan movement lock behind.
	if state.board.get_tile(cell) == null and not state.board.get_cell(cell).lock.is_empty():
		var lock := state.board.get_cell(cell).lock.duplicate(true)
		state.board.get_cell(cell).lock = {}
		emit("lock_cleared",{"cell":cell,"instance_id":source.instance_id,"old":lock},id)

func match_step(value: Dictionary) -> void:
	step += 1
	_journeys.clear()
	var batch_parent := parent
	for component in value.match_events:
		component_index += 1
		var id := emit("match_committed",{"component_id":component_index,"round":value.chain_index,
			"cascade":value.cascade_index,"sources":component.sources,"cells":component.cells,
			"tier":component.tier,"line_lengths":component.line_lengths,"intersection":component.intersection,
			"size_class":component.size_class,"survivor":component.survivor,"survivor_id":component.survivor_id},batch_parent)
		if reward_eligible:
			best_craft = maxi(best_craft,2 if component.intersection or component.size_class >= 5 else (1 if component.size_class == 4 else 0))
		for source in component.sources:
			if source.tile.instance_id != component.survivor_id:
				removed(source.tile,source.cell,"terminal_recovery" if component.tier == 8 else "merge_consumption",component.survivor_id,id)
		for promoted in value.upgrade_events:
			if promoted.instance_id == component.survivor_id:
				emit("tile_promoted",{"instance_id":promoted.instance_id,"cell":promoted.cell,"old":promoted.old,"new":promoted.new},id)
		damage_component(component,id)
		parent = id

func damage_component(component: Dictionary, source_event: int) -> void:
	for target in component.obstacle_targets: ObstacleResolver.damage(self,target.id,1,source_event)

func physical_step(value: Dictionary) -> void:
	if not budget.error.is_empty(): return
	step += 1
	for movement in value.gravity_events:
		var path := {"from":movement.from,"to":movement.to,"kind":movement.kind,"round":movement.round,"sequence":segment,"step":step}
		segment += 1
		if not _journeys.has(movement.instance_id):
			emit("tile_moved",{"instance_id":movement.instance_id,"tile_id":str(movement.tile_id),"tier":movement.tier,
				"from":movement.from,"to":movement.to,"movement":"settling","path":[]})
			if not budget.error.is_empty(): return
			_journeys[movement.instance_id] = facts.size()-1
		var journey: Dictionary = facts[_journeys[movement.instance_id]]
		journey.to = movement.to; journey.path.append(path)
	for spawn in value.spawn_events:
		emit("tile_spawned",{"instance_id":spawn.instance_id,"cell":spawn.cell,"source":spawn.source,"direction":spawn.direction})
