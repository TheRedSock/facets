extends SceneTree
## Numerical results for comparison against the optional independent renderer.
func _initialize() -> void:
	var cases := []
	for eta in [0.414, 0.6666666666666666, 0.99, 1.0, 1.01, 1.5, 2.417]:
		for index in 37:
			var cosine := 0.005 + 0.995 * index / 36.0
			for transmission in [false, true]:
				cases.append({"kind": "dielectric", "eta": eta, "cosine": cosine, "transmission": transmission,
					"matrix": Array(GemPolarization.dielectric(cosine, eta, transmission))})
	for index in 48:
		var angle := index * 0.17 - 3.0
		var phase := index * 0.31 - 7.0
		var tx := 0.05 + index / 51.0
		var ty := 1.0 - index / 51.0
		cases.append({"kind": "rotation", "angle": angle, "matrix": Array(GemPolarization.rotation(angle))})
		cases.append({"kind": "retarder", "phase": phase, "matrix": Array(GemPolarization.retarder(phase))})
		cases.append({"kind": "diattenuator", "tx": tx, "ty": ty, "matrix": Array(GemPolarization.diattenuator(tx, ty))})
		var forward := Vector3(sin(index * 0.4), cos(index * 0.7), 0.5).normalized()
		var axis := forward.cross(Vector3.UP).normalized()
		var target := Quaternion(forward, angle) * axis
		cases.append({"kind": "basis", "forward": [forward.x, forward.y, forward.z], "current": [axis.x, axis.y, axis.z],
			"target": [target.x, target.y, target.z], "matrix": Array(GemPolarization.basis_rotation(forward, axis, target))})
		var outgoing := Quaternion(Vector3.UP, 0.7) * forward
		var out_axis := outgoing.cross(Vector3.UP).normalized()
		var out_target := Quaternion(outgoing, phase) * out_axis
		var element := GemPolarization.multiply(GemPolarization.diattenuator(tx, ty), GemPolarization.retarder(phase))
		cases.append({"kind": "change_basis", "tx": tx, "ty": ty, "phase": phase,
			"forward": [forward.x, forward.y, forward.z], "current": [axis.x, axis.y, axis.z], "target": [target.x, target.y, target.z],
			"outgoing": [outgoing.x, outgoing.y, outgoing.z], "out_current": [out_axis.x, out_axis.y, out_axis.z], "out_target": [out_target.x, out_target.y, out_target.z],
			"matrix": Array(GemPolarization.change_basis(element, forward, axis, target, outgoing, out_axis, out_target))})
	var path := "res://artifacts/reference/polarization-cases.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify({"cases": cases}, "\t"))
	print("Exported %d polarization cases" % cases.size())
	quit()
