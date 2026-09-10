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
	for maker: Callable in [_quartz_low, _ruby_fine, _diamond_perfect, _sapphire_like]:
		var stone: GemStone = maker.call()
		out.append(LapidaryStoneCompiler.compile(stone))
	return out


func _quartz_low() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(1.07044083, 1.10202242, 0.0)
	sp.sellmeier_c_um2 = Vector3(0.0100585997, 100.0, 0.0)
	sp.hardness_mohs = 7.0
	var cloud := GemInclusionArchetype.new()
	cloud.form = GemInclusionArchetype.Form.CLOUD
	cloud.size_mm_range = Vector2(0.3, 0.9)
	cloud.scatter_density = 6.0
	sp.inclusions = [cloud]
	return _stone(sp, null, [0.3, 0.3, 0.3, 0.4], 11, 5.0)


func _ruby_fine() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	sp.sellmeier_c_um2 = Vector3(0.00527993, 0.01423827, 325.01783)
	sp.hardness_mohs = 9.0
	sp.fluorescence_emission_nm = 693.0
	sp.fluorescence_strength = 0.5
	var ch := GemChromophore.new()
	ch.absorption_mm = _band_curve(0.7, 0.22, 0.95, 0.25, 0.04)
	return _stone(sp, ch, [0.92, 0.85, 0.9, 0.95], 7, 5.2)


func _diamond_perfect() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(4.3356, 0.3306, 0.0)
	sp.sellmeier_c_um2 = Vector3(0.011236, 0.030625, 0.0)
	sp.hardness_mohs = 10.0
	sp.base_polish_roughness = 0.004
	return _stone(sp, null, [1.0, 1.0, 1.0, 1.0], 3, 5.5)


func _sapphire_like() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	sp.sellmeier_c_um2 = Vector3(0.00527993, 0.01423827, 325.01783)
	sp.hardness_mohs = 9.0
	var ch := GemChromophore.new()
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		arr[i] = 0.06 if wl < 500.0 else lerpf(0.15, 1.1, clampf((wl - 500.0) / 180.0, 0.0, 1.0))
	ch.absorption_mm = arr
	return _stone(sp, ch, [0.85, 0.8, 0.85, 0.9], 5, 5.3)


static func _stone(sp: GemSpecies, ch: GemChromophore, g: Array, seed: int, size: float) -> GemStone:
	var grade := GemGrade.new()
	grade.cut = g[0]
	grade.clarity = g[1]
	grade.surface = g[2]
	grade.crystal = g[3]
	var st := GemStone.new()
	st.material.species = sp
	st.material.chromophore = ch
	st.grade = grade
	st.seed = seed
	st.size_mm = size
	return st


static func _band_curve(a_uv: float, a_blue: float, a_green: float, a_orange: float, a_red: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		var a := a_red
		if wl < 445.0:
			a = a_uv
		elif wl < 500.0:
			a = a_blue
		elif wl < 610.0:
			a = a_green
		elif wl < 640.0:
			a = a_orange
		arr[i] = a
	return arr
