extends SceneTree
## Lighting A/B: a row of authored stones per rig, house-printed, stacked into
## one sheet. The first-class environment A/B tool: lighting changes are rig
## edits judged here, never print or exposure tweaks.
## Run:  godot --path . --script res://tools/rig_ab_check.gd [--rigs=a.tres,b.tres]
##       [--stones=quartz,ruby,...] [--spp=64] [--res=192]
## Rig paths are relative to data/lapidary/rigs/ and stone ids to
## data/lapidary/stones/ unless they contain a "/" (ad-hoc variants for A/B).

const OUT_DIR := "res://artifacts/lookdev/rig_ab"
const RIG_DIR := "res://data/lapidary/rigs/"
const DEFAULT_RIGS := ["gameplay_studio.tres", "reference_daylight.tres"]
const DEFAULT_STONES := ["quartz", "amethyst", "sapphire", "emerald", "ruby", "diamond"]
const TILT := Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0))


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var args := OS.get_cmdline_user_args()
	var rig_paths: Array = DEFAULT_RIGS
	var stone_ids: Array = DEFAULT_STONES
	var spp := 64
	var res := 192
	for a: String in args:
		if a.begins_with("--rigs="):
			rig_paths = a.trim_prefix("--rigs=").split(",")
		elif a.begins_with("--stones="):
			stone_ids = a.trim_prefix("--stones=").split(",")
		elif a.begins_with("--spp="):
			spp = int(a.trim_prefix("--spp="))
		elif a.begins_with("--res="):
			res = int(a.trim_prefix("--res="))

	var failures := 0
	var rows: Array[Image] = []
	for rp: String in rig_paths:
		var path := rp if rp.contains("/") else RIG_DIR + rp
		var rig := load(path) as GemLightRig
		if rig == null:
			print("  rig %s FAILED TO LOAD" % path)
			failures += 1
			continue
		var lights := GemRigCompiler.compile(rig)

		var row := Image.create(res * stone_ids.size(), res, false, Image.FORMAT_RGBA8)
		row.fill(Color(0.06, 0.06, 0.07, 1.0))
		var col := 0
		for sid: String in stone_ids:
			var stone := load(sid if sid.contains("/") else "res://data/lapidary/stones/%s.tres" % sid) as GemStone
			if stone == null or stone.material.species == null:
				print("  stone %s FAILED TO LOAD" % sid)
				failures += 1
				col += 1
				continue
			var instance := LapidaryStoneCompiler.compile(stone)
			var tracer := GemTracer.create(res, res)
			if tracer == null:
				failures += 1
				break
			var policy := GemRung.policy(GemRung.PREVIEW)
			tracer.configure_stone(instance, lights, policy)
			tracer.set_seed(stone.seed)
			tracer.set_clip_sample(TILT, 0.0, Vector4.ONE, 1.3)
			var t0 := Time.get_ticks_usec()
			var remaining := spp
			while remaining > 0:
				var n := mini(16, remaining)
				tracer.accumulate(n)
				remaining -= n
			var img := tracer.finalize_print(GemPrint.load_house(), false, 1.0)
			row.blend_rect(img, Rect2i(0, 0, res, res), Vector2i(col * res, 0))
			var st := _print_stats(img)
			print("  %-22s %-12s %6.0f ms   mean %.2f  p10 %.2f  p90 %.2f  clipped %4.1f%%  dark %4.1f%%" % [
				rig.rig_id, sid, float(Time.get_ticks_usec() - t0) / 1000.0,
				st["mean"], st["p10"], st["p90"], st["clipped"] * 100.0, st["dark"] * 100.0])
			tracer.release()
			col += 1
		var name := String(rig.rig_id)
		row.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name]))
		rows.append(row)

	if rows.size() > 0:
		var sheet := Image.create(rows[0].get_width(), res * rows.size(), false, Image.FORMAT_RGBA8)
		for i in rows.size():
			sheet.blit_rect(rows[i], Rect2i(0, 0, rows[i].get_width(), res), Vector2i(0, i * res))
		sheet.save_png(ProjectSettings.globalize_path("%s/ab.png" % OUT_DIR))
	print("RIG_AB %s" % ("FAILED" if failures > 0 else "COMPLETE"))
	quit(1 if failures > 0 else 0)


## Contrast discipline numbers over covered pixels (sRGB-encoded luma):
## mean, 10th/90th percentile, fraction with a clipped channel, fraction
## darker than 0.08.
static func _print_stats(img: Image) -> Dictionary:
	var lum := PackedFloat32Array()
	var clipped := 0
	var dark := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lum.append(l)
			if c.r >= 0.996 or c.g >= 0.996 or c.b >= 0.996:
				clipped += 1
			if l < 0.08:
				dark += 1
	if lum.is_empty():
		return {"mean": 0.0, "p10": 0.0, "p90": 0.0, "clipped": 0.0, "dark": 0.0}
	lum.sort()
	var sum := 0.0
	for v in lum:
		sum += v
	var n := lum.size()
	return {
		"mean": sum / n, "p10": lum[int(n * 0.1)], "p90": lum[int(n * 0.9)],
		"clipped": float(clipped) / n, "dark": float(dark) / n,
	}
