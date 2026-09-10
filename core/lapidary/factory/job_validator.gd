class_name GemJobValidator
extends RefCounted
## CPU admission for immutable jobs. Bounds are implementation limits, not a
## claim that an admitted specimen is measured or gemologically realistic.
const Cuts := preload("res://core/lapidary/cut/cut_compiler.gd")
const OUTLINES := [&"round", &"oval", &"square", &"triangle", &"diamond", &"rectangle", &"marquise", &"pear"]
const INTEGER_POLICY := {"res": Vector2(1, 8192), "out": Vector2(1, 8192), "spp": Vector2(1, 16777216),
	"batch": Vector2(1, 65536), "max_bounces": Vector2(1, 4096), "denoise_passes": Vector2(0, 5),
	"device_memory_budget_mib": Vector2(1, 1048576)}
const NUMBER_POLICY := {"denoise_phi": Vector2(0.1, 8), "throughput_epsilon": Vector2(1e-8, 0.01), "rad_clamp": Vector2(1e-12, 1e30)}
const BOOLEAN_POLICY := ["dispersion", "birefringence", "volume", "polarization", "crystal_transport"]

static func validate(job: GemFrameJob) -> String:
	if job == null:
		return "Job is missing"
	if job.samples < 1 or job.samples > 16777216:
		return "samples must be 1..16777216 (float32 accumulation limit)"
	for size in [job.resolution, job.output_size]:
		if size.x < 1 or size.y < 1 or size.x > 8192 or size.y > 8192:
			return "Frame dimensions must be 1..8192"
	if job.resolution.x * job.resolution.y * 16 + 64 > GemArtifactStore.MAX_BLOB_BYTES:
		return "Linear master exceeds the artifact payload limit"
	for key in job.quality:
		var value: Variant = job.quality[key]
		if INTEGER_POLICY.has(key):
			if not value is int or not _between(value, INTEGER_POLICY[key].x, INTEGER_POLICY[key].y):
				return "Invalid integer quality parameter: %s" % key
		elif NUMBER_POLICY.has(key):
			if not (value is int or value is float) or not _between(value, NUMBER_POLICY[key].x, NUMBER_POLICY[key].y):
				return "Invalid numeric quality parameter: %s" % key
		elif key in BOOLEAN_POLICY:
			if not value is bool:
				return "Quality parameter must be boolean: %s" % key
		elif key == "spectral_geometry":
			if value not in ["selective", "full"]:
				return "Unknown spectral_geometry mode"
		else:
			return "Unknown quality parameter: %s" % key
	var budget: int = job.quality.get("device_memory_budget_mib", 1024) * 1024 * 1024
	if job.resolution.x * job.resolution.y * 128 > budget:
		return "Estimated film buffers exceed the job's device memory budget"
	if not _rotation(job.orientation) or not _between(job.ortho_half, 1e-4, 10000) or not is_finite(job.rig_yaw):
		return "Camera needs a unit quaternion, finite yaw, and positive finite framing"
	for axis in 4:
		if not _between(job.role_multipliers[axis], 0, 1e10):
			return "Light role multipliers must be finite and nonnegative"
	if not _between(job.exposure, 0, 1e10):
		return "Exposure must be finite and nonnegative"
	var error := _stone(job.stone, job.quality.get("polarization", false))
	if not error.is_empty():
		return "Stone: " + error
	if job.quality.get("crystal_transport", false):
		if job.quality.get("polarization", false):
			return "Choose crystal transport or isotropic polarized transport"
		var why := GemCrystalAdmission.stone_error(job.stone)
		if not why.is_empty():
			return why
	error = _rig(job.rig)
	if not error.is_empty():
		return "Rig: " + error
	if job.print_style == null:
		return "Print is missing"
	return "; ".join(job.print_style.validate())

static func _stone(stone: GemStone, polarized: bool) -> String:
	if stone == null:
		return "missing specimen"
	if not _between(stone.size_mm, 1e-4, 10000) or not stone.optic_axis_override.is_finite() or not _rotation(stone.crystal_to_stone):
		return "invalid physical size, optic axis, or crystal frame"
	var error := _material(stone.material, polarized, stone.optic_axis_override)
	if not error.is_empty():
		return error
	if stone.grade != null:
		for axis in ["cut", "clarity", "surface", "crystal"]:
			if not _between(stone.grade.get(axis), 0, 1):
				return "grade.%s must be finite and in [0, 1]" % axis
	var shape := stone.shape
	if shape == null or shape.mode not in ["faceted", "cabochon", "loft"]:
		return "missing or unknown shape mode"
	if not _between(shape.aspect_ratio, 0.2, 8) or not _between(shape.corner_radius, 0, 0.45) or not _between(shape.sectors, 3, 128):
		return "invalid outline proportions or sector count"
	if not _between(shape.radial_segments, 8, 512) or not _between(shape.dome_rings, 4, 128) or not _between(shape.dome_height, 0.01, 3):
		return "invalid curved shape resolution or dome height"
	if shape.outline_points.is_empty() and shape.outline not in OUTLINES:
		return "unknown outline"
	if shape.outline_points.size() > 512 or shape.loft_sections.size() > 256:
		return "shape exceeds the procedural tessellation limits"
	if shape.mode == "faceted":
		if not shape.outline_points.is_empty():
			return "custom polygon outlines require loft mode"
		if not stone.cut is GemCutTemplate:
			return "faceted jobs require an explicit GemCutTemplate"
		error = Cuts.template_error(stone.cut)
		if not error.is_empty():
			return "cut: " + error
	else:
		# Reuse the topology implementation, including simple CCW polygon checks.
		var mesh := GemShapeCompiler.compile(shape)
		if not mesh.validate().is_empty():
			return "invalid procedural shape topology: %s" % mesh.validate()
	var condition := stone.condition
	if condition != null and not condition.validate_volume_fields().is_empty():
		return "; ".join(condition.validate_volume_fields())
	if polarized:
		var bulk := GemMaterialCompiler.compile(stone.material)
		bulk["volume_fields"] = condition.volume_fields if condition != null else []
		bulk["zoning"] = condition.banding.normalized(stone.size_mm) if condition != null and condition.banding != null else {}
		bulk["optic_axis"] = stone.resolved_optic_axis()
		error = GemMaterialCompiler.polarization_error(bulk)
		if not error.is_empty():
			return error
	if condition == null:
		return ""
	if condition.workmanship != null and not condition.workmanship.validate().is_empty():
		return "; ".join(condition.workmanship.validate())
	if condition.finish != null and not condition.finish.validate().is_empty():
		return "; ".join(condition.finish.validate())
	var descriptors: Array[GemDefect] = condition.defects.duplicate()
	if condition.cleavage != null:
		var event := GemCleavageCompiler.realize(LapidaryStoneCompiler.compile_geometry(stone),stone.shape,stone.size_mm,condition.cleavage,stone.crystal_to_stone)
		if not event.error.is_empty():
			return event.error
		if event.has("defect"):
			descriptors.append(event.defect)
	var count := 0
	var combined := GemMesh.new()
	for defect in descriptors:
		if defect == null:
			return "missing defect descriptor"
		if not defect.enabled:
			continue
		if defect.kind not in ["fracture", "chip", "crystal", "cleavage"] or not defect.center_mm.is_finite() or not _rotation(defect.orientation):
			return "invalid defect kind, center, or orientation"
		for axis in 3:
			if not _between(defect.half_extent_mm[axis], 1e-6, 10000):
				return "defect half-extents must be finite and positive"
		if not _between(defect.irregularity, 0, 1) or not _between(defect.radial_segments, 8, 128) or not _between(defect.radial_rings, 2, 32):
			return "invalid defect irregularity or tessellation"
		if defect.finish != null and not defect.finish.validate().is_empty():
			return "; ".join(defect.finish.validate())
		if defect.kind == "fracture" and (defect.fracture_profile == null or not defect.fracture_profile.validate().is_empty()):
			return "fracture needs a valid aperture/contact profile"
		if defect.filling != null:
			error = _material(defect.filling, polarized)
			if not error.is_empty():
				return "defect filling: " + error
		var mesh := GemDefectCompiler.compile(defect, stone.size_mm)
		if defect.kind == "fracture" and mesh.vertices.is_empty():
			continue # Fully closed, validated aperture: no optical region remains.
		count += 1
		if count >= GemBoundarySet.MAX_REGIONS:
			return "too many physical defect regions"
		if not mesh.validate().is_empty():
			return "defect geometry invalid at the requested physical scale: %s" % mesh.validate()
		combined.append_region(mesh, count)
	if count > 0:
		var geometry := LapidaryStoneCompiler.compile_geometry(stone)
		if not geometry.has("analytic_shape"):
			var host: GemMesh = geometry.get("mesh", null)
			if host == null:
				host = GemShapeCompiler.from_hull(geometry.planes, geometry.get("facet_ids", PackedInt32Array()))
			if not host.validate().is_empty():
				return "invalid host boundary: %s" % host.validate()
			combined.append_region(host, 0)
		var errors := combined.validate()
		if not errors.is_empty():
			return "invalid combined region boundaries: %s" % errors
	return ""

static func _material(material: GemMaterial, polarized: bool, axis_override := Vector3.ZERO) -> String:
	if material == null:
		return "missing material"
	var errors := material.validate()
	if not errors.is_empty():
		return "; ".join(errors)
	if polarized:
		var bulk := GemMaterialCompiler.compile(material)
		if axis_override != Vector3.ZERO:
			bulk["optic_axis"] = axis_override
		return GemMaterialCompiler.polarization_error(bulk)
	return ""

static func _rig(rig: GemLightRig) -> String:
	if rig == null:
		return "missing light rig"
	for value in [rig.bg_zenith, rig.bg_horizon, rig.bg_below]:
		if not _between(value, 0, 1e10):
			return "background radiance must be finite and nonnegative"
	var error := GemSpectrumCompiler.validate(rig.background_spectrum)
	if not error.is_empty():
		return "background: " + error
	var count := 0
	for light in rig.lights:
		if light == null:
			return "missing light descriptor"
		if not light.enabled:
			continue
		count += 1
		if count > GemTracer.MAX_LIGHTS:
			return "too many lights"
		if light.role < 0 or light.role > 4 or not is_finite(light.azimuth_deg) or not is_finite(light.elevation_deg):
			return "invalid light role or direction"
		if not _between(light.angular_radius_deg, 0.001, 180) or not _between(light.inner_fraction, 0.05, 0.98) or not _between(light.power, 0, 1e10):
			return "invalid light cone or power"
		if light.role == GemRigLight.Role.BLOCKER and light.power > 1:
			return "blocker strength must be in [0, 1]"
		error = GemSpectrumCompiler.validate(light.spectrum)
		if not error.is_empty():
			return "light spectrum: " + error
	if rig.white_spectrum != null:
		error = GemSpectrumCompiler.validate(rig.white_spectrum)
		if not error.is_empty():
			return "white spectrum: " + error
		if GemColorimetry.spectrum_xyz(GemSpectrumCompiler.compile(rig.white_spectrum)).y <= 0:
			return "white spectrum requires visible energy"
	return ""

static func _between(value: float, low: float, high: float) -> bool:
	return is_finite(value) and value >= low and value <= high

static func _rotation(value: Quaternion) -> bool:
	return value.is_finite() and absf(value.length_squared() - 1.0) < 1e-4
