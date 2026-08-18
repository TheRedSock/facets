extends SceneTree
## Lapidary spike: prove Godot -> RD compute -> spectral gem -> Image.
## Run:  godot --path . --script res://tools/spike_trace.gd   (windowed; RD needs a GPU context)
##
## Renders: ideal diamond, windowed diamond (grade sanity), ruby-ish absorber.
## Saves PNGs to artifacts/lookdev/spike/ and prints timing for board-live feasibility.

const OUT_DIR := "res://artifacts/lookdev/spike"
const GemTracerScript := preload("res://core/lapidary/tracer/gem_tracer.gd")

# Peter 1923, verified: n^2 - 1 = 4.3356 L^2/(L^2-0.1060^2) + 0.3306 L^2/(L^2-0.1750^2), L in um.
const DIAMOND_B := Vector3(4.3356, 0.3306, 0.0)
const DIAMOND_C := Vector3(0.1060 * 0.1060, 0.1750 * 0.1750, 0.0)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failures := 0

	var lights := _spike_lights()
	var clear := _flat_absorption(0.0)
	var ruby_ish := _ruby_placeholder_absorption()

	# --- 1. Ideal diamond, face-up, 256px ---
	failures += _render_case("diamond_ideal", 256, _brilliant_planes(40.75, 34.5, 0.56), lights, clear,
		{"sellmeier_b": DIAMOND_B, "sellmeier_c": DIAMOND_C, "size_mm": 3.0,
		"stone_quat": Quaternion.IDENTITY}, [1, 15, 48])

	# --- 2. Windowed diamond: pavilion far below critical (24.4 deg) -> must leak light ---
	failures += _render_case("diamond_windowed", 256, _brilliant_planes(17.0, 22.0, 0.70), lights, clear,
		{"sellmeier_b": DIAMOND_B, "sellmeier_c": DIAMOND_C, "size_mm": 3.0,
		"stone_quat": Quaternion.IDENTITY}, [64])

	# --- 3. Ruby-ish absorber (PLACEHOLDER curve, real spectra come from the species workstream) ---
	failures += _render_case("ruby_spike", 256, _brilliant_planes(42.0, 33.0, 0.58), lights, ruby_ish,
		{"sellmeier_b": Vector3(1.4313493, 0.65054713, 5.3414021),
		"sellmeier_c": Vector3(0.0726631 * 0.0726631, 0.1193242 * 0.1193242, 18.028251 * 18.028251),
		"size_mm": 4.0, "stone_quat": Quaternion(Vector3(1, 0, 0), deg_to_rad(-14.0)),
		"absorb_scale": 1.0}, [64])

	# --- 4. Board-live feasibility probe: 112px timings ---
	_timing_probe(lights, clear)

	print("SPIKE %s" % ("FAILED (%d)" % failures if failures > 0 else "COMPLETE"))
	quit(1 if failures > 0 else 0)


func _render_case(tag: String, res: int, planes: PackedFloat32Array, lights: PackedFloat32Array,
		absorb: PackedFloat32Array, params: Dictionary, spp_batches: Array) -> int:
	var tracer = GemTracerScript.create(res, res)
	if tracer == null:
		print("  %s: NO RD" % tag)
		return 1
	tracer.configure(planes, lights, absorb, params)
	var total_ms := 0.0
	for spp: int in spp_batches:
		total_ms += tracer.accumulate(spp)
	var img: Image = tracer.finalize_image(1.0)
	var path := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(ProjectSettings.globalize_path(path))
	# Mean luminance over covered pixels: cheap sanity that something rendered.
	var xyz: PackedFloat32Array = tracer.read_xyz()
	var lum := 0.0
	var cov := 0.0
	for i in res * res:
		lum += xyz[i * 4 + 1]
		cov += xyz[i * 4 + 3]
	var mean_y := lum / maxf(cov, 1.0)
	print("  %s: %d spp, gpu %.1f ms, mean_Y(covered)=%.4f, coverage=%.1f%% -> %s" % [
		tag, tracer.samples_accumulated, total_ms, mean_y, 100.0 * cov / float(res * res), path])
	tracer.release()
	return 0 if cov > 0.0 else 1


func _timing_probe(lights: PackedFloat32Array, absorb: PackedFloat32Array) -> void:
	var planes := _brilliant_planes(40.75, 34.5, 0.56)
	var tracer = GemTracerScript.create(112, 112)
	if tracer == null:
		return
	tracer.configure(planes, lights, absorb,
		{"sellmeier_b": DIAMOND_B, "sellmeier_c": DIAMOND_C, "size_mm": 3.0})
	tracer.accumulate(1) # pipeline warmup
	print("  timing 112px (diamond, warm):")
	for spp in [1, 4, 8, 16, 64]:
		tracer.reset_accumulation()
		var ms: float = tracer.accumulate(spp)
		print("    %2d spp: %.2f ms  (x64 gems serial ~= %.1f ms)" % [spp, ms, ms * 64.0])
	tracer.release()


## Round brilliant as a convex plane set. Angles in degrees from the girdle plane.
## Unit girdle radius; crown 8 mains + 8 stars would come from the cut compiler —
## the spike uses 8 crown mains, 16 upper girdle break planes, 16 girdle planes,
## 8 pavilion mains offset half-step, table, culet.
func _brilliant_planes(pavilion_deg: float, crown_deg: float, table_ratio: float) -> PackedFloat32Array:
	var planes := PackedFloat32Array()
	var g := 0.03 # girdle half-height
	var a_c := deg_to_rad(crown_deg)
	var a_p := deg_to_rad(pavilion_deg)

	# Table (zone 0)
	var z_table := g + (1.0 - table_ratio) * tan(a_c)
	_add_plane(planes, Vector3(0, 0, 1), z_table, 0)

	# Crown mains (zone 1): 8 facets
	for i in 8:
		var phi := TAU * (float(i) + 0.5) / 8.0
		var n := Vector3(sin(a_c) * cos(phi), sin(a_c) * sin(phi), cos(a_c))
		_add_plane(planes, n, sin(a_c) + cos(a_c) * g, 1)

	# Upper-girdle breaks (zone 2): 16 slightly steeper planes between crown mains
	var a_b := a_c + deg_to_rad(8.0)
	for i in 16:
		var phi := TAU * float(i) / 16.0
		var n := Vector3(sin(a_b) * cos(phi), sin(a_b) * sin(phi), cos(a_b))
		_add_plane(planes, n, sin(a_b) + cos(a_b) * g, 2)

	# Girdle (zone 3): 16 vertical planes
	for i in 16:
		var phi := TAU * (float(i) + 0.5) / 16.0
		_add_plane(planes, Vector3(cos(phi), sin(phi), 0.0), 1.0, 3)

	# Pavilion mains (zone 4): 8 facets, offset half-step from crown
	for i in 8:
		var phi := TAU * float(i) / 8.0
		var n := Vector3(sin(a_p) * cos(phi), sin(a_p) * sin(phi), -cos(a_p))
		_add_plane(planes, n, sin(a_p) + cos(a_p) * g, 4)

	# Lower-girdle breaks (zone 5)
	var a_lb := a_p + deg_to_rad(6.0)
	for i in 16:
		var phi := TAU * (float(i) + 0.5) / 16.0
		var n := Vector3(sin(a_lb) * cos(phi), sin(a_lb) * sin(phi), -cos(a_lb))
		_add_plane(planes, n, sin(a_lb) + cos(a_lb) * g, 5)

	# Culet (zone 6): trims the pavilion apex slightly
	var apex := tan(a_p) + g
	_add_plane(planes, Vector3(0, 0, -1), apex * 0.96, 6)

	return planes


static func _add_plane(arr: PackedFloat32Array, n: Vector3, d: float, zone: int) -> void:
	var un := n.normalized()
	arr.append_array(PackedFloat32Array([un.x, un.y, un.z, d, float(zone), 0.0, 0.0, 0.0]))


## Spike lighting (world space, dir points TOWARD the light). The lighting
## workstream replaces this with designed rigs.
func _spike_lights() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	_add_light(arr, Vector3(-0.5, 0.8, 0.6), 14.0, 8.0, 5500.0, 3.2)   # key, warm, broad
	_add_light(arr, Vector3(0.65, 0.25, 0.72), 30.0, 18.0, 6500.0, 0.7) # fill, cool, soft
	_add_light(arr, Vector3(0.35, -0.62, -0.70), 5.0, 2.5, 7000.0, 2.4) # kicker under pavilion
	return arr


static func _add_light(arr: PackedFloat32Array, dir: Vector3, outer_deg: float, inner_deg: float,
		kelvin: float, power: float) -> void:
	var d := dir.normalized()
	arr.append_array(PackedFloat32Array([
		d.x, d.y, d.z, cos(deg_to_rad(outer_deg)),
		kelvin, power, cos(deg_to_rad(inner_deg)), 1.0]))


static func _flat_absorption(alpha_per_mm: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(81)
	arr.fill(alpha_per_mm)
	return arr


## PLACEHOLDER ruby-shaped curve: violet + green absorption, blue window, red pass.
## Real chromophore spectra (with sources) come from the species workstream.
static func _ruby_placeholder_absorption() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		var a := 0.0
		if wl < 445.0:
			a = 0.85
		elif wl < 500.0:
			a = 0.30
		elif wl < 610.0:
			a = 1.30
		elif wl < 640.0:
			a = 0.35
		else:
			a = 0.05
		arr[i] = a
	return arr
