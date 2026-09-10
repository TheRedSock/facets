extends SceneTree
## 360° turntable GIF per authored stone. Windowed only (RenderingDevice):
##   godot --path . --script res://tools/turn_gifs.gd
##   godot --path . --script res://tools/turn_gifs.gd -- --stones ruby,quartz --spp 192
##
## Options (after `--`):
##   --stones a,b,c   subset of data/lapidary/stones (default: all 16)
##   --spp N          samples per frame (default 192)
##   --frames N       frames per revolution (default 60, seamless loop)
##   --fps N          playback fps (default 30)
##   --res N          render size in px (default 512)
##   --keep-frames    keep the PNG frame directory after encoding
##
## Renders each frame with the HERO rung policy at the requested resolution
## through the house print, writes PNGs to artifacts/lookdev/turn_gif/<stone>/,
## then encodes <stone>.gif with tools/turn_gifs_encode.py (Pillow).
## Per-frame cost = scatter-field build (orientation-dependent) + trace.

const OUT_DIR := "res://artifacts/lookdev/turn_gif"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const ENCODER := "res://tools/turn_gifs_encode.py"
const STONES_DIR := "res://data/lapidary/stones/"
const LADDER := [
	"quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond",
	"fluorite", "smoky_quartz", "tourmaline", "rhodolite", "aquamarine", "alexandrite",
	"painite", "blue_garnet",
]
const REST_TILT_DEG := Vector3(-12, 0, 0)
const ORTHO := 1.3
const EXPOSURE := 1.0  # the rig lights the stone; the house print is the only exposure knob


func _initialize() -> void:
	var opts := _parse_args(OS.get_cmdline_user_args())
	var stones: Array = opts["stones"]
	var spp: int = opts["spp"]
	var frames: int = opts["frames"]
	var fps: int = opts["fps"]
	var res: int = opts["res"]

	print("\n=== turn_gifs  %dpx  %d frames @ %d fps  %d spp  stones=%s ===" % [
		res, frames, fps, spp, ",".join(PackedStringArray(stones))])

	var rig: GemLightRig = load(RIG_PATH)
	if rig == null:
		print("TURN_GIFS FAILED: rig missing at %s" % RIG_PATH)
		quit(1)
		return
	var lights := GemRigCompiler.pack(rig)
	var bg := GemRigCompiler.environment(rig)
	var print_res := GemPrint.load_house()

	var policy: Dictionary = GemRung.policy(GemRung.HERO)
	policy["res"] = res
	policy["out"] = res
	policy["spp"] = spp
	var batch: int = policy["batch"]

	var tracer := GemTracer.create(res, res)
	if tracer == null:
		print("TURN_GIFS FAILED: no RenderingDevice (run windowed, not --headless)")
		quit(1)
		return
	tracer.set_environment(bg)

	var rest := Quaternion.from_euler(Vector3(
		deg_to_rad(REST_TILT_DEG.x), deg_to_rad(REST_TILT_DEG.y), deg_to_rad(REST_TILT_DEG.z)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var encoder_abs := ProjectSettings.globalize_path(ENCODER)

	var failures := 0
	var total_t0 := Time.get_ticks_msec()
	for tile_id: String in stones:
		var stone: GemStone = load(STONES_DIR + tile_id + ".tres")
		if stone == null:
			print("  MISSING stone %s" % tile_id)
			failures += 1
			continue
		var instance := LapidaryStoneCompiler.compile(stone)
		tracer.set_seed(int(instance["seed"]))
		tracer.configure_stone(instance, lights, policy)

		var frame_dir := OUT_DIR + "/" + tile_id
		var frame_dir_abs := ProjectSettings.globalize_path(frame_dir)
		DirAccess.make_dir_recursive_absolute(frame_dir_abs)

		var t0 := Time.get_ticks_msec()
		var accumulate_wall_ms := 0.0
		for i in frames:
			# Linear 360° so frame N wraps seamlessly to frame 0.
			var angle := TAU * float(i) / float(frames)
			var q := rest * Quaternion(Vector3.UP, angle)
			if i > 0:
				tracer.reset_accumulation()
			tracer.set_clip_sample(q, 0.0, Vector4.ONE, ORTHO)
			# The tracer chunks dispatches adaptively (TDR-safe) and rebuilds the
			# scatter field for the new orientation on the first accumulate.
			var remaining := spp
			while remaining > 0:
				var n := mini(batch, remaining)
				accumulate_wall_ms += tracer.accumulate(n)
				remaining -= n
			var img := tracer.finalize_print(print_res, false, EXPOSURE)
			img.save_png("%s/frame_%03d.png" % [frame_dir_abs, i])

		var gif_abs := ProjectSettings.globalize_path("%s/%s.gif" % [OUT_DIR, tile_id])
		var enc_out: Array = []
		var code := OS.execute("python", [encoder_abs, frame_dir_abs, gif_abs, str(fps)], enc_out, true)
		if code != 0:
			printerr("  FAIL encode %s (exit %d):\n%s" % [tile_id, code, "\n".join(PackedStringArray(enc_out))])
			failures += 1
		else:
			if not opts["keep_frames"]:
				_remove_dir(frame_dir_abs)
			print("  %-14s %3d frames  gpu %6.1fs  wall %6.1fs  sigma %.3f  defects %2d -> %s.gif" % [
				tile_id, frames, accumulate_wall_ms / 1000.0,
				float(Time.get_ticks_msec() - t0) / 1000.0,
				instance["scatter"]["sigma_per_mm"], maxi(instance.get("surfaces", []).size() - 1, 0), tile_id])

	tracer.release()
	print("TURN_GIFS %s  %d stones  %.1f min -> %s" % [
		"COMPLETE" if failures == 0 else "FAILED (%d)" % failures,
		stones.size(), float(Time.get_ticks_msec() - total_t0) / 60000.0, OUT_DIR])
	quit(1 if failures > 0 else 0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts := {
		"stones": LADDER.duplicate(), "spp": 192, "frames": 60, "fps": 30, "res": 512,
		"keep_frames": false,
	}
	var i := 0
	while i < args.size():
		var a := args[i]
		var has_val := i + 1 < args.size()
		match a:
			"--stones":
				if has_val:
					opts["stones"] = Array(args[i + 1].split(",", false))
					i += 1
			"--spp":
				if has_val:
					opts["spp"] = maxi(1, int(args[i + 1]))
					i += 1
			"--frames":
				if has_val:
					opts["frames"] = maxi(1, int(args[i + 1]))
					i += 1
			"--fps":
				if has_val:
					opts["fps"] = maxi(1, int(args[i + 1]))
					i += 1
			"--res":
				if has_val:
					opts["res"] = clampi(int(args[i + 1]), 64, 2048)
					i += 1
			"--keep-frames":
				opts["keep_frames"] = true
		i += 1
	return opts


func _remove_dir(abs_path: String) -> void:
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(abs_path)
