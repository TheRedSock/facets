class_name MotionPlan
extends RefCounted
## Pure presentation projection. Does not advance rules or allocate rule IDs.
## Dense, ordinary DOWN lanes are proven independent; other paths retain order.

static func build(result: Dictionary) -> Array:
	var phases: Array = []
	var physical: Array = []
	var ordinary := _ordinary(result.before)
	for step in result.timeline.cascade_steps:
		if not step.match_events.is_empty():
			if not physical.is_empty():
				phases.append(_wave(physical,ordinary)); physical = []
			phases.append({"kind":"match","step":step})
		elif not step.gravity_events.is_empty() or not step.spawn_events.is_empty():
			physical.append(step)
	if not physical.is_empty(): phases.append(_wave(physical,ordinary))
	return phases

static func _ordinary(board: BoardState) -> bool:
	if not board._portals.is_empty(): return false
	for pos in board.all_cells():
		var cell := board.get_cell(pos)
		if cell.blocked or not cell.fill_sources.is_empty() or not cell.lock.is_empty(): return false
		if board.get_effective_gravity(pos) != Vector2i.DOWN: return false
		if cell.tile != null and cell.tile.immovable: return false
	return true

static func _wave(steps: Array, ordinary: bool) -> Dictionary:
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
	for journey in journeys.values():
		if journey.spawn:
			# New pieces occupy the top gap in each ordinary lane. Stage a spaced
			# incoming stack, preserving the canonical final ordering and identity.
			journey.from = journey.to - Vector2i(0,spawns_by_column.get(journey.to.x,0))
			if journey.from.y >= 0: ordinary = false
		journey.start = 0.0
		journey.duration = AnimationSequencer.fall_duration(maxi(1,journey.to.y - journey.from.y))
		duration = maxf(duration,journey.duration)
	return {"kind":"travel","concurrent":ordinary,"journeys":journeys.values(),"steps":steps,
		"motion_seconds":duration if ordinary else serial_seconds,"serial_seconds":serial_seconds}
