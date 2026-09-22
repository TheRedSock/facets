class_name MergeProbe
extends Node
## Opt-in release measurements. CPU mode accelerates decision clocks, never
## claims native animation evidence; native mode uses the actual room adapter.
var failures: Array = []
var intervals: Array = []
var rooms: Array = []
var _raw: FileAccess
var _path := ""
var _multiplier := 1
var _process_trace: Array = []
var _process_previous := 0
var _pre_render_us := 0

func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(func(): _pre_render_us = Time.get_ticks_usec())

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_process_trace.append({"us":now,"gap":now-_process_previous,"process":Performance.get_monitor(Performance.TIME_PROCESS),"physics":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)})
	_process_previous = now
	if _process_trace.size() > 20: _process_trace.pop_front()

static func option(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key+"="): return arg.trim_prefix(key+"=")
	return fallback

static func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var sorted := values.duplicate(); sorted.sort()
	return {"count":sorted.size(),"p50":sorted[ceili(sorted.size()*0.50)-1],"p95":sorted[ceili(sorted.size()*0.95)-1],
		"p99":sorted[ceili(sorted.size()*0.99)-1],"max":sorted.back()}

static func choose(session: MergeSession, policy: String, rng: SeededRng) -> RoomCommand:
	var swaps := ActionLegality.enumerate_legal_swaps(session.state.board)
	if session.phase == "merge_window":
		if policy == "all-pass": return null
		var promoted: Array = session.last_batch.facts.filter(func(f: Dictionary) -> bool: return f.type == "tile_promoted").map(func(f: Dictionary) -> String: return f.instance_id)
		if policy in ["survivor","remote"]:
			swaps = swaps.filter(func(s: SwapCommand) -> bool:
				var involved: bool = session.state.board.get_tile(s.origin).instance_id in promoted or session.state.board.get_tile(s.destination).instance_id in promoted
				return involved if policy == "survivor" else not involved)
		if policy == "mixed" and rng.randi_range(0,2) == 0: return null
	elif swaps.is_empty() or policy == "mixed":
		var tools := RoomActionLegality.tools(session.state)
		if not tools.is_empty() and (swaps.is_empty() or (policy == "mixed" and rng.randi_range(0,2) == 0)): return tools[rng.randi_range(0,tools.size()-1)]
	if swaps.is_empty(): return null
	var swap: SwapCommand = swaps[rng.randi_range(0,swaps.size()-1)] if policy == "mixed" else swaps[0]
	var command := RoomCommand.exchange(session.state,swap.origin,swap.destination)
	return command if session.quote(command).ok else null

static func gravity_us(batch: Dictionary) -> int:
	var seconds := 0.0
	for phase in MotionPlan.build(batch):
		if phase.kind == "travel": seconds += phase.motion_seconds+AnimationSequencer.landing_bounce_duration
	return int(seconds*1000000)

func run(path: String) -> void:
	_path = path; _multiplier = int(option("--merge-multiplier","1"))
	if FileAccess.file_exists(path): printerr("FAIL: probe path exists"); get_tree().quit(1); return
	_raw = FileAccess.open(path+".intervals.jsonl",FileAccess.WRITE)
	if _raw == null: printerr("FAIL: probe output directory"); get_tree().quit(1); return
	var report := {"schema":"facets-merge-probe-v1","profile":MergeSession.PROFILE,"godot":Engine.get_version_info().string,
		"executable":OS.get_executable_path(),"editor":OS.has_feature("editor"),"cpu":OS.get_processor_name(),
		"compute_multiplier":_multiplier,"fps_cap":Engine.max_fps,"display":str(DisplayServer.window_get_size()),
		"vsync":DisplayServer.window_get_vsync_mode(),"warmup":"one excluded seed-101 all-pass room before corpus"}
	var began := Time.get_ticks_usec()
	if "--merge-native" in OS.get_cmdline_user_args():
		report.mode = "native"
		await _native(report)
		report.release_cases = await MergeReleaseCases.new().run(get_tree(),_path)
		failures.append_array(report.release_cases.failures)
	elif "--merge-characterization" in OS.get_cmdline_user_args():
		report.mode = "characterization_only"
		report.warmup = "none; each declared characterization includes all of its operations"
		report.characterization = MergeCharacterization.run()
		failures.append_array(report.characterization.failures)
	else:
		report.mode = "accelerated_decision_clock_worker_cpu"
		report.completion_observer = "poll_sleep_100us" if "--merge-cpu-polling" in OS.get_cmdline_user_args() else "worker_semaphore"
		_cpu_room(101,"all-pass",-1,false)
		var count := int(option("--merge-seeds","100")); var repeats := int(option("--merge-repetitions","3"))
		var policies := option("--merge-policies","all-pass,first,survivor,remote,mixed").split(",")
		for repetition in repeats:
			for policy in policies:
				for seed_number in range(1,count+1):
					_cpu_room(seed_number,policy,repetition,true)
					if seed_number%10 == 0:
						print("MERGE_PROGRESS: %d %s %d failures=%d" % [repetition,policy,seed_number,failures.size()])
						_raw.flush(); await get_tree().process_frame
		report.rooms = rooms
		report.intervals = _summarize()
	report.elapsed_seconds = (Time.get_ticks_usec()-began)/1000000.0
	var static_peak := OS.get_static_memory_peak_usage()
	report.static_memory_peak_bytes = static_peak if static_peak > 0 else null
	report.status = "passed" if failures.is_empty() else "failed"; report.failures = failures
	_raw.close()
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("CHECK_COMPLETE: merge_probe"); get_tree().quit(0 if failures.is_empty() else 1)

func _cpu_room(seed_number: int, policy: String, repetition: int, measured: bool) -> void:
	var game := RunController.new()
	if not game.start_room(null,seed_number): failures.append("room_start"); return
	game.apply_action(RoomCommand.begin(0))
	var session := MergeSession.new()
	if not session.start(game.run_state.to_dict()): failures.append("session_start"); return
	var polling := "--merge-cpu-polling" in OS.get_cmdline_user_args()
	var notice := Semaphore.new()
	var executor := MergeExecutor.new(session,null if polling else notice); executor.compute_multiplier = _multiplier
	var rng := SeededRng.new(); rng.reseed(900000+seed_number)
	var tags := {"seed":seed_number,"policy":policy,"repetition":repetition}
	var prior_gravity := 0; var count := 0; var intervention_count := 0
	while session.phase in ["ready","merge_window","gravity"] and count < 500:
		# A completion can be polled before its posted notification is consumed.
		# Drain only between jobs; a superseded default may also wake the observer.
		while notice.try_wait(): pass
		var phase := session.phase
		var command: RoomCommand
		var interval := 150000
		var scheduling := Time.get_ticks_usec()
		var default_schedule_us := 0
		if phase == "merge_window":
			session.presented(); executor.prepare_default()
			default_schedule_us = Time.get_ticks_usec()-scheduling
			command = choose(session,policy,rng)
			if command != null:
				session.tick(19 if policy == "mixed" else 0)
				intervention_count += 1
			else: interval = 333333
		elif phase == "ready":
			command = choose(session,policy,rng)
			if command == null: failures.append(str(tags)+"/no_ready_action"); break
		else: interval = prior_gravity
		# Policy search is diagnostic driver work, outside measured game scheduling.
		scheduling = Time.get_ticks_usec()
		if command != null:
			if not executor.submit(command).ok: failures.append(str(tags)+"/submit"); break
		elif phase == "gravity": executor.continue_gravity()
		var schedule_us := Time.get_ticks_usec()-scheduling
		var result := {}
		var timeout := Time.get_ticks_usec()+10000000
		var poll_us := 0
		var sleep_us := 0
		var sleep_max_us := 0
		var sleep_count := 0
		while result.is_empty() and Time.get_ticks_usec() < timeout:
			var began := Time.get_ticks_usec()
			result = executor.poll(); poll_us = maxi(poll_us,Time.get_ticks_usec()-began)
			if result.is_empty():
				var sleep_began := Time.get_ticks_usec()
				# CPU-only observer: wake on mailbox completion instead of rounding
				# an arbitrary 100us sleep to the OS timer quantum. The external
				# process watchdog handles a broken worker; native never waits here.
				if polling: OS.delay_usec(100)
				else: notice.wait()
				var slept := Time.get_ticks_usec()-sleep_began
				sleep_us += slept; sleep_max_us = maxi(sleep_max_us,slept); sleep_count += 1
		if result.is_empty(): failures.append(str(tags)+"/timeout"); break
		if result.get("status") == "default_ready":
			session.tick(20)
			var began := Time.get_ticks_usec(); result = executor.release_window()
			poll_us += Time.get_ticks_usec()-began
		if not result.ok: failures.append(str(tags)+"/"+result.get("code","unknown")); break
		var metric: Dictionary = executor.metrics.back().duplicate(true)
		metric.merge(tags,true); metric.phase = phase; metric.batch = session.batch_id
		metric.next_phase = session.phase; metric.available_us = interval
		metric.command = command.data.kind if command != null else "pass"
		metric.main_us = schedule_us+poll_us+default_schedule_us
		metric.observer_wait_us = sleep_us; metric.observer_wait_max_us = sleep_max_us; metric.observer_wait_count = sleep_count
		metric.completion_to_publication_us = metric.published_us-metric.ready_us
		metric.effective_ready_us = metric.latency_us
		metric.ratio = metric.effective_ready_us/float(maxi(1,interval))
		metric.scheduled_deadline_us = metric.submitted_us+interval
		if measured:
			intervals.append(metric); _raw.store_line(JSON.stringify(metric))
			if metric.effective_ready_us > interval: failures.append(str(tags)+"/deadline/"+str(count))
			if _multiplier == 1 and metric.kind != "default" and metric.ratio > 0.5: failures.append(str(tags)+"/headroom/"+str(count))
		if result.batch.kind == "gravity": prior_gravity = gravity_us(result.batch)
		count += 1
	if session.phase not in ["complete","failed"]: failures.append(str(tags)+"/nonterminal/"+session.phase)
	if not executor.shutdown(): failures.append(str(tags)+"/shutdown")
	if measured:
		var record := tags.duplicate(); record.batches = count; record.interventions = intervention_count
		record.phase = session.phase; record.digest = CanonicalCodec.digest(session.mechanical_snapshot()); record.cancelled = executor.discarded
		rooms.append(record)

func _summarize() -> Dictionary:
	var result := {}
	for kind in ["command","gravity","default"]:
		var subset := intervals.filter(func(m: Dictionary) -> bool: return m.kind == kind)
		var summary := {}
		for field in ["effective_ready_us","service_us","main_us","publication_us","ratio"]:
			summary[field] = stats(subset.map(func(m: Dictionary) -> Variant: return m[field]))
		for stage in ["copy","root","resolve","admit","project_hash"]:
			summary[stage] = stats(subset.map(func(m: Dictionary) -> Variant: return m.stages_us.get(stage,0)))
		if _multiplier == 1 and kind != "default" and not subset.is_empty() and summary.ratio.p95 > 0.25: failures.append(kind+"/p95_headroom")
		result[kind] = summary
	var mains := stats(intervals.map(func(m: Dictionary) -> int: return m.main_us))
	result.main_scheduling_us = mains
	if _multiplier == 1 and mains.get("count",0) > 0 and (mains.p95 > 5000 or mains.max > 16700): failures.append("cpu/main_scheduling")
	return result

func _loaded(view: MergeRoomView) -> bool:
	var until := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if not view.error.is_empty(): failures.append(view.error); return false
		if view.board != null and view.board.visible and view.player.live.size() > 0: return true
	failures.append("load_timeout"); return false

static func gesture(view: MergeRoomView, command: RoomCommand, keyboard: bool) -> void:
	if command.data.kind != "swap":
		view._tool = command.data.kind
		if command.data.kind == "action.exchange": view._target(command.data.origin); view._target(command.data.destination)
		else: view._target(command.data.cell)
	elif keyboard:
		view.board.cursor_cell = command.data.origin
		var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_ENTER; view.board._gui_input(key)
		var direction: Vector2i = command.data.destination-command.data.origin
		key = InputEventKey.new(); key.pressed = true
		key.keycode = KEY_RIGHT if direction.x > 0 else (KEY_LEFT if direction.x < 0 else (KEY_DOWN if direction.y > 0 else KEY_UP))
		view.board._gui_input(key)
		key = InputEventKey.new(); key.pressed = true; key.keycode = KEY_ENTER; view.board._gui_input(key)
	else:
		var mouse := InputEventMouseButton.new(); mouse.pressed = true; mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = view.board._board_offset+view.board._cell_to_pixel(command.data.origin)+Vector2(view.board._cell_size)*0.5
		view.board._gui_input(mouse)
		var drag := InputEventMouseMotion.new(); drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		drag.position = view.board._board_offset+view.board._cell_to_pixel(command.data.destination)+Vector2(view.board._cell_size)*0.5
		view.board._gui_input(drag)

func _native(report: Dictionary) -> void:
	var feedback: Array = []; var handoffs: Array = []; var frames: Array = []; var main_times: Array = []
	var samples: Array = []; var native_rooms: Array = []
	var policies := option("--merge-policies","all-pass,first,survivor,remote,mixed").split(",")
	for policy in policies:
		var view := MergeRoomView.new(); view.seed_value = int(option("--merge-native-seed","1"))
		view.reduced_motion = "--merge-reduced" in OS.get_cmdline_user_args()
		get_tree().root.add_child(view)
		if not await _loaded(view): view.queue_free(); continue
		for frame in 30: await get_tree().process_frame
		var forge := get_node("/root/GemForge")
		var warm_loads: int = forge.delivery_report().page_loads
		view.executor.compute_multiplier = _multiplier
		view._begin.pressed.emit()
		var rng := SeededRng.new(); rng.reseed(900000+view.seed_value)
		var last_window := -1; var selected: RoomCommand; var next_tick := 0
		var watched: TileView; var old_position := Vector2.ZERO; var receipt := 0
		var metric_index := 0; var presented_index := 0; var input_count := 0
		var available := {}; var previous := Time.get_ticks_usec()
		var until := Time.get_ticks_msec()+180000
		while Time.get_ticks_msec() < until:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec(); frames.append(now-previous)
			if now-previous > 50000:
				print("NATIVE_STALL: ",now-previous," now=",now," render=",now-_pre_render_us," phase=",view.session.phase," tick=",view.session.clock.tick," main=",view.main_frame_us.get(Engine.get_process_frames(),0)," focus=",DisplayServer.window_is_focused()," default=",not view.executor.default_result.is_empty()," trace=",_process_trace)
			previous = now
			if receipt != 0 and is_instance_valid(watched) and watched.position != old_position:
				feedback.append(now-receipt); samples.append({"kind":"feedback","us":now-receipt,"policy":policy}); receipt = 0
			while presented_index < view.presented_batches.size():
				var visible_batch: Dictionary = view.presented_batches[presented_index]; presented_index += 1
				if visible_batch.expiry_us > 0:
					handoffs.append(now-visible_batch.expiry_us)
					samples.append({"kind":"default_visible","us":now-visible_batch.expiry_us,"policy":policy})
				if visible_batch.kind == "gravity":
					available[visible_batch.batch+1] = view._motion_deadline-visible_batch.us
			while metric_index < view.executor.metrics.size():
				var metric: Dictionary = view.executor.metrics[metric_index].duplicate(true); metric_index += 1
				metric.policy = policy; metric.batch = metric_index
				if metric.kind != "default":
					metric.available_us = available.get(metric_index,150000)
					metric.ratio = metric.latency_us/float(maxi(1,metric.available_us))
					if metric.latency_us > metric.available_us: failures.append(policy+"/native_deadline/"+str(metric_index))
					if _multiplier == 1 and metric.ratio > 0.5: failures.append(policy+"/native_headroom/"+str(metric_index))
				intervals.append(metric)
			if not view.error.is_empty(): failures.append(policy+"/"+view.error); break
			if view.session.clock.paused: failures.append(policy+"/unexpected_assisted_pause"); break
			if view.session.phase in ["complete","failed"] and view.queue.is_empty() and not view.player.motion_busy: break
			if not view.can_input(): continue
			var policy_began := Time.get_ticks_usec()
			if view.session.phase == "merge_window":
				if last_window != view.session.window_id:
					last_window = view.session.window_id; selected = choose(view.session,policy,rng)
					next_tick = 19 if policy == "mixed" else 0
				if selected == null or view.session.clock.tick < next_tick: continue
			else: selected = choose(view.session,policy,rng)
			if selected == null: failures.append(policy+"/no_action"); break
			if Time.get_ticks_usec()-policy_began > 10000: print("SLOW_POLICY: ",Time.get_ticks_usec()-policy_began)
			if selected.data.kind == "swap":
				watched = view.player.live.get(selected.data.origin_id); old_position = watched.position; receipt = Time.get_ticks_usec()
			gesture(view,selected,input_count%2 == 0); input_count += 1; selected = null
		if receipt != 0: failures.append(policy+"/missing_visible_feedback")
		if view.session.phase not in ["complete","failed"]: failures.append(policy+"/nonterminal")
		if view.starvation != 0: failures.append(policy+"/starvation/"+str(view.starvation))
		if int(forge.delivery_report().page_loads) != warm_loads: failures.append(policy+"/cold_load")
		main_times.append_array(view.main_frame_us.values())
		native_rooms.append({"policy":policy,"phase":view.session.phase,"starvation":view.starvation,"inputs":input_count,
			"assisted":view.session.clock.assisted,"digest":CanonicalCodec.digest(view.session.mechanical_snapshot()),
			"complete_snapshot_encoded_bytes":CanonicalCodec.encode(view.session.snapshot()).size()})
		var replayed := MergeReplay.restored(view.session.snapshot(),false)
		if not replayed.ok: failures.append(policy+"/replay/"+replayed.code)
		report.memory = _memory(view)
		var worker := view.executor
		view.queue_free(); await get_tree().process_frame; await get_tree().process_frame
		if worker._thread.is_started() or not worker._pending.is_empty(): failures.append(policy+"/residual_worker")
		await get_tree().create_timer(0.1).timeout
		print("MERGE_NATIVE_PROGRESS: "+policy+" failures="+str(failures.size()))
	report.warmup = "30 asset-warmed idle frames per room; all subsequent active frames included"
	report.rooms = native_rooms; report.feedback_us = stats(feedback); report.handoff_us = stats(handoffs)
	report.frames_us = stats(frames); report.main_us = stats(main_times)
	report.raw_frames_us = frames; report.raw_main_us = main_times; report.presentation_samples = samples
	var ratios := intervals.filter(func(m: Dictionary) -> bool: return m.has("ratio")).map(func(m: Dictionary) -> float: return m.ratio)
	report.ready_ratio = stats(ratios)
	# Persist every native interval after the active measurement. Synchronous
	# filesystem writes inside frame_post_draw can stall the observed renderer.
	for metric in intervals: _raw.store_line(JSON.stringify(metric))
	if _multiplier == 1:
		for gate in [["feedback_us",16700,33400],["handoff_us",16700,33400],["main_us",5000,16700],["frames_us",16700,0],["ready_ratio",0.25,0.5]]:
			var value: Dictionary = report[gate[0]]
			if value.get("count",0) == 0 or value.p95 > gate[1] or (gate[2] > 0 and value.max > gate[2]): failures.append("native_gate/"+gate[0])

func _memory(view: MergeRoomView) -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/workshop_manifest.json"))
	var texture_bytes := 0; var audio_bytes := 0
	for path in manifest.resources:
		if path.ends_with(".svg"):
			var texture: Texture2D = load(path)
			texture_bytes += texture.get_width()*texture.get_height()*4
	for stream in view.audio.streams.values():
		if stream is AudioStreamWAV: audio_bytes += stream.data.size()
	if texture_bytes > 16*1024*1024 or audio_bytes > 2*1024*1024: failures.append("presentation_payload_budget")
	return {"gem":get_node("/root/GemForge").delivery_report(),"non_gem_rgba_bytes":texture_bytes,"decoded_audio_bytes":audio_bytes,
		"scope":"Authored SVG RGBA and decoded PCM payload bounds; font/scene/container/driver overhead belongs to whole-process measurements."}
