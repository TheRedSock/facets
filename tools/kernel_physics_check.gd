extends SceneTree
## Analytic kernel physics checks via read_xyz(). Windowed only:
##   godot --path . --script res://tools/kernel_physics_check.gd
##
## Assertions (tolerances, never bit equality):
##   1. Slab transmission ≈ exp(-alpha * L) for a weakly absorbing cube
##   2. Fresnel at normal incidence for n=1.5 is ~4%
##   3. Along-axis vs perpendicular pleochroism (o-ray vs mix)
##   4. Energy never exceeds env radiance ceiling for a colorless empty stone
##   5. The scatter field (deterministic single scattering) agrees with the
##      stochastic estimator in the mean and cuts its two-seed noise by a
##      large factor

const OUT_DIR := "res://artifacts/lookdev/physics"
const ORTHO := 1.4
const SPP := 256
const BATCH := 16


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tracer := GemTracer.create(64, 64)
	if tracer == null:
		print("PHYSICS FAILED: no RenderingDevice (run windowed)")
		quit(1)
		return

	var fails := 0
	fails += 0 if _check_fresnel_ni(tracer) else 1
	fails += 0 if _check_beer_slab(tracer) else 1
	fails += 0 if _check_pleochroism_axes(tracer) else 1
	fails += 0 if _check_energy_bound(tracer) else 1
	tracer.release()

	var field_tracer := GemTracer.create(96, 96)
	fails += 0 if _check_scatter_field(field_tracer) else 1
	field_tracer.release()

	print("KERNEL_PHYSICS %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _policy() -> Dictionary:
	return {
		"max_bounces": 8, "dispersion": false, "birefringence": false,
		"volume": false, "fluorescence": false, "rad_clamp": 1000.0,
		"env_filter_rad": 0.0, "field_exits": 0,
	}


func _single_light(power := 1.0, kelvin := 5600.0) -> PackedFloat32Array:
	# Broad light toward the camera (+Z in stone/world for face-up ortho).
	return PackedFloat32Array([
		0.15, 0.35, 0.92, cos(deg_to_rad(55.0)),
		kelvin, power, cos(deg_to_rad(25.0)), 0.0,
	])


func _fill_light(power := 0.35, kelvin := 6500.0) -> PackedFloat32Array:
	return PackedFloat32Array([
		-0.4, 0.2, 0.7, cos(deg_to_rad(70.0)),
		kelvin, power, cos(deg_to_rad(40.0)), 1.0,
	])


func _studio_lights(key_power := 1.0) -> PackedFloat32Array:
	var a := _single_light(key_power)
	var b := _fill_light()
	a.append_array(b)
	return a


func _cube_planes(half := 0.9) -> PackedFloat32Array:
	var planes := PackedFloat32Array()
	var normals := [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	for n in normals:
		planes.append_array(PackedFloat32Array([n.x, n.y, n.z, half, 0.0, 0.0, 0.0, 0.0]))
	return planes


func _flat_absorb(alpha: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(81)
	for i in 81:
		a[i] = alpha
	return a


func _instance(planes: PackedFloat32Array, absorb: PackedFloat32Array, absorb_e := PackedFloat32Array(),
		opts := {}) -> Dictionary:
	return {
		"planes": planes,
		"absorption": absorb,
		"absorption_eray": absorb_e,
		"inclusions": PackedFloat32Array(),
		"sellmeier_b": opts.get("sellmeier_b", Vector3(0.6961663, 0.4079426, 0.8974794)),
		"sellmeier_c": opts.get("sellmeier_c", Vector3(0.004679148, 0.01351206, 97.934)) ,
		"size_mm": opts.get("size_mm", 4.0),
		"seed": opts.get("seed", 1),
		"scatter": {"sigma_per_mm": 0.0, "g": 0.6},
		"zoning": {"axis": Vector3(0, 0, 1), "frequency": 0.0, "contrast": 0.0, "phase": 0.0},
		"birefringence": opts.get("birefringence", 0.0),
		"optic_axis": opts.get("optic_axis", Vector3(0, 0, 1)),
		"fluorescence": {"nm": 0.0, "strength": 0.0},
		"dispersion_strong": false,
		"absorb_scale": 1.0,
	}


func _mean_y(xyz: PackedFloat32Array) -> float:
	var acc := 0.0
	var n := 0
	var w := 64
	for i in w * w:
		var cov := xyz[i * 4 + 3]
		if cov < 0.05:
			continue
		acc += xyz[i * 4 + 1]
		n += 1
	return acc / float(maxi(n, 1))


## Flat neutral background of one level, no white balance (physics reads scene XYZ).
static func _env(level: float) -> Dictionary:
	return {"bg": Vector4(level, level, level, 0.0), "white_kelvin": 0.0}


func _render_y(tracer: GemTracer, inst: Dictionary, lights: PackedFloat32Array, env: Dictionary) -> float:
	tracer.set_environment(env)
	tracer.configure_stone(inst, lights, _policy())
	tracer.set_seed(int(inst["seed"]))
	tracer.set_clip_sample(Quaternion.IDENTITY, 0.0, Vector4.ONE, ORTHO)
	var left := SPP
	while left > 0:
		var n := mini(BATCH, left)
		tracer.accumulate(n)
		left -= n
	return _mean_y(tracer.read_xyz())


func _check_fresnel_ni(tracer: GemTracer) -> bool:
	# n≈1.5; R = ((n-1)/(n+1))^2 ≈ 0.04. Opaque absorb so only surface R survives.
	var n := 1.5
	var r_expect := pow((n - 1.0) / (n + 1.0), 2.0)
	var lights := _studio_lights(2.0)
	var inst := _instance(_cube_planes(), _flat_absorb(40.0), PackedFloat32Array(), {
		"sellmeier_b": Vector3(0.6962, 0.4079, 0.8975),
		"sellmeier_c": Vector3(0.0047, 0.0135, 97.93),
		"size_mm": 10.0,
	})
	var y := _render_y(tracer, inst, lights, _env(0.0))
	var ok := y > 0.008 and y < 0.25
	print("  fresnel_ni: Y=%.4f expect~%.3f (surface R)  %s" % [y, r_expect, "PASS" if ok else "FAIL"])
	return ok


func _check_beer_slab(tracer: GemTracer) -> bool:
	var alpha := 0.15
	var size_mm := 4.0
	var lights := _studio_lights(2.0)
	var clear := _instance(_cube_planes(0.85), _flat_absorb(0.0), PackedFloat32Array(), {"size_mm": size_mm})
	var tinted := _instance(_cube_planes(0.85), _flat_absorb(alpha), PackedFloat32Array(), {"size_mm": size_mm})
	var y0 := _render_y(tracer, clear, lights, _env(0.05))
	var y1 := _render_y(tracer, tinted, lights, _env(0.05))
	if y0 < 1e-4:
		print("  beer_slab: FAIL clear Y too low (%.6f)" % y0)
		return false
	var ratio := y1 / y0
	var t_theory := exp(-alpha * 2.0 * size_mm)
	var ok := ratio > t_theory * 0.35 and ratio < minf(1.05, t_theory * 2.5 + 0.15)
	print("  beer_slab: Y_tint/Y_clear=%.4f  T_2L=%.4f  %s" % [ratio, t_theory, "PASS" if ok else "FAIL"])
	return ok


func _check_pleochroism_axes(tracer: GemTracer) -> bool:
	var ao := _flat_absorb(0.55)
	var ae := _flat_absorb(0.05)
	var lights := _studio_lights(2.5)
	var along := _instance(_cube_planes(0.85), ao, ae, {
		"size_mm": 3.5, "optic_axis": Vector3(0, 0, 1), "birefringence": -0.008,
	})
	var perp := _instance(_cube_planes(0.85), ao, ae, {
		"size_mm": 3.5, "optic_axis": Vector3(1, 0, 0), "birefringence": -0.008,
	})
	var y_along := _render_y(tracer, along, lights, _env(0.04))
	var y_perp := _render_y(tracer, perp, lights, _env(0.04))
	var ok := y_perp > y_along * 1.05
	print("  pleochroism: Y_along=%.4f  Y_perp=%.4f  %s" % [y_along, y_perp, "PASS" if ok else "FAIL"])
	return ok


func _check_energy_bound(tracer: GemTracer) -> bool:
	var lights := _studio_lights(1.0)
	var inst := _instance(_cube_planes(0.9), _flat_absorb(0.0), PackedFloat32Array(), {"size_mm": 3.0})
	var y := _render_y(tracer, inst, lights, _env(0.02))
	var ok := y < 12.0 and y > 0.01
	print("  energy_bound: Y=%.4f  %s" % [y, "PASS" if ok else "FAIL"])
	return ok


## Scatter field vs stochastic scatter estimator on an authored faceted stone
## with strong milk and the gameplay rig. Both estimate the same integral (the
## field with l<=3 angular resolution and grid-limited spatial resolution):
## means must agree; the field must be far quieter.
func _check_scatter_field(tracer: GemTracer) -> bool:
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var lights := GemRigCompiler.pack(rig)
	var bg := GemRigCompiler.environment(rig)
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres")
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["scatter"] = {"sigma_per_mm": 0.25, "g": 0.55}
	inst["inclusions"] = PackedFloat32Array()
	var base := {
		"max_bounces": 24, "dispersion": false, "birefringence": false,
		"volume": true, "fluorescence": false, "rad_clamp": 100000.0,
		"env_filter_rad": 0.25, "field_grid": 32, "field_dirs": 2048,
	}
	var q := Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0))
	var stochastic := base.duplicate()
	stochastic["field_exits"] = 0
	var field := base.duplicate()
	field["field_exits"] = base["max_bounces"]

	var ref_a := _render_field(tracer, inst, lights, bg, stochastic, q, 1, 2048)
	var ref_b := _render_field(tracer, inst, lights, bg, stochastic, q, 7, 2048)
	var sto_128a := _render_field(tracer, inst, lights, bg, stochastic, q, 1, 128)
	var sto_128b := _render_field(tracer, inst, lights, bg, stochastic, q, 7, 128)
	var t0 := Time.get_ticks_usec()
	var fld_a := _render_field(tracer, inst, lights, bg, field, q, 1, 128)
	var info := tracer.field_info()
	print("    field render: %.2f s for 128 spp @96px (field build %.1f ms, grid %d, %.1f MB)" % [
		(Time.get_ticks_usec() - t0) * 1e-6, info["build_ms"], info["grid"], info["bytes"] / 1048576.0])
	var fld_b := _render_field(tracer, inst, lights, bg, field, q, 7, 128)

	var mean_ref := 0.5 * (_field_mean(ref_a) + _field_mean(ref_b))
	var mean_fld := 0.5 * (_field_mean(fld_a) + _field_mean(fld_b))
	var noise_sto := _field_noise(sto_128a, sto_128b) / maxf(mean_ref, 1e-6)
	var noise_fld := _field_noise(fld_a, fld_b) / maxf(mean_fld, 1e-6)
	var ratio := mean_fld / maxf(mean_ref, 1e-6)
	var ok := ratio > 0.88 and ratio < 1.12 and noise_fld < noise_sto * 0.35
	print("  scatter_field: mean field/stochastic=%.3f  noise@128spp stochastic %.1f%% -> field %.1f%%  %s" % [
		ratio, 100.0 * noise_sto, 100.0 * noise_fld, "PASS" if ok else "FAIL"])
	return ok


func _render_field(tracer: GemTracer, inst: Dictionary, lights: PackedFloat32Array, env: Dictionary,
		policy: Dictionary, q: Quaternion, seed: int, spp: int, batch := 32) -> PackedFloat32Array:
	tracer.set_environment(env)
	tracer.configure_stone(inst, lights, policy)
	tracer.set_seed(seed)
	tracer.set_clip_sample(q, 0.0, Vector4.ONE, 1.3)
	var left := spp
	while left > 0:
		var n := mini(batch, left)
		tracer.accumulate(n)
		left -= n
	return tracer.read_xyz()


func _field_mean(xyz: PackedFloat32Array) -> float:
	var acc := 0.0
	var n := 0
	for i in xyz.size() / 4:
		if xyz[i * 4 + 3] < 0.5:
			continue
		acc += xyz[i * 4 + 1]
		n += 1
	return acc / float(maxi(n, 1))


func _field_noise(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var acc := 0.0
	var n := 0
	for i in a.size() / 4:
		if a[i * 4 + 3] < 0.5 or b[i * 4 + 3] < 0.5:
			continue
		var d := a[i * 4 + 1] - b[i * 4 + 1]
		acc += d * d
		n += 1
	return sqrt(acc / float(maxi(n, 1)) / 2.0)
