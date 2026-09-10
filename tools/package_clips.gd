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
## --clips <ids>: comma-separated clip ids to bake (e.g. turn). Default: all.
##
## Turn bakes also write a lookdev atlas (one row per stone, one column per
## frame) to artifacts/lookdev/rotation/turn_atlas.png — the rotation×lighting
## lattice is gone; this sheet is the inspectable stand-in.
##
## Requires a windowed run (RenderingDevice; --headless has none):
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --script res://tools/package_clips.gd
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --script res://tools/package_clips.gd -- --smoke
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --script res://tools/package_clips.gd -- --clips turn

const SheetComposer := preload("res://core/lapidary/eval/sheet_composer.gd")

const STONES_DIR := "res://data/lapidary/stones/"
const CLIPS_DIR := "res://data/lapidary/clips/"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const ATLAS_DIR := "res://artifacts/lookdev/rotation"
const LADDER := [
	"quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond",
	"fluorite", "smoky_quartz", "tourmaline", "rhodolite", "aquamarine", "alexandrite",
	"painite", "blue_garnet",
]

var _tracers: Dictionary = {} # internal resolution -> GemTracer


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var smoke := args.has("--smoke")
	var clip_filter := _parse_clip_filter(args)
	var tag := ""
	if smoke:
		tag += " smoke"
	if not clip_filter.is_empty():
		tag += " clips=" + ",".join(clip_filter)
	print("\n=== package_clips%s ===" % tag)

	var lights := _rig_lights()
	var background := _rig_environment()
	var failures := 0
	var baked := 0
	var skipped := 0
	var total_t0 := Time.get_ticks_usec()

	var work: Array[Dictionary] = []
	if smoke:
		var stone := _smoke_stone()
		for clip_id in ["idle", "turn", "flash"]:
			if not clip_filter.is_empty() and not clip_filter.has(clip_id):
				continue
			work.append({"stone": stone, "clip_id": clip_id, "rung": GemRung.CLIP_BAKE,
				"root": GemCache.USER_ROOT})
	else:
		var manifest := GemManifest.load_default()
		for entry in manifest.entries():
			var clip_id := String(entry["clip_id"])
			if not clip_filter.is_empty() and not clip_filter.has(clip_id):
				continue
			var stone := _load_stone(entry["stone_id"])
			if stone == null:
				print("  SKIP %s/%s — stone resource not landed yet" %
					[entry["stone_id"], clip_id])
				skipped += 1
				continue
			work.append({"stone": stone, "clip_id": clip_id,
				"rung": entry["rung"], "root": GemCache.GENERATED_ROOT})

	var turn_rows: Dictionary = {} # stone_id -> Array[Image]
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
		if String(clip.clip_id) == "turn":
			turn_rows[String(stone.stone_id)] = result["frames"]
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

	if not turn_rows.is_empty():
		_write_turn_atlas(turn_rows)

	var ok := failures == 0 and baked > 0
	if ok and not smoke:
		_prune_stale_cache_versions()
	print("package_clips %s" % ("COMPLETE" if ok else "FAILED"))
	quit(0 if ok else 1)


## After a successful full package into GENERATED_ROOT, remove foreign
## look-version directories (vN where N != GemCache.LOOK_VERSION).
func _prune_stale_cache_versions() -> void:
	var abs_root := ProjectSettings.globalize_path(GemCache.GENERATED_ROOT)
	var keep := "v%d" % GemCache.LOOK_VERSION
	var dirs := DirAccess.get_directories_at(abs_root)
	if dirs.is_empty() and not DirAccess.dir_exists_absolute(abs_root):
		return
	var removed := 0
	for name: String in dirs:
		if not name.begins_with("v") or name == keep:
			continue
		var path := abs_root.path_join(name)
		var err := _remove_dir_recursive(path)
		if err == OK:
			removed += 1
			print("  pruned stale cache %s" % name)
		else:
			printerr("  FAIL prune %s (%s)" % [name, error_string(err)])
	if removed > 0:
		print("  pruned %d stale cache version(s); kept %s" % [removed, keep])


func _remove_dir_recursive(abs_path: String) -> Error:
	for file_name: String in DirAccess.get_files_at(abs_path):
		var err := DirAccess.remove_absolute(abs_path.path_join(file_name))
		if err != OK:
			return err
	for sub: String in DirAccess.get_directories_at(abs_path):
		var err := _remove_dir_recursive(abs_path.path_join(sub))
		if err != OK:
			return err
	return DirAccess.remove_absolute(abs_path)


func _parse_clip_filter(args: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for i in args.size():
		var a := args[i]
		var raw := ""
		if a == "--clips" and i + 1 < args.size():
			raw = args[i + 1]
		elif a.begins_with("--clips="):
			raw = a.substr("--clips=".length())
		if raw.is_empty():
			continue
		for part in raw.split(",", false):
			var id := part.strip_edges()
			if not id.is_empty() and not out.has(id):
				out.append(id)
	return out


func _write_turn_atlas(turn_rows: Dictionary) -> void:
	var frames_n := 0
	for sid in turn_rows:
		frames_n = maxi(frames_n, (turn_rows[sid] as Array).size())
	if frames_n <= 0:
		return
	var tiles: Array = []
	var row_labels: Array = []
	for sid in LADDER:
		if not turn_rows.has(sid):
			continue
		var frames: Array = turn_rows[sid]
		row_labels.append(sid.replace("_", " ").to_upper())
		for i in frames_n:
			if i < frames.size():
				tiles.append({"image": frames[i], "label": ""})
			else:
				tiles.append({"image": Image.create_empty(112, 112, false, Image.FORMAT_RGBA8),
					"label": ""})
	if tiles.is_empty():
		return
	var cols: Array = []
	for i in frames_n:
		cols.append("F%d" % i)
	var sheet: Image = SheetComposer.compose(tiles, frames_n, false,
		"TURN CLIP - 360 DEG EASED - CLIP BAKE - LOOK V%d" % GemCache.LOOK_VERSION,
		row_labels, cols)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ATLAS_DIR))
	var path := ATLAS_DIR + "/turn_atlas.png"
	var err := sheet.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("  FAIL turn atlas write %s (%s)" % [path, error_string(err)])
		return
	print("  wrote %s (%dx%d, %d stones x %d frames)" % [
		path, sheet.get_width(), sheet.get_height(), row_labels.size(), frames_n])


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


func _rig_lights() -> PackedFloat32Array:
	assert(ResourceLoader.exists(RIG_PATH), "package_clips: missing %s" % RIG_PATH)
	return GemRigCompiler.pack(load(RIG_PATH) as GemLightRig)


func _rig_environment() -> Dictionary:
	assert(ResourceLoader.exists(RIG_PATH), "package_clips: missing %s" % RIG_PATH)
	return GemRigCompiler.environment(load(RIG_PATH) as GemLightRig)
