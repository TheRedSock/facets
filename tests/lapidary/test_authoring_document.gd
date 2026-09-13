extends SceneTree
var failures := 0
var checks := 0
var output_root := "res://artifacts/authoring-tests/" + str(Time.get_ticks_usec())
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output_root)
	var original: GemStone = load("res://data/lapidary/stones/ruby.tres")
	var original_digest := GemContentIdentity.digest(original)
	var doc := GemAuthoringDocument.new()
	check(doc.open("res://data/lapidary/stones/ruby.tres").is_empty() and not doc.dirty(), "open detached saved specimen")
	var initial := doc.snapshot() as GemStone
	var job := GemFramePlan.animation(initial, load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.PREVIEW)[0]
	check(GemAuthoringAdmission.error(job).is_empty(), "public frame admission")
	var master := GemFramePlan.master_key(job)
	var geometry := GemGeometryPlan.key(job, 4)
	var acceptance_subject := GemAppearanceAcceptance.subject(job)
	check(doc.edit(["material", "source_note"], "Edited evidence narrative").is_empty(), "edit source note")
	check(doc.edit(["material", "material_id"], &"renamed_material").is_empty(), "edit material name")
	check(doc.edit(["material", "species", "display_name"], "New label").is_empty(), "edit species label")
	check(doc.edit(["material", "absorbers", 0, "chromophore", "display_name"], "Color label").is_empty(), "edit absorber label")
	job.stone = doc.snapshot()
	check(GemFramePlan.master_key(job) == master and GemGeometryPlan.key(job, 4) == geometry, "labels/evidence do not invalidate optical or geometry work")
	check(GemAppearanceAcceptance.subject(job) != acceptance_subject, "appearance review includes changed provenance")
	var saved_master := GemFramePlan.master_key(job)
	var amount: float = job.stone.material.absorbers[0].amount
	check(doc.edit(["material", "absorbers", 0, "amount"], amount * 0.8).is_empty(), "edit physical concentration")
	job.stone = doc.snapshot()
	check(GemFramePlan.master_key(job) != saved_master and GemGeometryPlan.key(job, 4) == geometry, "absorption changes optics only")
	check(job.stone.material.absorbers[0].amount_evidence.source_record.has("parent"), "concentration derivative retains original evidence")
	check(GemContentIdentity.digest(original) == original_digest, "loaded source and shared external dependencies untouched")
	check(doc.dirty() and doc.can_undo(), "edit dirty with history")
	check(doc.undo(), "undo concentration")
	job.stone = doc.snapshot()
	check(GemFramePlan.master_key(job) == saved_master and doc.can_redo(), "undo restores exact optical inputs")
	check(doc.redo(), "redo concentration")
	check(doc.edit(["size_mm"], -1.0).is_empty() and not doc.validation_error().is_empty(), "invalid draft remains inspectable")
	check(not doc.save(output_root.path_join("invalid.res")).is_empty() and not FileAccess.file_exists(output_root.path_join("invalid.res")), "invalid draft cannot publish")
	check(not doc.freeze(output_root.path_join("invalid-frozen.res")).is_empty(), "invalid draft cannot freeze for preview")
	check(doc.undo() and doc.validation_error().is_empty(), "undo repairs invalid draft")
	check(not doc.edit(["nonexistent"], 1).is_empty(), "reject nonexistent property")
	check(not doc.edit(["size_mm"], "bad").is_empty(), "reject property type mismatch")
	check(not doc.edit(["material"], GemPrint.new()).is_empty(), "reject incompatible resource assignment")
	check(not doc.edit(["material", "absorbers"], [GemPrint.new()]).is_empty(), "reject incompatible typed-array element")
	var saved := output_root.path_join("new gem ø.res")
	check(doc.save(saved).is_empty() and not doc.dirty() and doc.changes().is_empty(), "save as adopts exact persisted values")
	var reopened := GemAuthoringDocument.new()
	check(reopened.open(saved).is_empty() and GemContentIdentity.digest(reopened.snapshot()) == GemContentIdentity.digest(doc.snapshot()), "reopen binary exact")
	var detached := doc.snapshot() as GemStone; detached.size_mm = 999
	check((doc.snapshot() as GemStone).size_mm != 999, "snapshot cannot mutate document")
	var saved_hash := FileAccess.get_sha256(saved)
	check(reopened.edit(["size_mm"], 3.141592653589793).is_empty(), "high precision size edit")
	check(not reopened.save("res://data/lapidary/stones/ruby.tres").is_empty(), "save as cannot replace unrelated source implicitly")
	var frozen := output_root.path_join("frozen.res")
	check(reopened.freeze(frozen).is_empty() and reopened.path == saved and reopened.dirty(), "freeze preserves editor save path and dirty state")
	check(FileAccess.get_sha256(saved) == saved_hash, "freeze leaves authored source unchanged")
	check(not reopened.freeze(frozen).is_empty(), "existing frozen result needs explicit replace")
	var text_path := output_root.path_join("authored.tres")
	check(reopened.save(text_path).is_empty(), "text authoring save")
	var text_reload := ResourceLoader.load(text_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(GemContentIdentity.digest(reopened.snapshot()) == GemContentIdentity.digest(text_reload), "display draft matches potentially rounded text save")
	var external := text_reload.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemStone; external.size_mm = 4.0
	GemResourceBundle.save(external, text_path)
	check(not reopened.save().is_empty(), "external changes prevent implicit overwrite")
	check(reopened.save(text_path, true).is_empty(), "explicit replace resolves external conflict")
	var measured := GemAuthoringDocument.new(); measured.create(initial)
	check(measured.edit(["material", "species", "ordinary", "index_offset"], 0.01).is_empty(), "edit published refraction")
	var derived := (measured.snapshot() as GemStone).material.species.ordinary.evidence
	check(derived.kind == GemOpticalEvidence.Kind.AUTHORED_APPROXIMATION and derived.source_record.has("parent_evidence"), "changed published refraction becomes authored with retained parent")
	for i in 100: measured.edit(["material", "scatter_per_mm"], 0.001 * i)
	check(measured.validation_error().is_empty(), "repeated edits keep bounded source provenance")
	job.stone = initial
	var caps := GemAuthoringAdmission.capabilities(job)
	check(caps.selected_error.is_empty() and caps.backends.scalar.admitted, "capabilities match current admission")
	check(caps.backends.scalar.status == "approximate", "machine-readable scalar approximation status")
	check(caps.backends.crystal.required_device_features == ["shaderFloat64"] and not caps.backends.crystal.device_verified, "capabilities distinguish CPU and device admission")
	var unsupported := job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemFrameJob
	unsupported.quality["polarization"] = true; unsupported.quality["crystal_transport"] = true
	check(not GemAuthoringAdmission.capabilities(unsupported).selected_error.is_empty(), "unsupported combination actionable")
	check(GemAppearanceAcceptance.status(job, {}).status == "unreviewed", "numerical support does not certify appearance")
	var review := {"subject": GemAppearanceAcceptance.subject(job), "decision": "accepted", "reviewer": "test fixture", "checks": {"fixture": true}}
	check(GemAppearanceAcceptance.status(job, review).status == "accepted", "review bound to exact request")
	job.exposure *= 2
	check(GemAppearanceAcceptance.status(job, review).status == "stale", "print change stales review")
	print("Authoring document: %d checks, %d failures" % [checks, failures])
	print("CHECK_COMPLETE: test_authoring_document"); quit(1 if failures else 0)
