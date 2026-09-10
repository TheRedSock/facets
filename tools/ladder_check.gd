extends SceneTree
## Both merge ladders (main row over alternate row) rendered from AUTHORED
## data (species/chromophore/grade/stone .tres) in one batched dispatch.
## Run:  godot --path . --script res://tools/ladder_check.gd

const OUT_DIR := "res://artifacts/lookdev/ladder"
const ORDER := [
	"quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond",
	"fluorite", "smoky_quartz", "tourmaline", "rhodolite", "aquamarine", "alexandrite", "painite", "blue_garnet",
]
const CELL := 224


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var lights := GemRigCompiler.pack(rig)

	var instances: Array = []
	for tile_id in ORDER:
		var path := "res://data/lapidary/stones/%s.tres" % tile_id
		var stone: GemStone = load(path)
		if stone == null:
			print("  MISSING %s" % path)
			quit(1)
			return
		instances.append(LapidaryStoneCompiler.compile(stone))
		var fluor: Dictionary = instances[-1]["fluorescence"]
		print("  %s: %d planes, %d defect boundaries, sigma %.2f, fluor %.2f@%.0fnm, disp_strong %s" % [
			tile_id, instances[-1]["planes"].size() / 8, maxi(instances[-1].get("surfaces", []).size() - 1, 0),
			instances[-1]["scatter"]["sigma_per_mm"], fluor["strength"], fluor["nm"],
			str(instances[-1]["dispersion_strong"])])

	var tracer := GemTracer.create(CELL * 8, CELL * 2)
	if tracer == null:
		quit(1)
		return
	tracer.set_environment(GemRigCompiler.environment(rig))
	tracer.configure_stones(instances, lights,
		{"max_bounces": 28, "volume": true, "dispersion": true, "birefringence": true, "rad_clamp": 24.0},
		Vector2i(8, 2))
	var states: Array = []
	for i in ORDER.size():
		states.append({
			"quat": Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0)),
			"stone_index": i,
			"ortho_half": 1.3,
		})
	tracer.set_instances(states)
	var ms := 0.0
	for b in 8:
		ms += tracer.accumulate(16)
	var img_print := tracer.finalize_print(GemPrint.load_house(), false, 1.0)
	var img_raw := tracer.finalize_print(null, true, 1.0)
	img_print.save_png(ProjectSettings.globalize_path(OUT_DIR + "/ladder_print.png"))
	img_raw.save_png(ProjectSettings.globalize_path(OUT_DIR + "/ladder_raw.png"))
	print("  ladder %d gems @%dpx 128spp: %.0f ms -> ladder_{print,raw}.png" % [ORDER.size(), CELL, ms])
	tracer.release()
	print("LADDER COMPLETE")
	quit(0)
