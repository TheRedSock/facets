extends SceneTree
## Throwaway probe: why exactly does step/rectangle plane 101 die?

const CutCompiler := preload("res://core/lapidary/cut/cut_compiler.gd")


func _initialize() -> void:
	var t: Resource = load("res://data/lapidary/cuts/step.tres")
	var r: Dictionary = CutCompiler.compile(t, &"rectangle", 1.76, 1.0, 1234)
	var planes: PackedFloat32Array = r["planes"]
	var anchors: PackedVector3Array = r["anchors"]
	for target in [101, 29]:
		print("--- plane %d ---" % target)
		var n := Vector3(planes[target * 8], planes[target * 8 + 1], planes[target * 8 + 2])
		var d := planes[target * 8 + 3]
		print("n=(%.4f, %.4f, %.4f) d=%.4f anchor=%s" % [n.x, n.y, n.z, d, anchors[target]])
		var t1 := n.cross(Vector3(0, 0, 1))
		if t1.length_squared() < 1.0e-6:
			t1 = n.cross(Vector3(1, 0, 0))
		t1 = t1.normalized()
		var t2 := n.cross(t1).normalized()
		for scale in [0.004, 0.012, 0.03, 0.06]:
			for off in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
					Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]:
				var c: Vector3 = anchors[target] + (t1 * off.x + t2 * off.y) * scale
				var reject := -1
				var worst := 0.0
				for j in planes.size() / 8:
					if j == target:
						continue
					var nj := Vector3(planes[j * 8], planes[j * 8 + 1], planes[j * 8 + 2])
					var viol := nj.dot(c) - planes[j * 8 + 3]
					if viol > -1.0e-6 and viol > worst - 1.0e-12:
						if viol > worst or reject < 0:
							worst = viol
							reject = j
				if reject >= 0:
					print("  scale %.3f off %s -> rejected by %d (zone %d) viol %.6f" % [
						scale, off, reject, int(planes[reject * 8 + 4]), worst])
				else:
					print("  scale %.3f off %s -> INSIDE" % [scale, off])
	quit(0)
