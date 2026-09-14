class_name MotionPlan
extends RefCounted
## Pure presentation projection. Does not advance rules or allocate rule IDs.
## Dense, ordinary DOWN lanes are proven independent; other paths retain order.

static func build(result: Dictionary) -> Array:
	var phases: Array = []
	var physical: Array = []
	var ordinary := _ordinary(result.before)
	var displayed: BoardState = result.before.duplicate_board()
	for step in result.timeline.cascade_steps:
		if not step.match_events.is_empty() or not step.remove_events.is_empty() or not step.upgrade_events.is_empty() or not step.get("overlay_events",[]).is_empty() or not step.get("recovery_events",[]).is_empty():
			if not physical.is_empty():
				phases.append(_wave(physical,ordinary,displayed)); physical = []
			phases.append({"kind":"match","step":step})
			for event in step.get("overlay_events",[]):
				if event.type == "obstacle_broken": displayed.obstacles.erase(event.obstacle_id)
				elif event.type == "obstacle_damaged": displayed.obstacles[event.obstacle_id] = event.new.duplicate(true)
		elif not step.gravity_events.is_empty() or not step.spawn_events.is_empty():
			physical.append(step)
	if not physical.is_empty(): phases.append(_wave(physical,ordinary,displayed))
	return phases

static func _ordinary(board: BoardState) -> bool:
	if not board._portals.is_empty(): return false
	for pos in board.all_cells():
		var cell := board.get_cell(pos)
		if cell.blocked or not cell.fill_sources.is_empty() or not cell.lock.is_empty(): return false
		if board.get_effective_gravity(pos) != Vector2i.DOWN: return false
		if cell.tile != null and cell.tile.immovable: return false
	return true

static func _wave(steps: Array, ordinary: bool, displayed: BoardState = null) -> Dictionary:
	var journeys := {}
	var spawns_by_column := {}
	var serial_seconds := 0.0
	for step in steps:
		for event in step.gravity_events:
			serial_seconds += AnimationSequencer.fall_duration(1)
			if event.kind != "gravity" or event.to - event.from != Vector2i.DOWN: ordinary = false
			if not journeys.has(event.instance_id):
				journeys[event.instance_id] = {"instance_id":event.instance_id,"from":event.from,"to":event.to,"path":[],"spawn":false}
			var journey: Dictionary = journeys[event.instance_id]
			journey.to = event.to; journey.path.append(event)
		if not step.spawn_events.is_empty(): serial_seconds += AnimationSequencer.fall_duration(1)
		for event in step.spawn_events:
			journeys[event.instance_id] = {"instance_id":event.instance_id,"from":event.cell,"to":event.cell,"path":[],"spawn":true,"source":event.source}
			if event.direction != Vector2i.DOWN: ordinary = false
			spawns_by_column[event.cell.x] = spawns_by_column.get(event.cell.x,0) + 1
	var duration := 0.0
	if displayed != null and displayed.room_board:
		spawns_by_column.clear()
		for journey in journeys.values():
			if not journey.spawn: continue
			var below_rubble := false
			for obstacle in displayed.obstacles.values():
				if obstacle.cell.x == journey.to.x and obstacle.cell.y < journey.to.y: below_rubble = true
			if not below_rubble: spawns_by_column[journey.to.x] = spawns_by_column.get(journey.to.x,0)+1
	var lane_durations := {}
	for journey in journeys.values():
		if not journey.spawn: lane_durations[journey.to.x] = maxf(lane_durations.get(journey.to.x,0.0),AnimationSequencer.fall_duration(maxi(1,journey.to.y-journey.from.y)))
	for journey in journeys.values():
		journey.start = 0.0
		journey.in_place = false
		if journey.spawn:
			# New pieces occupy the top gap in each ordinary lane. Stage a spaced
			# incoming stack, preserving the canonical final ordering and identity.
			journey.from = journey.to - Vector2i(0,spawns_by_column.get(journey.to.x,0))
			var pocket := false
			if displayed != null and displayed.room_board:
				for obstacle in displayed.obstacles.values():
					if obstacle.cell.x == journey.to.x and obstacle.cell.y < journey.to.y: pocket = true
			if pocket:
				# A source in a rubble pocket appears only after its lane is clear.
				# Never draw a refill through the solid obstacle above it.
				journey.from = journey.to; journey.in_place = true
				journey.start = lane_durations.get(journey.to.x,0.0)
			elif journey.from.y >= 0: ordinary = false
		journey.duration = AnimationSequencer.fall_duration(maxi(1,journey.to.y - journey.from.y))
		duration = maxf(duration,journey.start+journey.duration)
	return {"kind":"travel","concurrent":ordinary,"journeys":journeys.values(),"steps":steps,
		"motion_seconds":duration if ordinary else serial_seconds,"serial_seconds":serial_seconds}
