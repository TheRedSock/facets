extends SceneTree
## Face-up light-return function R(theta) per cut: mean stone luminance (Y)
## when ONE 15-deg light of unit radiance sits at angle theta from the viewing
## axis (averaged over six azimuths), clean instance (no milk, no inclusions),
## rest pose. Says where a rig's light must come from to light the BODY; rig
## design starts here (see data/lapidary/rigs/gameplay_studio.tres header).
## Run:  godot --path . --script res://tools/return_sweep.gd

const RES := 128
const SPP := 32
const ORTHO := 1.3


func _initialize() -> void:
	var tracer := GemTracer.create(RES, RES)
	var rest := Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0))
	var policy: Dictionary = GemRung.policy(GemRung.PREVIEW).duplicate()
	policy["dispersion"] = false
	policy["birefringence"] = false

	var thetas := [0, 10, 20, 30, 40, 50, 60, 70, 80, 100, 120, 150]
	var phis := [15.0, 75.0, 135.0, 195.0, 255.0, 315.0]
	for sid: String in ["quartz", "amethyst", "emerald", "ruby", "diamond"]:
		var stone: GemStone = load("res://data/lapidary/stones/%s.tres" % sid)
		var inst := LapidaryStoneCompiler.compile(stone)
		inst["scatter"] = {"sigma_per_mm": 0.0, "g": 0.55}
		var line := "%-10s" % sid
		for th: int in thetas:
			var acc := 0.0
			for ph: float in phis:
				var t := deg_to_rad(float(th))
				var p := deg_to_rad(ph)
				var d := Vector3(sin(t) * cos(p), sin(t) * sin(p), cos(t))
				var lights := PackedFloat32Array([d.x, d.y, d.z, cos(deg_to_rad(15.0)),
					5600.0, 1.0, cos(deg_to_rad(9.0)), 0.0])
				tracer.configure_stone(inst, GemLighting.analytic(lights), policy)
				tracer.set_seed(3)
				tracer.set_clip_sample(rest, 0.0, Vector4.ONE, ORTHO)
				tracer.reset_accumulation()
				tracer.accumulate(SPP)
				acc += _mean_y(tracer.read_xyz())
			line += " %3d:%.3f" % [th, acc / phis.size()]
		print(line)
	tracer.release()
	quit(0)


static func _mean_y(xyz: PackedFloat32Array) -> float:
	var sum := 0.0
	var n := 0
	@warning_ignore("integer_division")
	for i in xyz.size() / 4:
		if xyz[i * 4 + 3] > 0.5:
			sum += xyz[i * 4 + 1]
			n += 1
	return sum / maxf(1.0, float(n))
