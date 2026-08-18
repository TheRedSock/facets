extends SceneTree
## Kernel v1 feature validation: grade axes, inclusions, wear, volume, zoning,
## dispersion, fluorescence, GPU print pass — all through LapidaryStoneCompiler.
## Species are built in code (the authored .tres data lands in a parallel
## workstream); optics constants here are the verified ones.
## Run:  godot --path . --script res://tools/kernel_v1_check.gd

const OUT_DIR := "res://artifacts/lookdev/kernel_v1"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failures := 0
	var lights := _spike_lights()

	# --- T1-like quartz: windowed + worn + included + milky (grade does ALL of it) ---
	var quartz := _species_quartz()
	var t1 := _stone("t1_check", quartz, null, _grade(0.30, 0.30, 0.30, 0.40), 11, 5.0)
	failures += _render(t1, lights, {"max_bounces": 24, "volume": 2, "birefringence": false, "dispersion": false},
		"quartz_t1", 256, 96)

	# --- Ruby-ish corundum: high grade, silk vocabulary at low density, fluorescence ---
	var corundum := _species_corundum()
	var ruby_chromo := GemChromophore.new()
	ruby_chromo.chromophore_id = &"check_ruby"
	ruby_chromo.absorption_mm = _ruby_placeholder()
	var t7 := _stone("t7_check", corundum, ruby_chromo, _grade(0.92, 0.80, 0.90, 0.95), 7, 5.2)
	failures += _render(t7, lights, {"max_bounces": 28, "volume": 2, "birefringence": false, "dispersion": false},
		"ruby_t7", 256, 96)

	# --- Diamond: exceptional, dispersion split on ---
	var diamond := _species_diamond()
	var t8 := _stone("t8_check", diamond, null, _grade(1.0, 1.0, 1.0, 1.0), 3, 5.5)
	failures += _render(t8, lights, {"max_bounces": 32, "volume": 0, "birefringence": false, "dispersion": true},
		"diamond_t8", 256, 128)

	print("KERNEL_V1 %s" % ("FAILED (%d)" % failures if failures > 0 else "COMPLETE"))
	quit(1 if failures > 0 else 0)


func _render(stone: GemStone, lights: PackedFloat32Array, policy: Dictionary,
		tag: String, res: int, spp: int) -> int:
	var instance := LapidaryStoneCompiler.compile(stone)
	var tracer := GemTracer.create(res, res)
	if tracer == null:
		print("  %s: NO RD" % tag)
		return 1
	tracer.set_seed(stone.seed)
	tracer.configure_stone(instance, lights, policy)
	tracer.set_clip_sample(Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0)), 0.0, Vector4.ONE, 1.3)
	var total_ms := 0.0
	var batches := int(ceil(spp / 16.0))
	for i in batches:
		total_ms += tracer.accumulate(16)
	var print_res := GemPrint.new()
	var img_raw := tracer.finalize_print(null, true, 1.6)
	var img_print := tracer.finalize_print(print_res, false, 1.6)
	img_raw.save_png(ProjectSettings.globalize_path("%s/%s_raw.png" % [OUT_DIR, tag]))
	img_print.save_png(ProjectSettings.globalize_path("%s/%s_print.png" % [OUT_DIR, tag]))
	var incl_count: int = instance["inclusions"].size() / 16
	print("  %s: %d spp %.1f ms gpu, %d planes, %d inclusion prims -> %s_{raw,print}.png" % [
		tag, tracer.samples_accumulated, total_ms, instance["planes"].size() / 8, incl_count, tag])
	tracer.release()
	return 0


func _stone(id: String, species: GemSpecies, chromo: GemChromophore, grade: GemGrade,
		seed: int, size: float) -> GemStone:
	var s := GemStone.new()
	s.stone_id = StringName(id)
	s.species = species
	s.chromophore = chromo
	s.grade = grade
	s.seed = seed
	s.size_mm = size
	return s


func _grade(c: float, cl: float, su: float, cr: float) -> GemGrade:
	var g := GemGrade.new()
	g.cut = c
	g.clarity = cl
	g.surface = su
	g.crystal = cr
	return g


func _species_quartz() -> GemSpecies:
	var s := GemSpecies.new()
	s.species_id = &"check_quartz"
	# Crystalline alpha-quartz o-ray (Ghosh 1999): n_D ~= 1.5443
	s.sellmeier_b = Vector3(1.07044083, 1.10202242, 0.0)
	s.sellmeier_c_um2 = Vector3(0.0100585997, 100.0, 0.0)
	s.birefringence = 0.009
	s.hardness_mohs = 7.0
	s.base_polish_roughness = 0.010
	s.zoning_frequency = 3.0
	s.zoning_contrast = 0.3
	var cloud := GemInclusionArchetype.new()
	cloud.archetype_id = &"milky_cloud"
	cloud.form = GemInclusionArchetype.Form.CLOUD
	cloud.size_mm_range = Vector2(0.3, 0.9)
	cloud.scatter_density = 6.0
	cloud.weight = 2.0
	var veil := GemInclusionArchetype.new()
	veil.archetype_id = &"milky_veil"
	veil.form = GemInclusionArchetype.Form.VEIL
	veil.size_mm_range = Vector2(0.4, 1.0)
	veil.scatter_density = 4.0
	s.inclusions = [cloud, veil]
	return s


func _species_corundum() -> GemSpecies:
	var s := GemSpecies.new()
	s.species_id = &"check_corundum"
	# Malitson 1962 ordinary ray: n_D ~= 1.768
	s.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	s.sellmeier_c_um2 = Vector3(0.00527993, 0.01423827, 325.01783)
	s.birefringence = 0.008
	s.hardness_mohs = 9.0
	s.base_polish_roughness = 0.006
	s.fluorescence_emission_nm = 693.0
	s.fluorescence_strength = 0.5
	var silk := GemInclusionArchetype.new()
	silk.archetype_id = &"silk"
	silk.form = GemInclusionArchetype.Form.NEEDLE
	silk.size_mm_range = Vector2(0.4, 1.1)
	silk.aspect = 26.0
	silk.orientation_axes = [Vector3(1, 0, 0), Vector3(0.5, 0.866, 0), Vector3(-0.5, 0.866, 0)]
	silk.scatter_density = 5.0
	s.inclusions = [silk]
	return s


func _species_diamond() -> GemSpecies:
	var s := GemSpecies.new()
	s.species_id = &"check_diamond"
	# Peter 1923: C values SQUARED into um^2.
	s.sellmeier_b = Vector3(4.3356, 0.3306, 0.0)
	s.sellmeier_c_um2 = Vector3(0.0112360, 0.0306250, 0.0)
	s.birefringence = 0.0
	s.hardness_mohs = 10.0
	s.base_polish_roughness = 0.004
	return s


static func _ruby_placeholder() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		var a := 0.05
		if wl < 445.0:
			a = 0.85
		elif wl < 500.0:
			a = 0.30
		elif wl < 610.0:
			a = 1.30
		elif wl < 640.0:
			a = 0.35
		arr[i] = a
	return arr


func _spike_lights() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for l in [
		[Vector3(-0.5, 0.8, 0.6), 14.0, 8.0, 5500.0, 3.2, 0.0],
		[Vector3(0.65, 0.25, 0.72), 30.0, 18.0, 6500.0, 0.7, 0.0],
		[Vector3(0.35, -0.62, -0.70), 5.0, 2.5, 7000.0, 2.4, 0.0],
	]:
		var d: Vector3 = l[0]
		d = d.normalized()
		arr.append_array(PackedFloat32Array([
			d.x, d.y, d.z, cos(deg_to_rad(l[1])),
			l[3], l[4], cos(deg_to_rad(l[2])), l[5]]))
	return arr
