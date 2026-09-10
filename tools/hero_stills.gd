extends SceneTree
## One HERO still per authored stone (768px, policy spp, house print).
## Windowed only:
##   godot --path . --script res://tools/hero_stills.gd
## Writes artifacts/lookdev/hero/<stone>.png and hero_sheet.png.

const SheetComposer := preload("res://core/lapidary/eval/sheet_composer.gd")

const OUT_DIR := "res://artifacts/lookdev/hero"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const PRINT_PATH := "res://data/lapidary/print/house_print.tres"
const ORDER := [
	"quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond",
	"fluorite", "smoky_quartz", "tourmaline", "rhodolite", "aquamarine", "alexandrite",
	"painite", "blue_garnet",
]
const ORTHO := 1.3
const EXPOSURE := 1.0  # the rig lights the stone; the house print is the only exposure knob
const TDR_SAFE_DISPATCH_MS := 700.0
const SHEET_CELL := 384


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rig: GemLightRig = load(RIG_PATH)
	if rig == null:
		print("HERO_STILLS FAILED: gameplay rig missing")
		quit(1)
		return
	var print_res := GemPrint.load_house()
	var lights := GemRigCompiler.pack(rig)
	var bg := GemRigCompiler.environment(rig)
	var face_up := Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0))
	var policy_res: Dictionary = GemRung.policy(GemRung.HERO)
	var res: int = policy_res["res"]
	var tracer := GemTracer.create(res, res)
	if tracer == null:
		print("HERO_STILLS FAILED: no RenderingDevice (run windowed)")
		quit(1)
		return

	var tiles: Array = []
	var t0 := Time.get_ticks_msec()
	for tile_id in ORDER:
		var stone: GemStone = load("res://data/lapidary/stones/%s.tres" % tile_id)
		if stone == null:
			print("  MISSING %s" % tile_id)
			quit(1)
			return
		var instance := LapidaryStoneCompiler.compile(stone)
		var policy: Dictionary = GemRung.policy(GemRung.HERO)
		var spp: int = policy["spp"]
		var batch: int = policy["batch"]
		tracer.set_seed(int(instance["seed"]))
		tracer.set_environment(bg)
		tracer.configure_stone(instance, lights, policy)
		tracer.set_clip_sample(face_up, 0.0, Vector4.ONE, ORTHO)
		var ms := tracer.accumulate(1)
		var chunk := clampi(int(TDR_SAFE_DISPATCH_MS / maxf(ms, 0.05)), 1, batch)
		var remaining := spp - 1
		while remaining > 0:
			var n := mini(chunk, remaining)
			ms += tracer.accumulate(n)
			remaining -= n
		var img := tracer.finalize_print(print_res, false, EXPOSURE)
		var path := OUT_DIR + "/%s.png" % tile_id
		img.save_png(ProjectSettings.globalize_path(path))
		var sheet_tile := img.duplicate()
		if sheet_tile.get_width() != SHEET_CELL:
			sheet_tile.resize(SHEET_CELL, SHEET_CELL, Image.INTERPOLATE_LANCZOS)
		tiles.append({"image": sheet_tile, "label": tile_id.replace("_", " ").to_upper()})
		print("  %-14s %4dpx %4d spp  %7.1f ms  sigma %.3f  incl %d" % [
			tile_id, res, spp, ms, instance["scatter"]["sigma_per_mm"],
			instance["inclusions"].size() / 16])

	tracer.release()
	var sheet: Image = SheetComposer.compose(tiles, 8, true,
		"HERO STILLS - %d PX - POLICY SPP - HOUSE PRINT - LOOK V%d" % [res, GemCache.LOOK_VERSION],
		[], [])
	sheet.save_png(ProjectSettings.globalize_path(OUT_DIR + "/hero_sheet.png"))
	print("  wrote %s/hero_sheet.png + %d stills in %.1f s" % [
		OUT_DIR, ORDER.size(), float(Time.get_ticks_msec() - t0) / 1000.0])
	print("HERO_STILLS COMPLETE")
	quit(0)
