extends SceneTree
## Kernel v1 feature validation: grade axes, inclusions, wear, volume, zoning,
## dispersion, fluorescence, GPU print pass — through authored stones + house print.
## Run:  godot --path . --script res://tools/kernel_v1_check.gd

const OUT_DIR := "res://artifacts/lookdev/kernel_v1"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const STONES := {
	"quartz_t1": "res://data/lapidary/stones/quartz.tres",
	"ruby_t7": "res://data/lapidary/stones/ruby.tres",
	"diamond_t8": "res://data/lapidary/stones/diamond.tres",
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failures := 0
	var rig := load(RIG_PATH) as GemLightRig
	if rig == null:
		printerr("kernel_v1_check: missing %s" % RIG_PATH)
		quit(1)
		return
	var lights := GemRigCompiler.pack(rig)
	var background := GemRigCompiler.environment(rig)

	failures += _render(STONES["quartz_t1"], lights, background,
		{"max_bounces": 24, "volume": true, "birefringence": false, "dispersion": false},
		"quartz_t1", 256, 96)
	failures += _render(STONES["ruby_t7"], lights, background,
		{"max_bounces": 28, "volume": true, "birefringence": false, "dispersion": false},
		"ruby_t7", 256, 96)
	failures += _render(STONES["diamond_t8"], lights, background,
		{"max_bounces": 32, "volume": false, "birefringence": false, "dispersion": true},
		"diamond_t8", 256, 128)

	print("KERNEL_V1 %s" % ("FAILED (%d)" % failures if failures > 0 else "COMPLETE"))
	quit(1 if failures > 0 else 0)


func _render(stone_path: String, lights: PackedFloat32Array, environment: Dictionary,
		policy: Dictionary, tag: String, res: int, spp: int) -> int:
	var stone := load(stone_path) as GemStone
	if stone == null or stone.material.species == null:
		printerr("  %s: FAILED TO LOAD %s" % [tag, stone_path])
		return 1
	var instance := LapidaryStoneCompiler.compile(stone)
	var tracer := GemTracer.create(res, res)
	if tracer == null:
		print("  %s: NO RD" % tag)
		return 1
	tracer.set_seed(stone.seed)
	tracer.set_environment(environment)
	tracer.configure_stone(instance, lights, policy)
	tracer.set_clip_sample(Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0)), 0.0, Vector4.ONE, 1.3)
	var total_ms := 0.0
	var batches := int(ceil(spp / 16.0))
	for i in batches:
		total_ms += tracer.accumulate(16)
	var print_res := GemPrint.load_house()
	var img_raw := tracer.finalize_print(null, true, 1.0)
	var img_print := tracer.finalize_print(print_res, false, 1.0)
	img_raw.save_png(ProjectSettings.globalize_path("%s/%s_raw.png" % [OUT_DIR, tag]))
	img_print.save_png(ProjectSettings.globalize_path("%s/%s_print.png" % [OUT_DIR, tag]))
	var incl_count: int = instance["inclusions"].size() / 16
	print("  %s: %d spp %.1f ms gpu, %d planes, %d inclusion prims -> %s_{raw,print}.png" % [
		tag, tracer.samples_accumulated, total_ms, instance["planes"].size() / 8, incl_count, tag])
	tracer.release()
	return 0
