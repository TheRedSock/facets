extends SceneTree
## Board-live feasibility: N gems in one batched dispatch at sprite size.
## Measures 1 / 16 / 64 gems per frame at BOARD_LIVE rung — the number that
## decides sprite clips vs live 3D.
## Run:  godot --path . --script res://tools/board_grid_check.gd

const OUT_DIR := "res://artifacts/lookdev/board_grid"
const CELL := 112


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var lights := GemRigCompiler.compile(rig)

	var policy: Dictionary = GemRung.policy(GemRung.BOARD_LIVE)
	var instances := _four_instances()
	var failures := 0

	for grid_n: int in [1, 4, 8]:
		var grid := Vector2i(grid_n, grid_n)
		var count := grid_n * grid_n
		var tracer := GemTracer.create(CELL * grid_n, CELL * grid_n)
		if tracer == null:
			failures += 1
			continue
		tracer.configure_stones(instances, lights, policy, grid)
		var states: Array = []
		for i in count:
			states.append({
				"quat": Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0))
					* Quaternion(Vector3(0, 1, 0), deg_to_rad(float(i) * 13.7)),
				"stone_index": i % instances.size(),
				"ortho_half": 1.3,
			})
		tracer.set_instances(states)
		# Warm-up dispatch, then measure steady-state frames.
		tracer.accumulate(int(policy["spp"]))
		var frame_ms: Array[float] = []
		for f in 5:
			tracer.reset_accumulation()
			frame_ms.append(tracer.accumulate(int(policy["spp"])))
		var med := frame_ms[2]
		frame_ms.sort()
		med = frame_ms[2]
		var img := tracer.finalize_print(GemPrint.load_house(), false, 1.0)
		img.save_png(ProjectSettings.globalize_path("%s/grid_%dx%d.png" % [OUT_DIR, grid_n, grid_n]))
		print("  %d gems @%dpx spp=%d: median %.2f ms/frame (%.1f ms/gem) -> grid_%dx%d.png" % [
			count, CELL, int(policy["spp"]), med, med / float(count), grid_n, grid_n])
		tracer.release()

	print("BOARD_GRID %s" % ("FAILED" if failures > 0 else "COMPLETE"))
	quit(1 if failures > 0 else 0)


func _four_instances() -> Array:
	var out: Array = []
	for id in ["quartz", "ruby", "diamond", "sapphire"]:
		out.append(LapidaryStoneCompiler.compile(load("res://data/lapidary/stones/" + id + ".tres")))
	return out
