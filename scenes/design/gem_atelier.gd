extends Control
## Gem Atelier — interactive designer preview for the Lapidary GPU pipeline.
##
## One persistent 512x512 GemTracer renders the selected authored stone
## progressively: a 4 spp first batch is shown immediately, then accumulation
## continues toward TARGET_SPP while idle. Material/condition edits mutate an
## in-memory duplicate of the stone — authored .tres files are never written.
## Clip scrubbing reuses GemClipSampler's sample math, so the preview matches
## baked frames exactly. Requires a windowed run; in --headless the preview
## shows a notice and all controls lock.
##
## Keys: R = reset accumulation, Space = toggle raw/print.

const AtelierUi := preload("res://scenes/design/atelier/atelier_ui.gd")

const STONES_DIR := "res://data/lapidary/stones"
const RIGS_DIR := "res://data/lapidary/rigs"
const CLIPS_DIR := "res://data/lapidary/clips"
const EXPORT_DIR := "user://atelier_exports"
const DEFAULT_RIG := &"gameplay_studio"

const RENDER_SIZE := 512
const TARGET_SPP := 128
const PREVIEW_SPP := 64
const FIRST_BATCH_SPP := 4
const STEP_SPP := 12
const DEBOUNCE_MS := 250

var _c: Dictionary = {}
var _tracer: GemTracer
var _default_print: GemPrint

var _stones: Array[GemStone] = []
var _rigs: Array[GemLightRig] = []
var _clips: Array[GemClip] = []

var _authored: GemStone
var _stone: GemStone
var _rig: GemLightRig
var _fingerprint := ""
var _clip_exposure := 1.0
var _presentation := GemPresentation.new()

var _configured := false
var _rebuild_at_ms := 0
var _present_dirty := false
var _syncing := false

var _preview_tex: ImageTexture
var _last_image: Image


func _ready() -> void:
	_default_print = GemPrint.load_house()
	_c = AtelierUi.build(self)
	_load_libraries()
	_populate_pickers()
	_connect_signals()
	_tracer = GemTracer.create(RENDER_SIZE, RENDER_SIZE)
	if _tracer == null or _stones.is_empty() or _rigs.is_empty():
		var overlay: Label = _c["overlay"]
		overlay.text = "GPU preview requires a windowed run" if _tracer == null \
			else "No loadable stones/rigs under data/lapidary"
		overlay.visible = true
		AtelierUi.set_enabled(_c, false)
		set_process(false)
		return
	_select_stone(0)


func _exit_tree() -> void:
	if _tracer != null:
		_tracer.release()
		_tracer = null


# ------------------------------------------------------------------ libraries

func _load_libraries() -> void:
	for path in _list_tres(STONES_DIR):
		var stone := load(path) as GemStone
		if stone != null and stone.material.species != null:
			_stones.append(stone)
		else:
			push_warning("Atelier: skipping unloadable stone %s" % path)
	for path in _list_tres(RIGS_DIR):
		var rig := load(path) as GemLightRig
		if rig != null and not rig.lights.is_empty():
			_rigs.append(rig)
	for path in _list_tres(CLIPS_DIR):
		var clip := load(path) as GemClip
		if clip != null:
			_clips.append(clip)


func _list_tres(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.get_extension() == "tres":
			out.append(dir_path + "/" + file)
	out.sort()
	return out


func _populate_pickers() -> void:
	var stones: OptionButton = _c["stones"]
	for stone in _stones:
		stones.add_item(String(stone.stone_id))
	var rigs: OptionButton = _c["rigs"]
	var default_rig := 0
	for i in _rigs.size():
		rigs.add_item(_rigs[i].display_name if _rigs[i].display_name != "" else String(_rigs[i].rig_id))
		if _rigs[i].rig_id == DEFAULT_RIG:
			default_rig = i
	if not _rigs.is_empty():
		rigs.select(default_rig)
		_rig = _rigs[default_rig]
	var clips: OptionButton = _c["clips"]
	clips.add_item("Manual pose")
	for clip in _clips:
		clips.add_item(String(clip.clip_id))
	(_c["clip_row"] as Control).visible = not _clips.is_empty()


# ------------------------------------------------------------------ wiring

func _connect_signals() -> void:
	(_c["stones"] as OptionButton).item_selected.connect(_on_stone_selected)
	for key in ["scatter", "anisotropy", "band_period", "band_contrast"]:
		(_c[key] as HSlider).value_changed.connect(_on_volume_changed.bind(key))
	(_c["reset"] as Button).pressed.connect(_on_reset_pressed)
	(_c["seed"] as SpinBox).value_changed.connect(_on_seed_changed)
	(_c["size"] as SpinBox).value_changed.connect(_on_size_changed)
	(_c["rigs"] as OptionButton).item_selected.connect(_on_rig_selected)
	for key in ["yaw", "tilt", "turn", "scrub"]:
		(_c[key] as HSlider).value_changed.connect(_on_pose_changed)
	(_c["exposure"] as HSlider).value_changed.connect(func(_v: float) -> void: _present_dirty = true)
	(_c["print_toggle"] as CheckButton).toggled.connect(func(_on: bool) -> void: _present_dirty = true)
	(_c["clips"] as OptionButton).item_selected.connect(func(_i: int) -> void: _apply_pose())
	(_c["export"] as Button).pressed.connect(_export_png)


func _select_stone(idx: int) -> void:
	(_c["stones"] as OptionButton).select(idx)
	_on_stone_selected(idx)


func _on_stone_selected(idx: int) -> void:
	if idx < 0 or idx >= _stones.size():
		return
	_authored = _stones[idx]
	_stone = _duplicate_stone(_authored)
	_sync_stone_ui()
	_queue_rebuild()


## Working copy: never mutate authored resources (load() returns the cached
## instance shared with the rest of the project).
func _duplicate_stone(authored: GemStone) -> GemStone:
	var copy: GemStone = authored.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if copy.condition == null:
		copy.condition = GemCondition.new()
	if copy.condition.banding == null:
		copy.condition.banding = GemBanding.new()
	return copy


func _sync_stone_ui() -> void:
	_syncing = true
	var scattering: Dictionary = GemMaterialCompiler.compile(_stone.material).scatter
	(_c["scatter"] as HSlider).value = scattering.sigma_per_mm
	(_c["anisotropy"] as HSlider).value = scattering.g
	(_c["band_period"] as HSlider).value = _stone.condition.banding.period_mm
	(_c["band_contrast"] as HSlider).value = _stone.condition.banding.contrast
	(_c["seed"] as SpinBox).value = _stone.seed
	(_c["size"] as SpinBox).value = _stone.size_mm
	_syncing = false


func _on_volume_changed(value: float, key: String) -> void:
	if _syncing or _stone == null:
		return
	match key:
		"scatter":
			_stone.material.scatter_per_mm = value
			GemAuthoringDocument._derive_evidence(_stone.material, "scatter_per_mm")
		"anisotropy":
			_stone.material.scatter_g = value
			GemAuthoringDocument._derive_evidence(_stone.material, "scatter_g")
		"band_period":
			_stone.condition.banding.period_mm = value
		"band_contrast":
			_stone.condition.banding.contrast = value
	_queue_rebuild()


func _on_reset_pressed() -> void:
	if _authored == null:
		return
	_stone = _duplicate_stone(_authored)
	_sync_stone_ui()
	_queue_rebuild()


func _on_seed_changed(value: float) -> void:
	if _syncing or _stone == null:
		return
	_stone.seed = int(value)
	_queue_rebuild()


func _on_size_changed(value: float) -> void:
	if _syncing or _stone == null:
		return
	_stone.size_mm = value
	_queue_rebuild()


func _on_rig_selected(idx: int) -> void:
	if idx < 0 or idx >= _rigs.size():
		return
	_rig = _rigs[idx]
	_queue_rebuild()


func _on_pose_changed(_value: float) -> void:
	_apply_pose()


# ------------------------------------------------------------------ render loop

func _queue_rebuild() -> void:
	if _tracer == null:
		return
	_invalidate_preview("Pending current specimen")
	_rebuild_at_ms = Time.get_ticks_msec() + DEBOUNCE_MS


func _process(_delta: float) -> void:
	if _tracer == null:
		return
	if _rebuild_at_ms > 0 and Time.get_ticks_msec() >= _rebuild_at_ms:
		_rebuild_at_ms = 0
		_rebuild_now()
	if not _configured:
		return
	var stepped := false
	if _tracer.samples_accumulated < TARGET_SPP:
		var batch := FIRST_BATCH_SPP if _tracer.samples_accumulated == 0 else STEP_SPP
		_tracer.accumulate(mini(batch, TARGET_SPP - _tracer.samples_accumulated))
		var error := _tracer.transport_error()
		if not error.is_empty(): _invalidate_preview(error); return
		stepped = true
	if stepped or _present_dirty:
		_present_dirty = false
		_update_preview()
		_update_status()


func _rebuild_now() -> void:
	var job := GemFrameJob.new()
	job.stone = _stone; job.rig = _rig; job.print_style = _default_print
	job.resolution = Vector2i(RENDER_SIZE, RENDER_SIZE); job.output_size = job.resolution
	job.samples = TARGET_SPP; job.quality = GemRung.policy(GemRung.PREVIEW)
	var error := GemAuthoringAdmission.error(job)
	if not error.is_empty(): _invalidate_preview(error); return
	var instance := LapidaryStoneCompiler.compile(_stone)
	_fingerprint = str(instance.get("fingerprint", ""))
	if not _tracer.configure_stone(instance, GemRigCompiler.compile(_rig), job.quality):
		_invalidate_preview(_tracer.configuration_error); return
	# configure_stone does not ingest seed/background itself — set them after.
	_tracer.set_seed(int(instance["seed"]))
	_configured = true
	_apply_pose()

func _invalidate_preview(message: String) -> void:
	_configured = false
	_last_image = null; _preview_tex = null
	(_c["preview"] as TextureRect).texture = null
	(_c["overlay"] as Label).text = message
	(_c["overlay"] as Label).visible = true


## Cheap path: pose/framing changes restart accumulation without recompiling.
## With a clip active the sample comes from GemClipSampler (baker parity);
## the manual rig-yaw slider stays a base offset under the clip's orbit.
func _apply_pose() -> void:
	if not _configured:
		_queue_rebuild()
		return
	var quat: Quaternion
	var rig_yaw := deg_to_rad((_c["yaw"] as HSlider).value)
	var role := Vector4.ONE
	_clip_exposure = 1.0
	var clip := _active_clip()
	if clip != null:
		var error := GemAuthoringAdmission.error(clip)
		if not error.is_empty(): _invalidate_preview(error); return
		var t: float = (_c["scrub"] as HSlider).value
		quat = GemClipSampler.frame_orientation(clip, t)
		rig_yaw += GemClipSampler.frame_rig_yaw_rad(clip, t)
		role = GemClipSampler.frame_role_mult(clip, t)
		_clip_exposure = GemClipSampler.frame_exposure(clip, t)
	else:
		quat = Quaternion(Vector3.RIGHT, deg_to_rad((_c["tilt"] as HSlider).value)) \
			* Quaternion(Vector3.UP, deg_to_rad((_c["turn"] as HSlider).value))
	var rest := GemClipSampler.frame_orientation(clip, 0.0) if clip != null else Quaternion(Vector3.RIGHT, deg_to_rad((_c["tilt"] as HSlider).value))
	var framing := GemPresentationCompiler.prepare(_stone, _presentation, rest)
	if not framing.error.is_empty(): _invalidate_preview(framing.error); return
	var pose := GemPresentationCompiler.sample(framing, quat, Vector2i(RENDER_SIZE, RENDER_SIZE), GemClipSampler.ORTHO_HALF)
	_tracer.set_clip_sample(pose.orientation, rig_yaw, role, GemClipSampler.ORTHO_HALF, pose.camera_offset)
	_tracer.reset_accumulation()
	_last_image = null; _preview_tex = null
	(_c["preview"] as TextureRect).texture = null
	(_c["overlay"] as Label).visible = false
	_update_status()


func _active_clip() -> GemClip:
	var idx := (_c["clips"] as OptionButton).selected
	if _clips.is_empty() or idx <= 0 or idx > _clips.size():
		return null
	return _clips[idx - 1]


func _update_preview() -> void:
	if _tracer.samples_accumulated == 0:
		return
	_last_image = _finalize_current()
	if _preview_tex == null:
		_preview_tex = ImageTexture.create_from_image(_last_image)
		(_c["preview"] as TextureRect).texture = _preview_tex
	else:
		_preview_tex.update(_last_image)


func _finalize_current() -> Image:
	var use_print: bool = (_c["print_toggle"] as CheckButton).button_pressed
	var exposure: float = (_c["exposure"] as HSlider).value * _clip_exposure
	return _tracer.finalize_print(_default_print if use_print else null, not use_print, exposure)


func _update_status() -> void:
	var spp := _tracer.samples_accumulated
	var rung := "preview" if spp >= PREVIEW_SPP else "interact"
	(_c["status"] as Label).text = "%s | %d spp | %.1f ms | fp %s" % [
		rung, spp, _tracer.last_dispatch_ms, _fingerprint]


# ------------------------------------------------------------------ export / input

func _export_png() -> void:
	if not _configured or _tracer.samples_accumulated == 0:
		return
	var img := _finalize_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
	var d := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [
		d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	var abs_path := ProjectSettings.globalize_path("%s/%s_%s.png" % [EXPORT_DIR, _stone.stone_id, stamp])
	var err := img.save_png(abs_path)
	if err == OK:
		print("Atelier export: %s" % abs_path)
		(_c["message"] as Label).text = "Exported " + abs_path
	else:
		(_c["message"] as Label).text = "Export failed (error %d)" % err


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _tracer == null:
		return
	match key.keycode:
		KEY_R:
			if _configured:
				_tracer.reset_accumulation()
				_update_status()
		KEY_SPACE:
			var toggle: CheckButton = _c["print_toggle"]
			toggle.button_pressed = not toggle.button_pressed


# ------------------------------------------------------------------ debug API (harness)

func debug_set_volume(key: String, value: float) -> void:
	var slider := _c.get(key) as HSlider
	if slider != null:
		slider.value = value


func debug_get_preview_image() -> Image:
	return _last_image


func debug_status() -> Dictionary:
	return {
		"configured": _configured,
		"spp": _tracer.samples_accumulated if _tracer != null else 0,
		"last_ms": _tracer.last_dispatch_ms if _tracer != null else 0.0,
		"fingerprint": _fingerprint,
	}
