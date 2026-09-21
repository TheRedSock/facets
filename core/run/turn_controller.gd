class_name TurnController
extends RefCounted

var match_detector := MatchDetector.new()
var match_classifier := MatchClassifier.new()
var effect_planner := EffectPlanner.new()
var conflict_resolver := ConflictResolver.new()
var effect_resolver: EffectResolver
var board_physics := BoardPhysics.new()
var spawn_resolver: SpawnResolver
var rules := RuleSet.new()
## Explicit diagnostic injection, never serialized as game policy.
var fail_at := ""
## Optional legacy diagnostics; canonical facts/checkpoints do not consume these.
var capture_step_hashes := true
const MAX_CASCADE_DEPTH := 50
const MAX_CHAIN_DEPTH := 20
var _prepared: EventTimeline
var _cursor := 0

func _init(catalog: GameCatalog = null) -> void:
	spawn_resolver = SpawnResolver.new(catalog)
	effect_resolver = EffectResolver.new(catalog)

func execute_turn(board: BoardState, rng: SeededRng, supply: SpawnTableResource, event_log: EventLog, swap_cells: Array[Vector2i] = [], context: ActionContext = null, cursor: Dictionary = {}, park_before_gravity: bool = false) -> EventTimeline:
	var timeline := EventTimeline.new()
	var budget := context.budget if context != null else ResolutionBudget.new(rules)
	if cursor.is_empty(): cursor.merge({"phase":"scan","cascade":0,"first":true})
	var cascade: int = cursor.cascade
	var first: bool = cursor.first
	while true:
		if cursor.phase == "done": return timeline
		if cursor.phase == "scan":
			if not budget.spend(board.size.x * board.size.y * 2): return _failure(timeline, budget.error, budget)
			var matches := match_classifier.classify(match_detector.find_matches(board))
			if not matches.is_empty():
				if cascade >= int(rules.value("max_cascades")): return _failure(timeline, "cascade_cap", budget)
				var chain := 0
				while not matches.is_empty():
					if chain > int(rules.value("max_chains")): return _failure(timeline, "chain_cap", budget)
					var pair: Array[Vector2i] = []
					if first: pair.assign(swap_cells)
					var match_events: Array[Dictionary] = []
					for m in matches:
						var sources: Array = []
						for pos in m.cells: sources.append({"cell": pos, "tile": board.get_tile(pos).to_dict()})
						var survivor: Variant = MatchClassifier.survivor(m.cells, pair) if m.tier < 8 else null
						var fact := m.duplicate(true)
						fact.type = &"match_formed"
						fact.sources = sources
						fact.survivor = survivor
						fact.survivor_id = board.get_tile(survivor).instance_id if survivor != null else ""
						if context != null: fact.obstacle_targets = board.obstacle_neighbors(m.cells)
						match_events.append(fact)
					var plan := conflict_resolver.resolve(effect_planner.build_base_plan(matches, pair), board)
					if not budget.spend(plan.size(), matches.size() + plan.size() * 2): return _failure(timeline, budget.error, budget)
					if effect_resolver.apply(board, plan, event_log) < 0: return _failure(timeline, effect_resolver.last_error, budget)
					if fail_at == "after_promotion": return _failure(timeline, "injected_after_promotion", budget)
					var step := {"cascade_index": cascade, "chain_index": chain, "match_events": match_events,
						"remove_events": effect_resolver.last_remove_events.duplicate(true), "upgrade_events": effect_resolver.last_upgrade_events.duplicate(true),
						"gravity_events": [], "spawn_events": [], "board_hash": board.compute_hash() if capture_step_hashes else -1}
					timeline.add_cascade_step(step)
					if context != null:
						context.match_step(step)
						if fail_at == "after_obstacle": return _failure(timeline,"injected_after_obstacle",budget)
						if not budget.error.is_empty(): return _failure(timeline,budget.error,budget)
					first = false
					chain += 1
					if not budget.spend(board.size.x * board.size.y * 2): return _failure(timeline, budget.error, budget)
					matches = match_classifier.classify(match_detector.find_matches(board))
				cascade += 1
			cursor.merge({"phase":"gravity","cascade":cascade,"first":first},true)
			if park_before_gravity:
				timeline.work_count = budget.work
				return timeline
		var settled := BoardSettler.resolve(board, rng, supply, spawn_resolver, budget, context.cause if context != null else "normal_swap")
		if not settled.ok: return _failure(timeline, settled.code, budget)
		if fail_at == "after_spawn": return _failure(timeline, "injected_after_spawn", budget)
		var settled_hash := board.compute_hash() if capture_step_hashes and not settled.steps.is_empty() else -1
		for physical in settled.steps:
			physical.cascade_index = cascade
			physical.match_events = []
			physical.remove_events = []
			physical.upgrade_events = []
			physical.board_hash = settled_hash
			timeline.add_cascade_step(physical)
			if context != null: context.physical_step(physical)
		if not budget.spend(board.size.x * board.size.y * 2): return _failure(timeline, budget.error, budget)
		if match_detector.find_matches(board).is_empty():
			cursor.phase = "done"
			break
		cursor.phase = "scan"
	timeline.work_count = budget.work
	return timeline

func _failure(timeline: EventTimeline, code: String, budget: ResolutionBudget) -> EventTimeline:
	timeline.failure_code = code
	timeline.work_count = budget.work
	return timeline

## Temporary adapters resolve once, before returning any presentation work.
func prepare_turn(board: BoardState, rng: SeededRng, supply: SpawnTableResource, log: EventLog, pair: Array[Vector2i] = []) -> void:
	_prepared = execute_turn(board,rng,supply,log,pair)
	_cursor = 0

func step_cascade() -> Variant:
	if not is_cascade_active(): return null
	var step: Dictionary = _prepared.cascade_steps[_cursor]
	_cursor += 1
	return step

func is_cascade_active() -> bool:
	return _prepared != null and _prepared.failure_code.is_empty() and _cursor < _prepared.cascade_steps.size()
