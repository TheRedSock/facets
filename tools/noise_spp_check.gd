extends SceneTree
## SPP ladder + ruby ablation. Windowed only:
##   godot --path . --script res://tools/noise_spp_check.gd
## Writes artifacts/lookdev/noise/: spp_ladder.png, ruby_ablation.png, metrics.json

const SheetComposer := preload("res://core/lapidary/eval/sheet_composer.gd")

const OUT_DIR := "res://artifacts/lookdev/noise"
const STONES := ["quartz", "ruby", "sapphire", "diamond"]
const SPP := [8, 32, 64, 160, 512, 2048]
const CELL := 224
const CHUNK := 32
const EXPOSURE := 1.6
const ORTHO := 1.3


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	if rig == null:
		print("NOISE_SPP FAILED: gameplay rig missing")
		quit(1)
		return
	var lights := GemRigCompiler.pack(rig)
	var bg := GemRigCompiler.background(rig)
	var policy: Dictionary = GemRung.policy(GemRung.CLIP_BAKE)
	policy["res"] = CELL
	policy["out"] = CELL

	var tracer := GemTracer.create(CELL, CELL)
	if tracer == null:
		print("NOISE_SPP FAILED: no RenderingDevice")
		quit(1)
		return
	tracer.set_background(bg)

	var metrics := {"adapter": RenderingServer.get_video_adapter_name(), "cell_px": CELL, "stones": {}}
	var ladder_tiles: Array = []
	for tile_id in STONES:
		var stone: GemStone = load("res://data/lapidary/stones/%s.tres" % tile_id)
		var instance := LapidaryStoneCompiler.compile(stone)
		metrics["stones"][tile_id] = _stone_stats(instance, stone)
		print("== %s ==" % tile_id)
		print("  %s" % JSON.stringify(metrics["stones"][tile_id], "", false))
		var prev: Image = null
		for spp in SPP:
			var img := _render(tracer, instance, stone.seed, lights, policy, spp)
			var grain := _grain(img)
			var delta := _rmse(img, prev) if prev != null else -1.0
			metrics["stones"][tile_id]["spp_%d" % spp] = {
				"ms": img.get_meta("ms"),
				"grain": grain,
				"mean_luma": _mean_luma(img),
				"delta_vs_prev": delta,
			}
			print("  spp %4d  %7.1f ms  grain %.4f  luma %.3f  dPrev %.4f" % [
				spp, img.get_meta("ms"), grain, _mean_luma(img), delta])
			ladder_tiles.append({"image": img, "label": "%s %d" % [tile_id, spp]})
			prev = img

	var ladder: Image = SheetComposer.compose(ladder_tiles, SPP.size(), true,
		"SPP LADDER - CLIP-BAKE POLICY - 224PX - PRINT", STONES, _spp_labels())
	_save(ladder, "spp_ladder.png")

	print("== ruby ablation @ 512 spp ==")
	var ruby_tiles: Array = []
	var ruby_metrics := {}
	for variant: Dictionary in _ruby_variants():
		var inst: Dictionary = variant["instance"]
		var img := _render(tracer, inst, int(inst["seed"]), lights, policy, 512)
		var rec := {
			"ms": img.get_meta("ms"),
			"grain": _grain(img),
			"mean_luma": _mean_luma(img),
			"mean_rgb": _mean_rgb(img),
		}
		ruby_metrics[variant["name"]] = rec
		print("  %-16s grain %.4f  luma %.3f  rgb %s  %.1f ms" % [
			variant["name"], rec["grain"], rec["mean_luma"], str(rec["mean_rgb"]), rec["ms"]])
		ruby_tiles.append({"image": img, "label": variant["name"]})
	metrics["ruby_ablation"] = ruby_metrics
	var ablation: Image = SheetComposer.compose(ruby_tiles, 4, true,
		"RUBY ABLATION - 512 SPP - 224PX - PRINT", [], [])
	_save(ablation, "ruby_ablation.png")

	tracer.release()
	var json := JSON.stringify(metrics, "\t")
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/metrics.json"), FileAccess.WRITE)
	f.store_string(json)
	f.close()
	print("NOISE_SPP COMPLETE -> %s" % OUT_DIR)
	quit(0)


func _ruby_variants() -> Array:
	var stone: GemStone = load("res://data/lapidary/stones/ruby.tres")
	var out: Array = []
	out.append({"name": "default", "instance": LapidaryStoneCompiler.compile(stone)})

	var no_fluor := LapidaryStoneCompiler.compile(stone)
	no_fluor["fluorescence"] = {"nm": 693.0, "strength": 0.0}
	out.append({"name": "no-fluor", "instance": no_fluor})

	var no_scat := LapidaryStoneCompiler.compile(stone)
	no_scat["scatter"] = {"sigma_per_mm": 0.0, "g": 0.6}
	out.append({"name": "no-scatter", "instance": no_scat})

	var no_silk := LapidaryStoneCompiler.compile(stone)
	no_silk["inclusions"] = PackedFloat32Array()
	out.append({"name": "no-silk", "instance": no_silk})

	var clean := LapidaryStoneCompiler.compile(stone)
	clean["fluorescence"] = {"nm": 693.0, "strength": 0.0}
	clean["scatter"] = {"sigma_per_mm": 0.0, "g": 0.6}
	clean["inclusions"] = PackedFloat32Array()
	out.append({"name": "clean-optics", "instance": clean})

	var thin := LapidaryStoneCompiler.compile(stone)
	thin["absorb_scale"] = 0.35
	thin["fluorescence"] = {"nm": 693.0, "strength": 0.0}
	out.append({"name": "thin-body", "instance": thin})

	var round_stone: GemStone = stone.duplicate()
	round_stone.silhouette = &"round"
	out.append({"name": "round-cut", "instance": LapidaryStoneCompiler.compile(round_stone)})

	var t8_stone: GemStone = stone.duplicate()
	t8_stone.grade = load("res://data/lapidary/grades/t8.tres")
	out.append({"name": "t8-grade", "instance": LapidaryStoneCompiler.compile(t8_stone)})
	return out


func _render(tracer: GemTracer, instance: Dictionary, seed: int, lights: PackedFloat32Array,
		policy: Dictionary, spp: int) -> Image:
	tracer.configure_stone(instance, lights, policy)
	tracer.set_seed(seed)
	tracer.set_clip_sample(Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0)), 0.0, Vector4.ONE, ORTHO)
	var ms := 0.0
	var left := spp
	while left > 0:
		var n := mini(CHUNK, left)
		ms += tracer.accumulate(n)
		left -= n
	var img := tracer.finalize_print(GemPrint.new(), false, EXPOSURE)
	img.set_meta("ms", ms)
	return img


func _stone_stats(instance: Dictionary, stone: GemStone) -> Dictionary:
	var absb: PackedFloat32Array = instance["absorption"]
	return {
		"planes": instance["planes"].size() / 8,
		"inclusions": instance["inclusions"].size() / 16,
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


func _grain(img: Image) -> float:
	## High-frequency residual RMSE in luma over covered pixels. Proxy for visible grain.
	var w := img.get_width()
	var h := img.get_height()
	var acc := 0.0
	var n := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := img.get_pixel(x, y)
			if c.a < 0.12:
				continue
			var blur := Color(0, 0, 0, 0)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					blur += img.get_pixel(x + dx, y + dy)
			blur /= 9.0
			var d := _luma(c) - _luma(blur)
			acc += d * d
			n += 1
	return sqrt(acc / float(maxi(n, 1)))


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
