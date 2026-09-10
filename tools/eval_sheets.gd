extends SceneTree
## Lapidary evaluation harness: renders the evidence sheets used to judge the
## GPU gem pipeline's look and performance, plus measured timings.
## Requires a RenderingDevice, so run WINDOWED (never --headless):
##   godot --path . --script res://tools/eval_sheets.gd
## Outputs into artifacts/eval/: contact_sheet.png, condition_sheet.png,
## lighting_sheet.png, rung_sheet.png, timings.json, EVAL_NOTES.md.
## Exit code 0 on success, 1 if any sheet failed.

const SheetComposer := preload("res://core/lapidary/eval/sheet_composer.gd")

const OUT_DIR := "res://artifacts/eval"
const STONES_DIR := "res://data/lapidary/stones"
const RIG_GAMEPLAY_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const RIG_REFERENCE_PATH := "res://data/lapidary/rigs/reference_daylight.tres"
const ORTHO_HALF := 1.3
const EXPOSURE := 1.0  # the rig lights the stone; the house print is the only exposure knob
## Ladder display order for the contact sheet; unknown ids append after.
const LADDER := ["quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond"]
## HERO cost projection from the measured PREVIEW tiles:
## (768/256)^2 pixels * (512/32) spp * (48/24) bounces = 288.
const HERO_PROJECTION_FACTOR := 288.0
const HERO_BUDGET_MS := 60000.0
const HERO_REDUCED_SPP := 128
## Per-dispatch ceiling. A single 768px HERO dispatch at the policy batch
## (64 spp) takes ~4 s on this GPU and trips the Windows watchdog (TDR,
## ~2 s) -> Vulkan device loss. Dispatches are chunked to stay under this.
const TDR_SAFE_DISPATCH_MS := 700.0

var _face_up := Quaternion(Vector3(1, 0, 0), deg_to_rad(-12.0))
var _failures := 0
var _warnings: PackedStringArray = []
var _rig_gameplay: GemLightRig
var _rig_reference: GemLightRig
var _timings := {}
var _hero_spp := 512
var _contact_count := 0
var _tres_count := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_rig_gameplay = load(RIG_GAMEPLAY_PATH) as GemLightRig
	_rig_reference = load(RIG_REFERENCE_PATH) as GemLightRig
	if _rig_gameplay == null:
		print("EVAL_SHEETS FAILED: gameplay rig missing (%s)" % RIG_GAMEPLAY_PATH)
		quit(1)
		return
	if _rig_reference == null:
		_warn("reference rig missing (%s) - reference columns skipped" % RIG_REFERENCE_PATH)

	_sheet_contact()
	_sheet_condition()
	_sheet_lighting()
	_sheet_rungs()
	_measure_timings()
	_write_outputs()

	print("EVAL_SHEETS %s in %.1f s (%d warnings)" % [
		"FAILED" if _failures > 0 else "COMPLETE",
		float(Time.get_ticks_msec() - t0) / 1000.0, _warnings.size()])
	quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ sheets

## a) Every available stone (.tres ladder + in-code makers), gameplay rig,
##    raw row + print row. PREVIEW policy at 64 spp, 224 px tiles.
func _sheet_contact() -> void:
	print("== contact sheet ==")
	var stones := _collect_stones()
	if stones.is_empty():
		_fail("contact: no stones available")
		return
	var tracer := GemTracer.create(224, 224)
	if tracer == null:
		_fail("contact: no RenderingDevice (run windowed)")
		return
	var policy: Dictionary = GemRung.policy(GemRung.PREVIEW)
	policy["spp"] = 64
	var raw_tiles: Array = []
	var print_tiles: Array = []
	for entry: Dictionary in stones:
		var ms := _render(tracer, entry["instance"], entry["seed"], _rig_gameplay,
			policy, 64, int(policy["batch"]))
		raw_tiles.append({"image": tracer.finalize_print(null, true, EXPOSURE), "label": entry["name"]})
		print_tiles.append({"image": tracer.finalize_print(GemPrint.load_house(), false, EXPOSURE), "label": entry["name"]})
		print("  contact %-16s %7.1f ms" % [entry["name"], ms])
	tracer.release()
	_contact_count = stones.size()
	var sheet: Image = SheetComposer.compose(raw_tiles + print_tiles, stones.size(), true,
		"CONTACT - GAMEPLAY RIG - PREVIEW POLICY SPP 64 - 224PX", ["RAW", "PRINT"], [])
	_save(sheet, "contact_sheet.png")


## Explicit physical volume sweeps. These coefficients are not grade laws.
func _sheet_condition() -> void:
	print("== physical condition sheet ==")
	var stops := [0.0, 0.05, 0.1, 0.2, 0.4]
	var axes := ["SCATTER /mm", "BAND CONTRAST"]
	var tracer := GemTracer.create(176, 176)
	if tracer == null:
		_fail("condition: no RenderingDevice")
		return
	var policy := GemRung.policy(GemRung.PREVIEW)
	var base_stone: GemStone = load("res://data/lapidary/stones/ruby.tres")
	var tiles: Array = []
	for axis: String in axes:
		for stop: float in stops:
			var stone: GemStone = base_stone.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
			if axis == "SCATTER /mm":
				stone.material.scatter_per_mm = stop
			else:
				stone.condition.banding.contrast = stop
			var instance := LapidaryStoneCompiler.compile(stone)
			_render(tracer, instance, stone.seed, _rig_gameplay, policy, 128, int(policy["batch"]))
			tiles.append({"image": tracer.finalize_print(GemPrint.load_house(), false, EXPOSURE), "label": "%s %.2f" % [axis, stop]})
	tracer.release()
	var cols: Array = []
	for stop: float in stops:
		cols.append("%.2f" % stop)
	_save(SheetComposer.compose(tiles, stops.size(), true,
		"EXPLICIT CONDITION - RUBY - GAMEPLAY RIG - SPP128 - 176PX", axes, cols), "condition_sheet.png")


## c) Ruby / diamond / sapphire makers x [gameplay raw, gameplay print,
##    reference raw, reference print]. 224 px, 64 spp, dispersion on diamond.
func _sheet_lighting() -> void:
	print("== lighting sheet ==")
	var stones: Array = [["RUBY", _ruby_fine()], ["DIAMOND", _diamond_perfect()], ["SAPPHIRE", _sapphire_like()]]
	var rigs: Array = [["GAMEPLAY", _rig_gameplay]]
	if _rig_reference != null:
		rigs.append(["REFERENCE", _rig_reference])
	var tracer := GemTracer.create(224, 224)
	if tracer == null:
		_fail("lighting: no RenderingDevice")
		return
	var tiles: Array = []
	for s: Array in stones:
		var stone: GemStone = s[1]
		var instance := LapidaryStoneCompiler.compile(stone)
		for r: Array in rigs:
			var policy := {"max_bounces": 32, "volume": true, "dispersion": s[0] == "DIAMOND"}
			var ms := _render(tracer, instance, stone.seed, r[1], policy, 64, 16)
			tiles.append({"image": tracer.finalize_print(null, true, EXPOSURE), "label": ""})
			tiles.append({"image": tracer.finalize_print(GemPrint.load_house(), false, EXPOSURE), "label": ""})
			print("  lighting %-8s @ %-9s %7.1f ms" % [s[0], r[0], ms])
	tracer.release()
	var cols: Array = []
	var row_names: Array = []
	for r: Array in rigs:
		cols.append("%s RAW" % r[0])
		cols.append("%s PRINT" % r[0])
	for s: Array in stones:
		row_names.append(s[0])
	var sheet: Image = SheetComposer.compose(tiles, rigs.size() * 2, false,
		"LIGHTING - RAW VS PRINT - SPP 64 - 224PX", row_names, cols)
	_save(sheet, "lighting_sheet.png")


## d) Diamond + quartz makers x all 5 rungs at true policy res/spp/batch,
##    NEAREST-resized to 224 so rung resolution differences stay honest.
func _sheet_rungs() -> void:
	print("== rung sheet ==")
	var stone_defs: Array = [["DIAMOND", _diamond_perfect()], ["QUARTZ", _quartz_low()]]
	var instances := {}
	for sd: Array in stone_defs:
		instances[sd[0]] = LapidaryStoneCompiler.compile(sd[1])
	var rungs: Array = [GemRung.INTERACT, GemRung.PREVIEW, GemRung.BOARD_LIVE, GemRung.CLIP_BAKE, GemRung.HERO]
	var tile_by_key := {}
	var rung_tile_ms := {}
	var preview_ms_sum := 0.0
	for rung: int in rungs:
		var policy: Dictionary = GemRung.policy(rung)
		var hero_note := ""
		if rung == GemRung.HERO:
			var projected := preview_ms_sum * HERO_PROJECTION_FACTOR
			if projected > HERO_BUDGET_MS:
				_hero_spp = HERO_REDUCED_SPP
				hero_note = " SPP128"
				_warn("hero projection %.0f ms exceeds %.0f ms budget - hero spp reduced 512 -> %d" % [
					projected, HERO_BUDGET_MS, HERO_REDUCED_SPP])
		var res := int(policy["res"])
		var tracer := GemTracer.create(res, res)
		if tracer == null:
			_fail("rung %s: no RenderingDevice" % GemRung.rung_name(rung))
			continue
		for sd: Array in stone_defs:
			var stone: GemStone = sd[1]
			var inst: Dictionary = instances[sd[0]]
			var stone_policy: Dictionary = GemRung.policy(rung)
			var stone_spp := _hero_spp if rung == GemRung.HERO else int(stone_policy["spp"])
			var ms := _render(tracer, inst, stone.seed, _rig_gameplay,
				stone_policy, stone_spp, int(stone_policy["batch"]))
			if rung == GemRung.PREVIEW:
				preview_ms_sum += ms
			var img := tracer.finalize_print(GemPrint.load_house(), false, EXPOSURE)
			if img.get_width() != 224:
				img.resize(224, 224, Image.INTERPOLATE_NEAREST)
			tile_by_key["%s|%d" % [sd[0], rung]] = {
				"image": img,
				"label": "%s%s %s" % [GemRung.rung_name(rung), hero_note, _fmt_ms(ms)],
			}
			rung_tile_ms["%s %s" % [sd[0].to_lower(), GemRung.rung_name(rung)]] = snappedf(ms, 0.01)
			print("  rung %-10s %-8s %8.1f ms (%d spp @ %dpx)" % [
				GemRung.rung_name(rung), sd[0], ms, stone_spp, res])
		tracer.release()
	_timings["rung_sheet_tile_ms"] = rung_tile_ms
	var tiles: Array = []
	for sd: Array in stone_defs:
		for rung: int in rungs:
			tiles.append(tile_by_key.get("%s|%d" % [sd[0], rung],
				{"image": Image.create_empty(224, 224, false, Image.FORMAT_RGBA8), "label": "MISSING"}))
	var cols: Array = []
	for rung: int in rungs:
		cols.append(GemRung.rung_name(rung))
	var sheet: Image = SheetComposer.compose(tiles, rungs.size(), true,
		"RUNGS - GAMEPLAY RIG - PRINT - NEAREST RESIZE TO 224", ["DIAMOND", "QUARTZ"], cols)
	_save(sheet, "rung_sheet.png")


# ------------------------------------------------------------------ timings

## e) Measurement pattern from board_grid_check.gd: one warm-up dispatch,
##    then 5 measured samples, median. Single-stone rung cost samples one
##    TDR-safe chunk (capped at the policy batch); frame ms scales the
##    median chunk to the rung's full spp.
func _measure_timings() -> void:
	print("== timings ==")
	_timings["adapter"] = RenderingServer.get_video_adapter_name()
	_timings["generated"] = Time.get_datetime_string_from_system()
	_timings["hero_spp"] = _hero_spp

	var stone := _ruby_fine()
	var instance := LapidaryStoneCompiler.compile(stone)
	var lights := GemRigCompiler.compile(_rig_gameplay)

	var by_rung := {}
	for rung: int in [GemRung.INTERACT, GemRung.PREVIEW, GemRung.BOARD_LIVE, GemRung.CLIP_BAKE, GemRung.HERO]:
		var policy: Dictionary = GemRung.policy(rung)
		var spp := _hero_spp if rung == GemRung.HERO else int(policy["spp"])
		var batch := int(policy["batch"])
		var res := int(policy["res"])
		var tracer := GemTracer.create(res, res)
		if tracer == null:
			_fail("timings: no RenderingDevice")
			return
		tracer.set_seed(stone.seed)
		tracer.configure_stone(instance, lights, policy)
		tracer.set_clip_sample(_face_up, 0.0, Vector4.ONE, ORTHO_HALF)
		var probe_ms := tracer.accumulate(1)
		var chunk := clampi(int(TDR_SAFE_DISPATCH_MS / maxf(probe_ms, 0.05)), 1, batch)
		tracer.accumulate(chunk) # warm-up at measured chunk size
		var samples: Array[float] = []
		for f in 5:
			samples.append(tracer.accumulate(chunk))
		samples.sort()
		var frame_ms := samples[2] * float(spp) / float(chunk)
		by_rung[GemRung.rung_name(rung)] = {
			"res": res, "spp": spp, "chunk_spp": chunk,
			"chunk_ms_median": snappedf(samples[2], 0.001),
			"frame_ms": snappedf(frame_ms, 0.01),
		}
		print("  single %-10s median %8.3f ms/%d spp -> %8.2f ms/frame" % [
			GemRung.rung_name(rung), samples[2], chunk, frame_ms])
		tracer.release()
	_timings["single_stone_ms_by_rung"] = by_rung

	var policy_bl: Dictionary = GemRung.policy(GemRung.BOARD_LIVE)
	var instances: Array = []
	for maker: Callable in [_quartz_low, _ruby_fine, _diamond_perfect, _sapphire_like]:
		instances.append(LapidaryStoneCompiler.compile(maker.call()))
	var batch_out := {}
	for grid_n: int in [1, 4, 8]:
		var count := grid_n * grid_n
		var tracer := GemTracer.create(112 * grid_n, 112 * grid_n)
		if tracer == null:
			_fail("timings: no RenderingDevice (grid %d)" % grid_n)
			return
		tracer.configure_stones(instances, lights, policy_bl, Vector2i(grid_n, grid_n))
		var states: Array = []
		for i in count:
			states.append({
				"quat": _face_up * Quaternion(Vector3(0, 1, 0), deg_to_rad(float(i) * 13.7)),
				"stone_index": i % instances.size(),
				"ortho_half": ORTHO_HALF,
			})
		tracer.set_instances(states)
		tracer.accumulate(int(policy_bl["spp"])) # warm-up
		var frame_ms: Array[float] = []
		for f in 5:
			tracer.reset_accumulation()
			frame_ms.append(tracer.accumulate(int(policy_bl["spp"])))
		frame_ms.sort()
		var med := frame_ms[2]
		batch_out["gems_%d" % count] = {
			"ms_per_frame_median": snappedf(med, 0.01),
			"ms_per_gem": snappedf(med / float(count), 0.001),
		}
		print("  batch %2d gems: median %8.2f ms/frame (%.2f ms/gem)" % [count, med, med / float(count)])
		tracer.release()
	_timings["batch_board_live"] = batch_out


# ------------------------------------------------------------------ output

func _write_outputs() -> void:
	_timings["warnings"] = Array(_warnings)
	var json_file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/timings.json"), FileAccess.WRITE)
	if json_file == null:
		_fail("cannot write timings.json")
	else:
		json_file.store_string(JSON.stringify(_timings, "\t") + "\n")
		json_file.close()
		print("  wrote %s/timings.json" % OUT_DIR)

	var table := _timing_table()
	print("\n%s" % table)

	var notes := "# Lapidary Evaluation Notes\n\n"
	notes += "Generated %s on %s by `tools/eval_sheets.gd` (windowed CLI).\n\n" % [
		_timings.get("generated", "?"), _timings.get("adapter", "?")]
	notes += "Sheets: `contact_sheet.png`, `condition_sheet.png`, `lighting_sheet.png`, `rung_sheet.png`.\n\n"
	notes += "## Timings\n\n```\n%s```\n\n## Summary\n\n" % table
	for line in _summary_lines():
		notes += "- %s\n" % line
	if not _warnings.is_empty():
		notes += "\n## Warnings\n\n"
		for w in _warnings:
			notes += "- %s\n" % w
	var notes_file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/EVAL_NOTES.md"), FileAccess.WRITE)
	if notes_file == null:
		_fail("cannot write EVAL_NOTES.md")
	else:
		notes_file.store_string(notes)
		notes_file.close()
		print("  wrote %s/EVAL_NOTES.md" % OUT_DIR)


func _timing_table() -> String:
	if not _timings.has("single_stone_ms_by_rung") or not _timings.has("batch_board_live"):
		return "timings unavailable (measurement pass failed)\n"
	var s := "single stone by rung - ruby maker - median chunk dispatch scaled to full spp\n"
	s += "%-12s %5s %5s %6s %12s %12s\n" % ["rung", "res", "spp", "chunk", "chunk ms", "frame ms"]
	for rung_name: String in ["interact", "preview", "board_live", "clip_bake", "hero"]:
		var d: Dictionary = _timings["single_stone_ms_by_rung"][rung_name]
		s += "%-12s %5d %5d %6d %12.3f %12.2f\n" % [rung_name, d["res"], d["spp"], d["chunk_spp"], d["chunk_ms_median"], d["frame_ms"]]
	s += "\nbatched BOARD_LIVE - 112px cells - 4 maker stones cycled - median of 5\n"
	s += "%-6s %12s %10s\n" % ["gems", "ms/frame", "ms/gem"]
	for key: String in ["gems_1", "gems_16", "gems_64"]:
		var d: Dictionary = _timings["batch_board_live"][key]
		s += "%-6s %12.2f %10.3f\n" % [key.trim_prefix("gems_"), d["ms_per_frame_median"], d["ms_per_gem"]]
	return s


func _summary_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Contact sheet contains %d stones (%d authored and four diagnostic makers). Inspect images before judging appearance." % [_contact_count, _tres_count])
	lines.append("Condition sheet varies explicit scattering and band contrast. Grade labels do not change transport. These are authored approximations, not measured specimens.")
	if _timings.has("single_stone_ms_by_rung"):
		var r: Dictionary = _timings["single_stone_ms_by_rung"]
		lines.append("Rung frame cost (ruby maker): interact %.2f ms, preview %.2f ms, board_live %.2f ms, clip_bake %.2f ms, hero %.2f ms at %d spp." % [
			r["interact"]["frame_ms"], r["preview"]["frame_ms"], r["board_live"]["frame_ms"],
			r["clip_bake"]["frame_ms"], r["hero"]["frame_ms"], _hero_spp])
	if _timings.has("batch_board_live"):
		var b: Dictionary = _timings["batch_board_live"]
		lines.append("Measured BOARD_LIVE batch costs: 1 gem %.2f ms/frame, 16 gems %.2f ms, 64 gems %.2f ms (%.3f ms/gem at 64)." % [
			b["gems_1"]["ms_per_frame_median"], b["gems_16"]["ms_per_frame_median"],
			b["gems_64"]["ms_per_frame_median"], b["gems_64"]["ms_per_gem"]])
	return lines


# ------------------------------------------------------------------ render helpers

## One stone render into an already-created tracer. Call order mirrors
## tools/rig_ab_check.gd: seed, background BEFORE configure, then clip sample.
## Accumulation starts with a 1-spp probe dispatch that sizes the following
## chunks so no single dispatch exceeds TDR_SAFE_DISPATCH_MS (never larger
## than the rung's policy batch).
func _render(tracer: GemTracer, instance: Dictionary, stone_seed: int, rig: GemLightRig,
		policy: Dictionary, spp: int, batch: int) -> float:
	tracer.set_seed(stone_seed)
	tracer.configure_stone(instance, GemRigCompiler.compile(rig), policy)
	tracer.set_clip_sample(_face_up, 0.0, Vector4.ONE, ORTHO_HALF)
	var ms := tracer.accumulate(1)
	var chunk := clampi(int(TDR_SAFE_DISPATCH_MS / maxf(ms, 0.05)), 1, batch)
	var remaining := spp - 1
	while remaining > 0:
		var n := mini(chunk, remaining)
		ms += tracer.accumulate(n)
		remaining -= n
	return ms


## All .tres stones from data/lapidary/stones (ladder order) + the 4 in-code
## makers so the contact sheet is never empty. Bad resources skip with a warning.
func _collect_stones() -> Array:
	var out: Array = []
	var files: Array = []
	var dir := DirAccess.open(STONES_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.get_extension() == "tres":
				files.append(f)
	else:
		_warn("stones dir missing (%s)" % STONES_DIR)
	files.sort_custom(func(a: String, b: String) -> bool: return _ladder_key(a) < _ladder_key(b))
	for f: String in files:
		var stone := ResourceLoader.load("%s/%s" % [STONES_DIR, f]) as GemStone
		if stone == null:
			_warn("stone %s failed to load - skipped" % f)
			continue
		var why := _stone_invalid_reason(stone)
		if not why.is_empty():
			_warn("stone %s invalid (%s) - skipped" % [f, why])
			continue
		var stone_name := String(stone.stone_id) if stone.stone_id != &"" else f.get_basename()
		out.append({"name": stone_name, "seed": stone.seed, "instance": LapidaryStoneCompiler.compile(stone)})
		_tres_count += 1
	for maker: Array in [["quartz-low", _quartz_low], ["ruby-fine", _ruby_fine],
			["diamond-perfect", _diamond_perfect], ["sapphire-like", _sapphire_like]]:
		var stone: GemStone = (maker[1] as Callable).call()
		out.append({"name": maker[0], "seed": stone.seed, "instance": LapidaryStoneCompiler.compile(stone)})
	return out


static func _ladder_key(file: String) -> String:
	var idx := LADDER.find(file.get_basename())
	return ("%02d" % idx if idx >= 0 else "99") + file


static func _stone_invalid_reason(stone: GemStone) -> String:
	if stone.material.species == null:
		return "no species"
	return "; ".join(stone.material.validate())


static func _fmt_ms(ms: float) -> String:
	return "%.1fMS" % ms if ms < 10.0 else "%.0fMS" % ms


func _warn(msg: String) -> void:
	_warnings.append(msg)
	print("  WARNING: %s" % msg)


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAILURE: %s" % msg)


func _save(img: Image, file_name: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name]))
	if err != OK:
		_fail("save %s failed (error %d)" % [file_name, err])
	else:
		print("  wrote %s/%s (%dx%d)" % [OUT_DIR, file_name, img.get_width(), img.get_height()])


# ------------------------------------------------------------------ fallback stone makers
# Mirrors tools/board_grid_check.gd exactly (same Sellmeier constants, grades,
# seeds, sizes) so the harness is never empty while authored data lands.

func _quartz_low() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(1.07044083, 1.10202242, 0.0)
	sp.sellmeier_c_um2 = Vector3(0.0100585997, 100.0, 0.0)
	sp.hardness_mohs = 7.0
	var cloud := GemInclusionArchetype.new()
	cloud.form = GemInclusionArchetype.Form.CLOUD
	cloud.size_mm_range = Vector2(0.3, 0.9)
	cloud.scatter_density = 6.0
	sp.inclusions = [cloud]
	return _stone(sp, null, [0.3, 0.3, 0.3, 0.4], 11, 5.0)


func _ruby_fine() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	sp.sellmeier_c_um2 = Vector3(0.00527993, 0.01423827, 325.01783)
	sp.hardness_mohs = 9.0
	sp.fluorescence_emission_nm = 693.0
	sp.fluorescence_strength = 0.5
	var ch := GemChromophore.new()
	ch.absorption_mm = _band_curve(0.7, 0.22, 0.95, 0.25, 0.04)
	return _stone(sp, ch, [0.92, 0.85, 0.9, 0.95], 7, 5.2)


func _diamond_perfect() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(4.3356, 0.3306, 0.0)
	sp.sellmeier_c_um2 = Vector3(0.011236, 0.030625, 0.0)
	sp.hardness_mohs = 10.0
	sp.base_polish_roughness = 0.004
	return _stone(sp, null, [1.0, 1.0, 1.0, 1.0], 3, 5.5)


func _sapphire_like() -> GemStone:
	var sp := GemSpecies.new()
	sp.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	sp.sellmeier_c_um2 = Vector3(0.00527993, 0.01423827, 325.01783)
	sp.hardness_mohs = 9.0
	var ch := GemChromophore.new()
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		arr[i] = 0.06 if wl < 500.0 else lerpf(0.15, 1.1, clampf((wl - 500.0) / 180.0, 0.0, 1.0))
	ch.absorption_mm = arr
	return _stone(sp, ch, [0.85, 0.8, 0.85, 0.9], 5, 5.3)


static func _stone(sp: GemSpecies, ch: GemChromophore, g: Array, stone_seed: int, size: float) -> GemStone:
	var grade := GemGrade.new()
	grade.cut = g[0]
	grade.clarity = g[1]
	grade.surface = g[2]
	grade.crystal = g[3]
	var st := GemStone.new()
	st.cut = load("res://data/lapidary/cuts/brilliant.tres")
	st.material.species = sp
	st.material.chromophore = ch
	st.grade = grade
	st.seed = stone_seed
	st.size_mm = size
	return st


static func _band_curve(a_uv: float, a_blue: float, a_green: float, a_orange: float, a_red: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(81)
	for i in 81:
		var wl := 380.0 + float(i) * 5.0
		var a := a_red
		if wl < 445.0:
			a = a_uv
		elif wl < 500.0:
			a = a_blue
		elif wl < 610.0:
			a = a_green
		elif wl < 640.0:
			a = a_orange
		arr[i] = a
	return arr
