extends SceneTree
## Print-space grain per authored stone: two-seed RMSE of the delivered 8-bit
## image at a given rung / resolution / spp. Windowed only (RenderingDevice):
##   godot --path . --script res://tools/grain_check.gd
##   godot --path . --script res://tools/grain_check.gd -- --res 512 --spp 192 --stones ruby,quartz --diff
##
## Options (after `--`):
##   --stones a,b,c   subset of data/lapidary/stones (default: all 16)
##   --rung NAME      interact | preview | board_live | clip_bake | hero (default hero)
##   --res N          render size (default 512; delivered size is the same)
##   --spp N          samples per frame (default 192)
##   --diff           also write frame + x8 amplified two-seed difference PNGs
##
## Metric: sqrt(mean over covered pixels of |a - b|^2 / 3) / sqrt(2), in 8-bit
## units. Grain below ~1 LSB is invisible; the target is < 1.0 at GIF settings.
## Writes artifacts/lookdev/grain/metrics.json (+ PNGs with --diff).

const OUT_DIR := "res://artifacts/lookdev/grain"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const STONES_DIR := "res://data/lapidary/stones/"
const LADDER := [
	"quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond",
	"fluorite", "smoky_quartz", "tourmaline", "rhodolite", "aquamarine", "alexandrite",
	"painite", "blue_garnet",
]
const REST_TILT_DEG := Vector3(-12, 0, 0)
const ORTHO := 1.3
const EXPOSURE := 1.0  # the rig lights the stone; the house print is the only exposure knob
const SEED_B_OFFSET := 91711
const TARGET_LSB := 1.0


func _initialize() -> void:
	var opts := _parse_args(OS.get_cmdline_user_args())
	var rig: GemLightRig = load(RIG_PATH)
	var lights := GemRigCompiler.compile(rig)

	var print_res := GemPrint.load_house()
	var rung: int = opts["rung"]
	var res: int = opts["res"]
	var spp: int = opts["spp"]
	var policy: Dictionary = GemRung.policy(rung)
	policy["res"] = res
	policy["out"] = res
	policy["spp"] = spp

	var tracer := GemTracer.create(res, res)
	if tracer == null:
		print("GRAIN_CHECK FAILED: no RenderingDevice (run windowed)")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rest := Quaternion.from_euler(Vector3(
		deg_to_rad(REST_TILT_DEG.x), deg_to_rad(REST_TILT_DEG.y), deg_to_rad(REST_TILT_DEG.z)))
	print("\n=== grain_check  %s  %dpx  %d spp ===" % [GemRung.rung_name(rung), res, spp])
	print("  %-14s %8s %8s %8s %8s  %s" % ["stone", "grain", "field_ms", "trace_s", "luma", ""])

	var metrics := {"rung": GemRung.rung_name(rung), "res": res, "spp": spp, "stones": {}}
	var failures := 0
	for tile_id: String in opts["stones"]:
		var stone: GemStone = load(STONES_DIR + tile_id + ".tres")
		if stone == null:
			print("  MISSING stone %s" % tile_id)
			failures += 1
			continue
		var instance := LapidaryStoneCompiler.compile(stone)
		var frames: Array[Image] = []
		var trace_ms := 0.0
		var field_ms := 0.0
		for seed_off: int in [0, SEED_B_OFFSET]:
			tracer.configure_stone(instance, lights, policy)
			tracer.set_seed(int(instance["seed"]) + seed_off)
			tracer.set_clip_sample(rest, 0.0, Vector4.ONE, ORTHO)
			var left := spp
			while left > 0:
				var n := mini(int(policy["batch"]), left)
				trace_ms += tracer.accumulate(n)
				left -= n
			field_ms = tracer.last_field_ms
			frames.append(tracer.finalize_print(print_res, false, EXPOSURE))
		var stats := _two_seed_stats(frames[0], frames[1])
		var grain: float = stats["grain_lsb"]
		var ok := grain < TARGET_LSB
		if not ok:
			failures += 1
		@warning_ignore("integer_division")
		var defect_count: int = maxi(instance.get("surfaces", []).size() - 1, 0)
		metrics["stones"][tile_id] = {
			"grain_lsb": grain, "mean_luma": stats["luma"], "field_ms": field_ms,
			"trace_s": trace_ms / 1000.0, "sigma_per_mm": instance["scatter"]["sigma_per_mm"],
			"defects": defect_count, "pass": ok,
		}
		print("  %-14s %8.2f %8.0f %8.1f %8.3f  %s" % [tile_id, grain, field_ms, trace_ms / 1000.0,
			stats["luma"], "PASS" if ok else "FAIL"])
		if opts["diff"]:
			frames[0].save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, tile_id]))
			(stats["diff"] as Image).save_png(ProjectSettings.globalize_path("%s/%s_diff.png" % [OUT_DIR, tile_id]))

	tracer.release()
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/metrics.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(metrics, "\t"))
	f.close()
	print("GRAIN_CHECK %s  failures=%d -> %s" % ["PASS" if failures == 0 else "FAIL", failures, OUT_DIR])
	quit(1 if failures > 0 else 0)


func _two_seed_stats(a: Image, b: Image) -> Dictionary:
	var w := a.get_width()
	var h := a.get_height()
	var diff := Image.create(w, h, false, Image.FORMAT_RGB8)
	var se := 0.0
	var luma := 0.0
	var n := 0
	for y in h:
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a < 0.5 and cb.a < 0.5:
				diff.set_pixel(x, y, Color.BLACK)
				continue
			var d := Vector3(absf(ca.r - cb.r), absf(ca.g - cb.g), absf(ca.b - cb.b))
			se += d.length_squared() / 3.0
			luma += 0.2126 * ca.r + 0.7152 * ca.g + 0.0722 * ca.b
			n += 1
			diff.set_pixel(x, y, Color(minf(d.x * 8.0, 1.0), minf(d.y * 8.0, 1.0), minf(d.z * 8.0, 1.0)))
	var rmse := sqrt(se / maxf(n, 1)) / sqrt(2.0)
	return {"grain_lsb": rmse * 255.0, "luma": luma / maxf(n, 1), "diff": diff}


func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts := {"stones": LADDER.duplicate(), "rung": GemRung.HERO, "res": 512, "spp": 192, "diff": false}
	var names := ["interact", "preview", "board_live", "clip_bake", "hero"]
	var i := 0
	while i < args.size():
		var has_val := i + 1 < args.size()
		match args[i]:
			"--stones":
				if has_val:
					opts["stones"] = Array(args[i + 1].split(",", false))
					i += 1
			"--rung":
				if has_val:
					opts["rung"] = maxi(0, names.find(args[i + 1]))
					i += 1
			"--res":
				if has_val:
					opts["res"] = clampi(int(args[i + 1]), 64, 2048)
					i += 1
			"--spp":
				if has_val:
					opts["spp"] = maxi(1, int(args[i + 1]))
					i += 1
			"--diff":
				opts["diff"] = true
		i += 1
	return opts
