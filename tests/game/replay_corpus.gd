class_name GameReplayCorpus
extends RefCounted

static func run(test: SceneTree) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/seeds.json"))
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/p1-checkpoints.json"))
	var report := {"protocol":"facets-replay-v1","platform":OS.get_name(),"godot":Engine.get_version_info().string,"seeds":[],"actions":0,"failures":[]}
	var timings: Array = []
	var work_counts: Array = []
	var segment_counts: Array = []
	var initial_failures: int = test.failures.size()
	for seed_number in manifest.seeds:
		var seed_value := int(seed_number)
		var controller := RunController.new()
		if not controller.start_new_run({"seed":seed_value}):
			test.check(false,"corpus opening: %d/%s" % [seed_value,controller.last_error])
			report.failures.append({"seed":seed_value,"code":controller.last_error}); continue
		var snapshots: Array = [CanonicalCodec.encode(controller.run_state.to_dict())]
		for action_index in 20:
			var commands := controller.enumerate_legal_swaps()
			if commands.is_empty(): break
			var command: SwapCommand = commands[(seed_value + action_index) % commands.size()]
			var started := Time.get_ticks_usec()
			var result := controller.apply_action(command)
			timings.append(Time.get_ticks_usec() - started)
			if not result.ok:
				test.check(false,"corpus action: %d/%d/%s" % [seed_value,action_index,result.code])
				report.failures.append({"seed":seed_value,"action":action_index,"code":result.code}); break
			report.actions += 1
			var expected: Dictionary = baseline.seeds[seed_value].checkpoints[action_index]
			test.check(result.state_digest == expected.state_digest and result.event_digest == expected.event_digest,"P1 frozen checkpoint seed %d action %d" % [seed_value,action_index])
			work_counts.append(result.timeline.work_count)
			var segments := 0
			for fact in result.facts:
				if fact.type == "tile_moved": segments += fact.path.size()
			segment_counts.append(segments)
			snapshots.append(CanonicalCodec.encode(controller.run_state.to_dict()))
		var replay := controller.export_replay()
		var verified := ReplayRecord.verify(CanonicalCodec.decode(CanonicalCodec.encode(replay)).value)
		test.check(verified.ok and verified.state.digest() == controller.run_state.digest(), "fresh full replay seed %d" % seed_value)
		var midpoint: int = replay.commands.size() / 2
		var resumed := RunController.new()
		test.check(resumed.restore_bytes(snapshots[midpoint]), "resume stable boundary seed %d" % seed_value)
		for i in range(midpoint,replay.commands.size()):
			var expected: Dictionary = replay.commands[i]
			var result := resumed.apply_action(SwapCommand.parse(expected.command))
			test.check(result.ok and result.state_digest == expected.state_digest and result.event_digest == expected.event_digest,"resumed checkpoint seed %d action %d" % [seed_value,i])
		test.check(resumed.run_state.digest() == controller.run_state.digest(), "resume final identity seed %d" % seed_value)
		report.seeds.append({"seed":seed_value,"actions":replay.commands.size(),"phase":controller.run_state.phase,"state_digest":controller.run_state.digest(),"opening_attempts":controller.run_state.opening_attempts,"checkpoints":replay.commands})
		if report.seeds.size() % 10 == 0: print("Replay corpus: %d/100 seeds" % report.seeds.size())
	timings.sort()
	if not timings.is_empty():
		report.p95_action_ms = timings[mini(timings.size()-1,int(ceil(timings.size()*0.95))-1)] / 1000.0
		report.max_action_ms = timings[-1] / 1000.0
		report.target_5ms_met = report.p95_action_ms <= 5.0
		report.max_work = work_counts.max(); report.max_segments = segment_counts.max()
	report.assertion_failures = test.failures.size() - initial_failures
	report.status = "pass" if report.failures.is_empty() and report.assertion_failures == 0 and report.seeds.size() == 100 else "fail"
	DirAccess.make_dir_recursive_absolute("res://artifacts/game/p1-implementation")
	var file := FileAccess.open("res://artifacts/game/p1-implementation/replay-corpus.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	test.check(report.status == "pass", "100-seed corpus no discarded failures")
	print("Replay timing: p95=%s ms max=%s ms" % [report.get("p95_action_ms"),report.get("max_action_ms")])
