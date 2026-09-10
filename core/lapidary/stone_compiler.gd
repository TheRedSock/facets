class_name LapidaryStoneCompiler
extends RefCounted
## Compiles a GemStone (species + chromophore + cut + grade + seed) into the
## StoneInstance dictionary consumed by the GPU kernel (see KERNEL_CONTRACT.md).
## This file owns the GRADE -> PHYSICS mapping. All randomness is a private
## deterministic hash sequence from the stone seed (never gameplay SeededRng).
##
## Grade axes consumed: cut (geometry), crystal (milk, zoning). The `surface`
## axis has NO kernel effect (wear model removed; clean-optics baseline).
## `clarity` is data only while INCLUSIONS_ENABLED is false — the primitive
## placer is gated so the kernel never sees needles / lily pads / clouds.
## Flip the const when the inclusion look is ready to re-assess.

const CUT_COMPILER_PATH := "res://core/lapidary/cut/cut_compiler.gd"
## Temporary clean-optics gate. Species vocabularies and grade.clarity stay
## authored; nothing is packed into the kernel until this is true again.
const INCLUSIONS_ENABLED := false
const MAX_INCLUSION_PRIMS := 64
const HULL_MARGIN := 0.07

## Fraunhofer lines for dispersion strength (B-G).
const WL_F := 486.1
const WL_C := 656.3


static func compile(stone: GemStone, cut_quality_override := -1.0) -> Dictionary:
	assert(stone != null and stone.material.species != null)
	var species := stone.material.species
	var grade := stone.grade if stone.grade != null else GemGrade.new()
	var cut_q := grade.cut if cut_quality_override < 0.0 else cut_quality_override
	var n_d := species.ior_at(589.3)

	var geometry := _compile_cut(stone, n_d, cut_q)

	var bulk := GemMaterialCompiler.compile(stone.material)
	var rng_state := [int(stone.seed) * 2654435761 + 1013904223]
	
	var compiled := {
		"planes": geometry["planes"],
		"facet_ids": geometry.get("facet_ids", PackedInt32Array()),
		"outline": geometry.get("outline", PackedVector2Array()),
		"inclusions": _place_inclusions(species, grade, geometry["planes"], stone.size_mm, rng_state),
		"absorption": bulk["absorption"],
		"absorption_eray": bulk["absorption_eray"],
		"sellmeier_b": species.sellmeier_b,
		"sellmeier_c": species.sellmeier_c_um2,
		"size_mm": stone.size_mm,
		"seed": stone.seed,
		"scatter": bulk["scatter"] if stone.material.scatter_per_mm >= 0.0 else _crystal_to_scatter(species, grade),
		"zoning": _crystal_to_zoning(species, grade, rng_state),
		"birefringence": bulk["birefringence"],
		"optic_axis": _resolve_optic_axis(stone).normalized(),
		"fluorescence": _resolve_fluorescence(species, stone.material.chromophore),
		"dispersion_strong": dispersion_bg(species) >= 0.025,
		"fingerprint": stone.fingerprint(),
	}
	if geometry.has("mesh"):
		compiled["mesh"] = geometry["mesh"]
	if geometry.has("analytic_shape"):
		compiled["analytic_shape"] = geometry["analytic_shape"]
	GemDefectCompiler.apply(compiled, stone.condition, stone.size_mm)
	return compiled


static func dispersion_bg(species: GemSpecies) -> float:
	return species.ior_at(WL_F) - species.ior_at(WL_C)


static func _resolve_optic_axis(stone: GemStone) -> Vector3:
	if stone.optic_axis_override != Vector3.ZERO:
		return stone.optic_axis_override
	return stone.material.species.optic_axis_stone


## Fluorescence is chromophore-gated: the glow comes from the coloring ion
## (Cr3+), and co-impurities quench it (Fe in blue sapphire).
static func _resolve_fluorescence(species: GemSpecies, chromo: GemChromophore) -> Dictionary:
	var nm := species.fluorescence_emission_nm
	var strength := species.fluorescence_strength
	if chromo != null:
		if chromo.fluorescence_strength_override >= 0.0:
			strength = chromo.fluorescence_strength_override
		if chromo.fluorescence_emission_nm_override > 0.0:
			nm = chromo.fluorescence_emission_nm_override
	return {"nm": nm, "strength": strength}


# ------------------------------------------------------------------ cut

static func _compile_cut(stone: GemStone, n_d: float, cut_q: float) -> Dictionary:
	if stone.shape.mode == "cabochon" and stone.shape.outline in [&"round", &"oval"] and stone.shape.outline_points.is_empty():
		return {"planes": PackedFloat32Array(), "outline": GemShapeCompiler.outline(stone.shape),
			"analytic_shape": Vector4(1.0, 1.0 / stone.shape.aspect_ratio, stone.shape.dome_height, -0.04)}
	if stone.shape.mode != "faceted":
		var mesh := GemShapeCompiler.compile(stone.shape)
		assert(mesh.validate().is_empty(), "Invalid procedural shape: %s" % mesh.validate())
		return {"planes": PackedFloat32Array(), "mesh": mesh, "outline": GemShapeCompiler.outline(stone.shape)}
	assert(ResourceLoader.exists(CUT_COMPILER_PATH),
		"LapidaryStoneCompiler: cut compiler missing at %s" % CUT_COMPILER_PATH)
	var compiler: GDScript = load(CUT_COMPILER_PATH)
	return compiler.call("compile", stone.cut, stone.shape.outline, n_d, cut_q, stone.seed, stone.shape)


## Pavilion law v2 (re-derived from the prototype's solver):
##   critical = asin(1/n); optimal = 45 - (n - 1) * 3 (empirical lapidary fit)
##   window target = critical - 6 deg (light leaks face-up), floored at 16 deg.
##   No hard [38,48] clamp: low-critical minerals (diamond) window weakly,
##   which is physically true — their grade must read via other axes too.
static func solve_pavilion_deg(n_d: float, cut_q: float) -> float:
	var critical_deg := rad_to_deg(asin(1.0 / maxf(n_d, 1.0001)))
	var optimal := 45.0 - (n_d - 1.0) * 3.0
	var windowed := maxf(critical_deg - 6.0, 16.0)
	return lerpf(windowed, optimal, clampf(cut_q, 0.0, 1.0))


# ------------------------------------------------------------------ grade axes

static func _crystal_to_scatter(species: GemSpecies, grade: GemGrade) -> Dictionary:
	# T1 crystal ~0.66: translucent, not milky-white. Mean free path stays
	# longer than the stone; windowing remains legible.
	var haze := pow(1.0 - grade.crystal, 1.6) * 0.40
	return {
		"sigma_per_mm": species.base_scatter_per_mm + haze,
		"g": species.scatter_anisotropy_g,
	}


static func _crystal_to_zoning(species: GemSpecies, grade: GemGrade, state: Array) -> Dictionary:
	return {
		"axis": species.zoning_axis.normalized(),
		"frequency": species.zoning_frequency,
		"contrast": species.zoning_contrast * (1.0 - grade.crystal),
		"phase": _rndf(state) * TAU,
	}


# ------------------------------------------------------------------ inclusions

static func _place_inclusions(species: GemSpecies, grade: GemGrade, planes: PackedFloat32Array,
		size_mm: float, state: Array) -> PackedFloat32Array:
	var prims := PackedFloat32Array()
	if not INCLUSIONS_ENABLED:
		return prims
	if species.inclusions.is_empty() or grade.clarity >= 0.985:
		return prims
	var dirt := 1.0 - grade.clarity
	var budget := mini(int(round(pow(dirt, 1.25) * 26.0)), MAX_INCLUSION_PRIMS)
	if budget <= 0:
		return prims

	var total_weight := 0.0
	for arch in species.inclusions:
		total_weight += arch.weight
	var placed := 0
	var guard := 0
	while placed < budget and guard < budget * 30:
		guard += 1
		var pick := _rndf(state) * total_weight
		var arch: GemInclusionArchetype = species.inclusions[0]
		for a in species.inclusions:
			pick -= a.weight
			if pick <= 0.0:
				arch = a
				break
		var pos := _sample_inside_hull(planes, arch.center_bias, state)
		if pos == Vector3.INF:
			continue
		var size_stone: float = lerpf(arch.size_mm_range.x, arch.size_mm_range.y,
			pow(_rndf(state), 1.5 - 0.9 * dirt)) / size_mm
		var axis := _pick_axis(arch, state)
		var count_before := prims.size()
		_emit_primitives(prims, arch, pos, axis, size_stone, state)
		placed += (prims.size() - count_before) / 16
	return prims


static func _pick_axis(arch: GemInclusionArchetype, state: Array) -> Vector3:
	if not arch.orientation_axes.is_empty():
		var base: Vector3 = arch.orientation_axes[_rndi(state, arch.orientation_axes.size())]
		var wobble := Vector3(_rndf(state) - 0.5, _rndf(state) - 0.5, _rndf(state) - 0.5) * 0.12
		return (base + wobble).normalized()
	var v := Vector3(_rndf(state) * 2.0 - 1.0, _rndf(state) * 2.0 - 1.0, _rndf(state) * 2.0 - 1.0)
	return v.normalized() if v.length() > 0.01 else Vector3.UP


static func _emit_primitives(prims: PackedFloat32Array, arch: GemInclusionArchetype,
		pos: Vector3, axis: Vector3, size: float, state: Array) -> void:
	match arch.form:
		GemInclusionArchetype.Form.NEEDLE:
			# Radius floor ~1px at sprite scale: real silk is subpixel-fine, but
			# at 112px it must still read (scale-honest exaggeration, documented).
			_prim(prims, pos, 0, axis, size, maxf(size / maxf(arch.aspect, 2.0), 0.012), arch)
		GemInclusionArchetype.Form.PLATELET:
			# Lily-pad disc: kernel draws an annulus. Cap so a 112px sprite
			# does not grow table-facing coins. Olivine cleavage is not only +Z.
			var pad := minf(size, 0.07)
			_prim(prims, pos, 1, axis, pad, pad / maxf(arch.aspect, 2.0), arch, 0.0)
		GemInclusionArchetype.Form.CLOUD:
			# Milk is the homogeneous σ_s field. Cloud prims are local wisps,
			# not millimetre potatoes (those read as oval stickers at 112px).
			var major := minf(size, 0.055)
			_prim(prims, pos, 2, axis, major, major * 0.62, arch)
		GemInclusionArchetype.Form.CRYSTAL:
			# Pinpoint, not a resolved sphere. 0.016 stone-units ≈ 2px at 112.
			var rad := minf(size * 0.5, 0.016)
			_prim(prims, pos, 3, axis, rad, rad, arch)
		GemInclusionArchetype.Form.VEIL:
			# Healed-fracture sheet: a few irregular discs, kernel style=1.
			var n := 2 + _rndi(state, 3)
			var t1 := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
			var t2 := axis.cross(t1)
			for i in n:
				var off := t1 * (_rndf(state) - 0.5) * size * 2.2 + t2 * (_rndf(state) - 0.5) * size * 2.2 \
					+ axis * (_rndf(state) - 0.5) * size * 0.35
				var wob := (axis + Vector3(_rndf(state) - 0.5, _rndf(state) - 0.5, _rndf(state) - 0.5) * 0.35).normalized()
				_prim(prims, pos + off, 1, wob, size * (0.40 + _rndf(state) * 0.45), size * 0.03, arch, 1.0)
		GemInclusionArchetype.Form.FINGERPRINT:
			var n := 8 + _rndi(state, 6)
			var t1 := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
			var t2 := axis.cross(t1)
			for i in n:
				var ang := TAU * float(i) / float(n) + _rndf(state) * 0.3
				var ring_pos := pos + (t1 * cos(ang) + t2 * sin(ang)) * size
				_prim(prims, ring_pos, 2, axis, size * 0.07, size * 0.045, arch)


static func _prim(prims: PackedFloat32Array, pos: Vector3, type: int, axis: Vector3,
		r0: float, r1: float, arch: GemInclusionArchetype, style := 0.0) -> void:
	prims.append_array(PackedFloat32Array([
		pos.x, pos.y, pos.z, float(type),
		axis.x, axis.y, axis.z, r0,
		r1, arch.scatter_density, arch.tint.r, arch.tint.g,
		arch.tint.b, 0.0, style, 0.0,
	]))


static func _sample_inside_hull(planes: PackedFloat32Array, center_bias: float, state: Array) -> Vector3:
	var plane_count := planes.size() / 8
	for attempt in 24:
		var p := Vector3(_rndf(state) * 2.0 - 1.0, _rndf(state) * 2.0 - 1.0, _rndf(state) * 1.6 - 0.9)
		p *= lerpf(1.0, 0.45, center_bias)
		var inside := true
		for i in plane_count:
			var n := Vector3(planes[i * 8], planes[i * 8 + 1], planes[i * 8 + 2])
			if n.dot(p) > planes[i * 8 + 3] - HULL_MARGIN:
				inside = false
				break
		if inside:
			return p
	return Vector3.INF


# ------------------------------------------------------------------ deterministic hash RNG

static func _rndi(state: Array, n: int) -> int:
	return int(_rndf(state) * float(n)) % n


static func _rndf(state: Array) -> float:
	var s: int = (int(state[0]) * 747796405 + 2891336453) & 0xFFFFFFFF
	state[0] = s
	var word: int = (((s >> ((s >> 28) + 4)) ^ s) * 277803737) & 0xFFFFFFFF
	return float(((word >> 22) ^ word) & 0xFFFFF) / 1048576.0
