extends SceneTree
## SPP ladder with two-seed RMSE noise metric. Windowed only:
##   godot --path . --script res://tools/noise_spp_check.gd
## Writes artifacts/lookdev/noise/: spp_ladder.png, ruby_ablation.png, metrics.json
##
## Noise = RMSE(seed_a, seed_b) / sqrt(2) at equal spp over covered pixels.
## Target at CLIP_BAKE spp: < 0.5/255 ≈ 0.002 for every species.

const SheetComposer := preload("res://core/lapidary/eval/sheet_composer.gd")

const OUT_DIR := "res://artifacts/lookdev/noise"
const STONES := ["quartz", "ruby", "sapphire", "diamond"]
const SPP := [8, 32, 64, 96, 160, 512]
const EXPOSURE := 1.6
const ORTHO := 1.3
const SEED_A_OFFSET := 0
const SEED_B_OFFSET := 91711
const NOISE_TARGET := 0.5 / 255.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	if rig == null:
		print("NOISE_SPP FAILED: gameplay rig missing")
		quit(1)
		return
	var lights := GemRigCompiler.compile(rig)

	var policy: Dictionary = GemRung.policy(GemRung.CLIP_BAKE)
	var res: int = policy["res"]
	var out: int = policy["out"]
	var bake_spp: int = policy["spp"]

	var tracer := GemTracer.create(res, res)
	if tracer == null:
		print("NOISE_SPP FAILED: no RenderingDevice")
		quit(1)
		return

	var metrics := {
		"adapter": RenderingServer.get_video_adapter_name(),
		"res": res, "out": out, "bake_spp": bake_spp,
		"noise_target": NOISE_TARGET, "metric": "two_seed_rmse/sqrt(2)",
		"stones": {},
	}
	var ladder_tiles: Array = []
	var failures := 0
	for tile_id in STONES:
		var stone: GemStone = load("res://data/lapidary/stones/%s.tres" % tile_id)
		var instance := LapidaryStoneCompiler.compile(stone)
		metrics["stones"][tile_id] = _stone_stats(instance, stone)
		print("== %s ==" % tile_id)
		print("  %s" % JSON.stringify(metrics["stones"][tile_id], "", false))
		for spp in SPP:
			var img_a := _render(tracer, instance, stone.seed + SEED_A_OFFSET, lights, policy, spp)
			var img_b := _render(tracer, instance, stone.seed + SEED_B_OFFSET, lights, policy, spp)
			var noise := _two_seed_noise(img_a, img_b)
			metrics["stones"][tile_id]["spp_%d" % spp] = {
				"ms": img_a.get_meta("ms") + img_b.get_meta("ms"),
				"noise": noise,
				"mean_luma": _mean_luma(img_a),
				"pass": noise < NOISE_TARGET if spp >= bake_spp else null,
			}
			print("  spp %4d  %7.1f ms  noise %.5f  luma %.3f%s" % [
				spp, img_a.get_meta("ms") + img_b.get_meta("ms"), noise, _mean_luma(img_a),
				"  PASS" if spp >= bake_spp and noise < NOISE_TARGET \
					else ("  FAIL" if spp >= bake_spp else "")])
			if spp >= bake_spp and noise >= NOISE_TARGET:
				failures += 1
			ladder_tiles.append({"image": img_a, "label": "%s %d" % [tile_id, spp]})

	var ladder: Image = SheetComposer.compose(ladder_tiles, SPP.size(), true,
		"SPP LADDER - CLIP-BAKE %d→%d - TWO-SEED NOISE" % [res, out], STONES, _spp_labels())
	_save(ladder, "spp_ladder.png")

	print("== ruby ablation @ bake spp ==")
	var ruby_tiles: Array = []
	var ruby_metrics := {}
	for variant: Dictionary in _ruby_variants():
		var inst: Dictionary = variant["instance"]
		var img := _render(tracer, inst, int(inst["seed"]), lights, policy, bake_spp)
		var rec := {
			"ms": img.get_meta("ms"),
			"mean_luma": _mean_luma(img),
			"mean_rgb": _mean_rgb(img),
		}
		ruby_metrics[variant["name"]] = rec
		print("  %-16s luma %.3f  rgb %s  %.1f ms" % [
			variant["name"], rec["mean_luma"], str(rec["mean_rgb"]), rec["ms"]])
		ruby_tiles.append({"image": img, "label": variant["name"]})
	metrics["ruby_ablation"] = ruby_metrics
	var ablation: Image = SheetComposer.compose(ruby_tiles, 4, true,
		"RUBY ABLATION - %d SPP - %d→%d - PRINT" % [bake_spp, res, out], [], [])
	_save(ablation, "ruby_ablation.png")

	tracer.release()
	var json := JSON.stringify(metrics, "\t")
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/metrics.json"), FileAccess.WRITE)
	f.store_string(json)
	f.close()
	print("NOISE_SPP COMPLETE -> %s  failures=%d" % [OUT_DIR, failures])
	quit(1 if failures > 0 else 0)


func _ruby_variants() -> Array:
	var stone: GemStone = load("res://data/lapidary/stones/ruby.tres")
	var out: Array = []
	out.append({"name": "default", "instance": LapidaryStoneCompiler.compile(stone)})

	var no_scat := LapidaryStoneCompiler.compile(stone)
	no_scat["scatter"] = {"sigma_per_mm": 0.0, "g": 0.6}
	out.append({"name": "no-scatter", "instance": no_scat})

	var thin := LapidaryStoneCompiler.compile(stone)
	thin["absorb_scale"] = 0.35
	thin["fluorescence"] = {"nm": 693.0, "strength": 0.0}
	out.append({"name": "thin-body", "instance": thin})

	var round_stone: GemStone = stone.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	round_stone.shape.outline = &"round"
	out.append({"name": "round-cut", "instance": LapidaryStoneCompiler.compile(round_stone)})

	var t8_stone: GemStone = stone.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	t8_stone.grade = load("res://data/lapidary/grades/t8.tres")
	out.append({"name": "t8-grade", "instance": LapidaryStoneCompiler.compile(t8_stone)})
	return out


func _render(tracer: GemTracer, instance: Dictionary, seed: int, lights: GemLighting,
		policy: Dictionary, spp: int) -> Image:
	tracer.configure_stone(instance, lights, policy)
	tracer.set_seed(seed)
	tracer.set_clip_sample(Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0)), 0.0, Vector4.ONE, ORTHO)
	var ms := 0.0
	var left := spp
	var chunk: int = policy["batch"]
	while left > 0:
		var n := mini(chunk, left)
		ms += tracer.accumulate(n)
		left -= n
	var out: int = policy["out"]
	var img := tracer.finalize_print(GemPrint.load_house(), false, EXPOSURE, Vector2i(out, out))
	img.set_meta("ms", ms)
	return img


func _stone_stats(instance: Dictionary, stone: GemStone) -> Dictionary:
	var absb: PackedFloat32Array = instance["absorption"]
	return {
		"planes": instance["planes"].size() / 8,
		"defects": maxi(instance.get("surfaces", []).size() - 1, 0),
		"sigma_per_mm": instance["scatter"]["sigma_per_mm"],
		"fluor": instance["fluorescence"]["strength"],
		"size_mm": stone.size_mm,
		"alpha_480": _alpha_at(absb, 480.0),
		"alpha_556": _alpha_at(absb, 556.0),
		"alpha_650": _alpha_at(absb, 650.0),
		"T_2size_650": exp(-_alpha_at(absb, 650.0) * 2.0 * stone.size_mm),
		"T_2size_556": exp(-_alpha_at(absb, 556.0) * 2.0 * stone.size_mm),
	}


func _alpha_at(curve: PackedFloat32Array, nm: float) -> float:
	if curve.is_empty():
		return 0.0
	var t := clampf((nm - 380.0) / 5.0, 0.0, 80.0)
	var i := int(t)
	var f := t - float(i)
	var a := curve[i]
	var b := curve[mini(i + 1, curve.size() - 1)]
	return lerpf(a, b, f)


## Unbiased MC noise estimate: RMSE between two independent seeds / sqrt(2).
func _two_seed_noise(a: Image, b: Image) -> float:
	return _rmse(a, b) / sqrt(2.0)


func _mean_luma(img: Image) -> float:
	var acc := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.12:
				continue
			acc += _luma(c)
			n += 1
	return acc / float(maxi(n, 1))


func _mean_rgb(img: Image) -> Array:
	var acc := Vector3.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.12:
				continue
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return [0.0, 0.0, 0.0]
	acc /= float(n)
	return [snappedf(acc.x, 0.001), snappedf(acc.y, 0.001), snappedf(acc.z, 0.001)]


func _rmse(a: Image, b: Image) -> float:
	var acc := 0.0
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a < 0.12 and cb.a < 0.12:
				continue
			var d := _luma(ca) - _luma(cb)
			acc += d * d
			n += 1
	return sqrt(acc / float(maxi(n, 1)))


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _spp_labels() -> Array:
	var out: Array = []
	for s in SPP:
		out.append("SPP %d" % s)
	return out


func _save(img: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
	img.save_png(path)
	print("  wrote %s" % path)
