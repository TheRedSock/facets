extends SceneTree
## Lighting A/B: diamond + ruby-ish under gameplay_studio vs reference_daylight,
## raw and printed. The first-class environment A/B tool (replaces the old
## "compare two environment tres by hand" policy).
## Run:  godot --path . --script res://tools/rig_ab_check.gd

const OUT_DIR := "res://artifacts/lookdev/rig_ab"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rigs := {
		"gameplay": load("res://data/lapidary/rigs/gameplay_studio.tres") as GemLightRig,
		"reference": load("res://data/lapidary/rigs/reference_daylight.tres") as GemLightRig,
	}
	var stones := {
		"diamond": _diamond_stone(),
		"ruby": _ruby_stone(),
	}
	var failures := 0
	for rig_name: String in rigs:
		var rig: GemLightRig = rigs[rig_name]
		if rig == null:
			print("  rig %s FAILED TO LOAD" % rig_name)
			failures += 1
			continue
		var lights := GemRigCompiler.pack(rig)
		for stone_name: String in stones:
			var stone: GemStone = stones[stone_name]
			var instance := LapidaryStoneCompiler.compile(stone)
			var tracer := GemTracer.create(256, 256)
			if tracer == null:
				failures += 1
				continue
			tracer.set_seed(stone.seed)
			tracer.set_background(GemRigCompiler.background(rig))
			var disp: bool = stone_name == "diamond"
			tracer.configure_stone(instance, lights, {"max_bounces": 32, "volume": 2, "dispersion": disp})
			tracer.set_clip_sample(Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0)), 0.0, Vector4.ONE, 1.3)
			var spp := 128 if disp else 96
			var batches := int(ceil(spp / 16.0))
			var ms := 0.0
			for i in batches:
				ms += tracer.accumulate(16)
			var img_raw := tracer.finalize_print(null, true, 1.6)
			var img_print := tracer.finalize_print(GemPrint.new(), false, 1.6)
			img_raw.save_png(ProjectSettings.globalize_path("%s/%s_%s_raw.png" % [OUT_DIR, stone_name, rig_name]))
			img_print.save_png(ProjectSettings.globalize_path("%s/%s_%s_print.png" % [OUT_DIR, stone_name, rig_name]))
			print("  %s @ %s: %.0f ms" % [stone_name, rig_name, ms])
			tracer.release()
	print("RIG_AB %s" % ("FAILED" if failures > 0 else "COMPLETE"))
	quit(1 if failures > 0 else 0)


func _diamond_stone() -> GemStone:
	var sp := GemSpecies.new()
	sp.species_id = &"check_diamond"
	sp.sellmeier_b = Vector3(4.3356, 0.3306, 0.0)
	sp.sellmeier_c_um2 = Vector3(0.011236, 0.030625, 0.0)
	sp.hardness_mohs = 10.0
	sp.base_polish_roughness = 0.004
	var st := GemStone.new()
	st.stone_id = &"ab_diamond"
	st.species = sp
	st.grade = _grade(1, 1, 1, 1)
	st.seed = 3
	st.size_mm = 5.5
	return st


func _ruby_stone() -> GemStone:
	var sp := GemSpecies.new()
	sp.species_id = &"check_corundum"
	sp.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	sp.sellmeier_c_um2 = Vector3(0.00527993, 0.01423827, 325.01783)
	sp.birefringence = 0.008
	sp.hardness_mohs = 9.0
	sp.base_polish_roughness = 0.006
	sp.fluorescence_emission_nm = 693.0
	sp.fluorescence_strength = 0.5
	var ch := GemChromophore.new()
	ch.chromophore_id = &"check_ruby"
	ch.absorption_mm = _ruby_placeholder()
	var st := GemStone.new()
	st.stone_id = &"ab_ruby"
	st.species = sp
	st.chromophore = ch
	st.grade = _grade(0.92, 0.85, 0.9, 0.95)
	st.seed = 7
	st.size_mm = 5.2
	return st


static func _grade(c: float, cl: float, su: float, cr: float) -> GemGrade:
	var g := GemGrade.new()
	g.cut = c
	g.clarity = cl
	g.surface = su
	g.crystal = cr
	return g


static func _ruby_placeholder() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		var a := 0.04
		if wl < 445.0:
			a = 0.70
		elif wl < 500.0:
			a = 0.22
		elif wl < 610.0:
			a = 0.95
		elif wl < 640.0:
			a = 0.25
		arr[i] = a
	return arr
