extends SceneTree
## Bakes the clip catalog for the dev fast path.
##
## Default: every manifest entry whose stone resource exists, written into
## res://generated/gemcache/ (committed/artifacted; GemCache reads user://
## first, then this root). Prints per-clip and total timings; exits nonzero
## when nothing baked or any bake/write failed.
##
## --smoke: bakes a temporary quartz-like stone (idle + turn + flash at
## CLIP_BAKE) into user://gemcache/ for GPU/timing validation before the
## real stone resources land.
##
## Requires a windowed run (RenderingDevice; --headless has none):
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --script res://tools/package_clips.gd
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --script res://tools/package_clips.gd -- --smoke

const STONES_DIR := "res://data/lapidary/stones/"
const CLIPS_DIR := "res://data/lapidary/clips/"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"

var _tracers: Dictionary = {} # internal resolution -> GemTracer


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var smoke := args.has("--smoke")
	print("\n=== package_clips%s ===" % (" (smoke)" if smoke else ""))

	var lights := _rig_lights()
	var background := _rig_background()
	var failures := 0
	var baked := 0
	var skipped := 0
	var total_t0 := Time.get_ticks_usec()

	var work: Array[Dictionary] = []
	if smoke:
		var stone := _smoke_stone()
		for clip_id in ["idle", "turn", "flash"]:
			work.append({"stone": stone, "clip_id": clip_id, "rung": GemRung.CLIP_BAKE,
				"root": GemCache.USER_ROOT})
	else:
		var manifest := GemManifest.load_default()
		for entry in manifest.entries():
			var stone := _load_stone(entry["stone_id"])
			if stone == null:
				print("  SKIP %s/%s — stone resource not landed yet" %
					[entry["stone_id"], entry["clip_id"]])
				skipped += 1
				continue
			work.append({"stone": stone, "clip_id": String(entry["clip_id"]),
				"rung": entry["rung"], "root": GemCache.GENERATED_ROOT})

	for item in work:
		var clip := load(CLIPS_DIR + String(item["clip_id"]) + ".tres") as GemClip
		if clip == null:
			printerr("  FAIL missing clip resource: %s" % item["clip_id"])
			failures += 1
			continue
		var stone: GemStone = item["stone"]
		var rung: int = item["rung"]
		var policy := GemRung.policy(rung)
		var tracer := _tracer_for(int(policy["res"]))
		if tracer == null:
			printerr("  FAIL no RenderingDevice — run windowed, not --headless")
			failures += 1
			break
		var result := GemClipBaker.bake(stone, clip, rung, lights, background, tracer)
		if result.is_empty():
			printerr("  FAIL bake %s/%s" % [stone.stone_id, clip.clip_id])
			failures += 1
			continue
		if not GemCache.write(stone, clip, rung, result["frames"], result["meta"], item["root"]):
			printerr("  FAIL cache write %s/%s" % [stone.stone_id, clip.clip_id])
			failures += 1
			continue
		baked += 1
		var meta: Dictionary = result["meta"]
		var gpu_total := 0.0
		for ms: float in meta["frame_gpu_ms"]:
			gpu_total += ms
		print("  %s/%s@%s: %d frames @ %dpx (from %dpx, %d spp)  gpu %.1f ms  wall %.1f ms" % [
			stone.stone_id, clip.clip_id, meta["rung"], (result["frames"] as Array).size(),
			meta["out"], meta["res"], meta["spp"], gpu_total, meta["wall_ms"]])
		if smoke:
			var per := PackedStringArray()
			for ms: float in meta["frame_gpu_ms"]:
				per.append("%.1f" % ms)
			print("      per-frame gpu ms: [%s]" % ", ".join(per))

	for tracer: GemTracer in _tracers.values():
		tracer.release()
	_tracers.clear()

	var total_ms := float(Time.get_ticks_usec() - total_t0) / 1000.0
	print("  ---")
	print("  baked %d clip(s), skipped %d, failed %d — total %.1f ms" %
		[baked, skipped, failures, total_ms])
	if smoke and failures == 0:
		var idle_ms := _find_wall_ms(work, "idle")
		if idle_ms > 0.0:
			print("  cold-start estimate (8 idles at clip_bake): ~%.2f s" % (idle_ms * 8.0 / 1000.0))

	var ok := failures == 0 and baked > 0
	print("package_clips %s" % ("COMPLETE" if ok else "FAILED"))
	quit(0 if ok else 1)


func _find_wall_ms(work: Array[Dictionary], clip_id: String) -> float:
	# Re-read the just-written sidecar for the smoke stone's idle timing.
	for item in work:
		if String(item["clip_id"]) != clip_id:
			continue
		var clip := load(CLIPS_DIR + clip_id + ".tres") as GemClip
		var cached := GemCache.read(item["stone"], clip, item["rung"])
		if not cached.is_empty():
			return float((cached["meta"] as Dictionary).get("wall_ms", 0.0))
	return 0.0


func _tracer_for(res: int) -> GemTracer:
	if _tracers.has(res):
		return _tracers[res]
	var tracer := GemTracer.create(res, res)
	if tracer == null:
		return null
	_tracers[res] = tracer
	return tracer


func _load_stone(tile_id: StringName) -> GemStone:
	var path := STONES_DIR + String(tile_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var stone := load(path) as GemStone
	if stone == null or stone.species == null:
		return null
	return stone


## Temporary in-code stone for GPU validation while the stone resources land
## in a parallel workstream. Quartz-like (fused-silica Sellmeier), colorless.
func _smoke_stone() -> GemStone:
	var species := GemSpecies.new()
	species.species_id = &"smoke_quartz_placeholder"
	species.sellmeier_b = Vector3(0.6962, 0.4079, 0.8975)
	species.sellmeier_c_um2 = Vector3(0.0047, 0.0135, 97.93)
	species.hardness_mohs = 7.0
	var stone := GemStone.new()
	stone.stone_id = &"smoke_quartz"
	stone.species = species
	stone.silhouette = &"round"
	stone.seed = 7
	stone.size_mm = 5.0
	return stone


## PLACEHOLDER — same rig fallback logic as GemForge until the lighting
## workstream lands the designed rig (this CLI cannot rely on the autoload).
func _rig_lights() -> PackedFloat32Array:
	if ResourceLoader.exists(RIG_PATH):
		var rig := load(RIG_PATH) as GemLightRig
		if rig != null and not rig.lights.is_empty():
			return GemClipBaker.pack_rig_lights(rig)
	return GemClipBaker.placeholder_rig_lights()


func _rig_background() -> Vector3:
	if ResourceLoader.exists(RIG_PATH):
		var rig := load(RIG_PATH) as GemLightRig
		if rig != null:
			return Vector3(rig.bg_zenith, rig.bg_horizon, rig.bg_below)
	return GemClipBaker.placeholder_rig_background()
