class_name P3Policy
extends RefCounted
## Deterministic diagnostic policy, never consulted by player input.
## One-batch candidate evaluation has no access to the live RNG or scene.
static func command(session: MergeSession) -> RoomCommand:
	var state := session.state
	var commands: Array[RoomCommand] = []
	for swap in ActionLegality.enumerate_legal_swaps(state.board): commands.append(RoomCommand.exchange(state,swap.origin,swap.destination))
	commands.append_array(RoomActionLegality.tools(state))
	var best: RoomCommand
	var best_score := -9223372036854775807
	for choice in commands:
		# Tools without a purposeful effect are not useful policy candidates.
		if choice.data.kind == "action.clear_target" and choice.data.layer != "obstacle": continue
		var prepared := session.prepare(choice)
		if not prepared.ok: continue
		var candidate: MergeSession = prepared.candidate
		var value := score(candidate.state)-score(state)
		if choice.data.kind == "swap": value += 40
		else: value -= 20
		if candidate.phase == "complete": value += 1000000
		if value > best_score: best_score = value; best = choice
	return best

static func score(state: RunState) -> int:
	var value := state.room.craft*12
	for obstacle in state.board.obstacles.values(): value -= obstacle.durability*250
	var extraction: bool = state.room.definition.data.objective == "extract"
	if extraction: value += state.room.deliveries.size()*100000
	for cell in state.board.all_cells():
		var tile := state.board.get_tile(cell)
		if tile == null: continue
		value += tile.tier*tile.tier*3
		if extraction and tile.tier >= state.room.definition.data.minimum_tier:
			var distance := 100
			for outlet in state.room.definition.data.outlets: distance = mini(distance,absi(cell.x-outlet.x)+absi(cell.y-outlet.y))
			value += maxi(0,20-distance)*100
	return value
