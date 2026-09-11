class_name GemGeometryPlan
extends RefCounted
## Optional primary-boundary companion. Independent of optical estimators,
## lighting, absorption/scattering and display processing; not refracted AOVs.
static var _source_digest := ""

static func source_digest() -> String:
	if _source_digest.is_empty():
		_source_digest = GemContentIdentity.digest([GemRenderIdentity.pipeline_digest("geometry"),
			FileAccess.get_sha256("res://core/lapidary/factory/geometry_plan.gd"),
			FileAccess.get_sha256("res://core/lapidary/factory/geometry_worker.gd")])
	return _source_digest

static func key(job: GemFrameJob, coverage_side: int) -> String:
	return GemContentIdentity.digest(["primary-geometry-v1", source_digest(),
		specimen_inputs(job.stone), job.resolution, GemFramePlan.canonical_orientation(job.orientation),
		job.ortho_half, job.camera_offset, coverage_side])

static func specimen_inputs(stone: GemStone) -> Dictionary:
	var defects := []
	if stone.condition != null:
		for defect in stone.condition.defects:
			if defect != null and defect.enabled:
				# Reflect all geometry descriptor fields so additions invalidate
				# existing companions. Finish and filling spectra are not geometry.
				var fields := {}
				for property: Dictionary in defect.get_property_list():
					var name: String = property.name
					if int(property.usage) & PROPERTY_USAGE_STORAGE == 0 or name in ["script", "resource_path", "resource_name", "resource_local_to_scene", "finish", "filling"] or name.begins_with("metadata/"):
						continue
					fields[name] = defect.get(name)
				# Presence/order of filled regions determines semantic material IDs.
				fields["filled"] = defect.filling != null
				defects.append(fields)
	return {"shape": stone.shape, "cut": stone.cut, "size_mm": stone.size_mm, "seed": stone.seed,
		"rounding":stone.condition.rounding if stone.condition!=null else null,
		"cleavage_crystal_frame": stone.crystal_to_stone if stone.condition != null and stone.condition.cleavage != null else null,
		"cleavage": stone.condition.cleavage.geometry_inputs() if stone.condition != null and stone.condition.cleavage != null else null,
		"workmanship": stone.condition.workmanship if stone.condition != null else null, "defects": defects}

static func validate(job: GemFrameJob, coverage_side: int) -> String:
	var error := GemJobValidator.validate(job)
	if not error.is_empty():
		return error
	if coverage_side not in [1, 2, 4, 8]:
		return "Geometry coverage side must be 1, 2, 4 or 8"
	if job.resolution.x * job.resolution.y * GemGeometryAov.STRIDE + 20 > GemArtifactStore.MAX_BLOB_BYTES:
		return "Geometry companion exceeds the artifact payload limit"
	var budget: int = job.quality.get("device_memory_budget_mib", 1024) * 1024 * 1024
	if job.resolution.x * job.resolution.y * (128 + GemGeometryAov.STRIDE) > budget:
		return "Geometry plus film buffers exceed the job's device memory budget"
	return ""

static func records_error(records: Variant) -> String:
	if not records is Dictionary:
		return "Geometry manifest records must be a dictionary"
	for id: Variant in records:
		if not id is String or not GemArtifactStore.valid_key(id) or not records[id] is Dictionary:
			return "Invalid geometry recipe identity"
		var record: Dictionary = records[id]
		if not GemArtifactStore.valid_key(str(record.get("engine", ""))):
			return "Geometry pipeline identity is missing or invalid"
		for field in ["width", "height", "coverage_side"]:
			var value: Variant = record.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)):
				return "Geometry dimensions and coverage must be integers"
		# JSON numbers arrive as floats; membership must follow the integer
		# validation above, not Variant-type-sensitive Array.has semantics.
		if record.width < 1 or record.height < 1 or record.width > 8192 or record.height > 8192 or record.width * record.height * GemGeometryAov.STRIDE + 20 > GemArtifactStore.MAX_BLOB_BYTES or int(record.coverage_side) not in [1, 2, 4, 8]:
			return "Geometry dimensions or coverage exceed supported bounds"
	return ""

static func references_error(manifest: Dictionary) -> String:
	var records: Variant = manifest.get("geometry", {})
	var error := records_error(records)
	if not error.is_empty():
		return error
	if not manifest.get("jobs") is Dictionary:
		return "Missing frame requests"
	for job: Variant in manifest.jobs.values():
		if not job is Dictionary:
			return "Invalid frame request"
		if job.has("geometry") and (not job.geometry is String or not records.has(job.geometry)):
			return "Frame refers to an absent geometry companion"
	return ""

static func payload_error(record: Dictionary, expected: Dictionary, engine: String) -> String:
	var metadata: Dictionary = record.get("metadata", {})
	if metadata.get("kind") != "primary_geometry" or metadata.get("engine") != engine or metadata.get("codec") != "gao1" or metadata.get("status") != "complete":
		return "Geometry kind, engine, codec or completion mismatch"
	for field in ["width", "height", "coverage_side"]:
		if metadata.get(field) != expected.get(field):
			return "Geometry dimensions/coverage differ from request"
	var decoded := GemGeometryAov.decode(record.get("payload", PackedByteArray()))
	if decoded == null or decoded.width != expected.width or decoded.height != expected.height or decoded.coverage_side != expected.coverage_side:
		return "Invalid geometry payload or decoded dimensions"
	return ""
