class_name LapidaryStoneCompiler
extends RefCounted
## Compiles a GemStone (species + chromophore + cut + grade + seed) into the
## StoneInstance dictionary consumed by the GPU kernel (see KERNEL_CONTRACT.md).
## This file owns the GRADE -> PHYSICS mapping. All randomness is a private
## deterministic hash sequence from the stone seed (never gameplay SeededRng).

const CUT_COMPILER_PATH := "res://core/lapidary/cut/cut_compiler.gd"
const MAX_INCLUSION_PRIMS := 64
const HULL_MARGIN := 0.07

## Fraunhofer lines for dispersion strength (B-G).
const WL_F := 486.1
const WL_C := 656.3


static func compile(stone: GemStone, cut_quality_override := -1.0) -> Dictionary:
	assert(stone != null and stone.species != null)
	var species := stone.species
	var grade := stone.grade if stone.grade != null else GemGrade.new()
	var cut_q := grade.cut if cut_quality_override < 0.0 else cut_quality_override
	var n_d := species.ior_at(589.3)

	var geometry := _compile_cut(stone, n_d, cut_q)

	var absorption := PackedFloat32Array()
	absorption.resize(81)
	if stone.chromophore != null and not stone.chromophore.is_colorless():
		var curve := stone.chromophore.absorption_mm
		for i in 81:
			absorption[i] = curve[i] * stone.chromophore.concentration
	var absorption_eray := PackedFloat32Array()
	if stone.chromophore != null and not stone.chromophore.absorption_eray_mm.is_empty():
		absorption_eray = stone.chromophore.absorption_eray_mm.duplicate()
		for i in absorption_eray.size():
			absorption_eray[i] *= stone.chromophore.concentration

	var rng_state := [int(stone.seed) * 2654435761 + 1013904223]

	return {
		"planes": geometry["planes"],
		"outline": geometry.get("outline", PackedVector2Array()),
		"inclusions": _place_inclusions(species, grade, geometry["planes"], stone.size_mm, rng_state),
		"absorption": absorption,
		"absorption_eray": absorption_eray,
		"sellmeier_b": species.sellmeier_b,
		"sellmeier_c": species.sellmeier_c_um2,
		"size_mm": stone.size_mm,
		"seed": stone.seed,
		"scatter": _crystal_to_scatter(species, grade),
		"zoning": _crystal_to_zoning(species, grade, rng_state),
		"wear": _surface_to_wear(species, grade),
		"birefringence": species.birefringence,
		"optic_axis": Vector3(0.31, 0.12, 0.94).normalized(),
		"fluorescence": _resolve_fluorescence(species, stone.chromophore),
		"dispersion_strong": dispersion_bg(species) >= 0.025,
		"fingerprint": stone.fingerprint(),
	}


static func dispersion_bg(species: GemSpecies) -> float:
	return species.ior_at(WL_F) - species.ior_at(WL_C)


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
	if ResourceLoader.exists(CUT_COMPILER_PATH):
		var compiler: GDScript = load(CUT_COMPILER_PATH)
		return compiler.call("compile", stone.cut, stone.silhouette, n_d, cut_q, stone.seed)
	# Fallback until the cut language lands: solved round brilliant.
	return {"planes": _fallback_brilliant(n_d, cut_q, stone.seed), "outline": PackedVector2Array()}


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


static func _fallback_brilliant(n_d: float, cut_q: float, seed: int) -> PackedFloat32Array:
	var planes := PackedFloat32Array()
	var g := 0.03
	var a_p := deg_to_rad(solve_pavilion_deg(n_d, cut_q))
	var a_c := deg_to_rad(lerpf(19.0, 34.5, cut_q))
	var table_ratio: float = clampf(0.56 * lerpf(1.25, 1.0, cut_q), 0.1, 0.9)
	var jitter := (1.0 - cut_q) * 0.035
	var state := [seed * 747796405 + 2891336453]

	var z_table := g + (1.0 - table_ratio) * tan(a_c)
	_plane(planes, Vector3(0, 0, 1), z_table, 0, 0.0)
	for i in 8:
		var phi := TAU * (float(i) + 0.5) / 8.0 + _rndf(state) * jitter
		var a := a_c + (_rndf(state) - 0.5) * jitter * 2.0
		_plane(planes, Vector3(sin(a) * cos(phi), sin(a) * sin(phi), cos(a)), sin(a) + cos(a) * g, 1, 0.0)
	var a_b := a_c + deg_to_rad(8.0)
	for i in 16:
		var phi := TAU * float(i) / 16.0 + _rndf(state) * jitter
		_plane(planes, Vector3(sin(a_b) * cos(phi), sin(a_b) * sin(phi), cos(a_b)), sin(a_b) + cos(a_b) * g, 2, 0.0)
	for i in 16:
		var phi := TAU * (float(i) + 0.5) / 16.0
		_plane(planes, Vector3(cos(phi), sin(phi), 0.0), 1.0, 3, 0.0)
	for i in 8:
		var phi := TAU * float(i) / 8.0 + _rndf(state) * jitter
		var a := a_p + (_rndf(state) - 0.5) * jitter * 2.0
		_plane(planes, Vector3(sin(a) * cos(phi), sin(a) * sin(phi), -cos(a)), sin(a) + cos(a) * g, 4, 0.0)
	var a_lb := a_p + deg_to_rad(6.0)
	for i in 16:
		var phi := TAU * (float(i) + 0.5) / 16.0 + _rndf(state) * jitter
		_plane(planes, Vector3(sin(a_lb) * cos(phi), sin(a_lb) * sin(phi), -cos(a_lb)), sin(a_lb) + cos(a_lb) * g, 5, 0.0)
	_plane(planes, Vector3(0, 0, -1), (tan(a_p) + g) * 0.96, 6, 0.0)
	return planes


static func _plane(arr: PackedFloat32Array, n: Vector3, d: float, zone: int, rough: float) -> void:
	var un := n.normalized()
	arr.append_array(PackedFloat32Array([un.x, un.y, un.z, d, float(zone), rough, 0.0, 0.0]))


# ------------------------------------------------------------------ grade axes

static func _crystal_to_scatter(species: GemSpecies, grade: GemGrade) -> Dictionary:
	# Tuned so a T1 (crystal ~0.4) stays translucent-milky: mean free path a bit
	# over the stone radius, 1-2 scatter events — windowing must stay legible.
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


## Hardness shapes wear statistics: soft minerals accumulate dense shallow
## scratches; hard minerals keep polish but show sparse deeper pits.
static func _surface_to_wear(species: GemSpecies, grade: GemGrade) -> Dictionary:
	var s := 1.0 - grade.surface
	var softness: float = clampf((9.0 - species.hardness_mohs) / 4.0, 0.0, 1.5)
	return {
		"roughness_boost": species.base_polish_roughness + pow(s, 1.6) * 0.12,
		"scratch_density": pow(s, 1.15) * (5.0 + 9.0 * softness),
		"scratch_aniso": 0.75,
		"abrasion": pow(s, 1.4) * 0.6 * softness,
		"dirt": maxf(0.0, s - 0.35) * 0.8,
		"edge_round": lerpf(0.010, 0.05, s),
	}


# ------------------------------------------------------------------ inclusions

static func _place_inclusions(species: GemSpecies, grade: GemGrade, planes: PackedFloat32Array,
		size_mm: float, state: Array) -> PackedFloat32Array:
	var prims := PackedFloat32Array()
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
			_prim(prims, pos, 1, axis, size, size / maxf(arch.aspect, 2.0), arch)
		GemInclusionArchetype.Form.CLOUD:
			_prim(prims, pos, 2, axis, size, size * 0.55, arch)
		GemInclusionArchetype.Form.CRYSTAL:
			_prim(prims, pos, 3, axis, size * 0.5, size * 0.5, arch)
		GemInclusionArchetype.Form.VEIL:
			# A veil reads as a warped sheet: several thin discs along a plane.
			var n := 4 + _rndi(state, 4)
			var t1 := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
			var t2 := axis.cross(t1)
			for i in n:
				var off := t1 * (_rndf(state) - 0.5) * size * 2.2 + t2 * (_rndf(state) - 0.5) * size * 2.2 \
					+ axis * (_rndf(state) - 0.5) * size * 0.35
				var wob := (axis + Vector3(_rndf(state) - 0.5, _rndf(state) - 0.5, _rndf(state) - 0.5) * 0.35).normalized()
				_prim(prims, pos + off, 1, wob, size * (0.35 + _rndf(state) * 0.4), size * 0.03, arch)
		GemInclusionArchetype.Form.FINGERPRINT:
			var n := 8 + _rndi(state, 6)
			var t1 := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
			var t2 := axis.cross(t1)
			for i in n:
				var ang := TAU * float(i) / float(n) + _rndf(state) * 0.3
				var ring_pos := pos + (t1 * cos(ang) + t2 * sin(ang)) * size
				_prim(prims, ring_pos, 2, axis, size * 0.12, size * 0.08, arch)


static func _prim(prims: PackedFloat32Array, pos: Vector3, type: int, axis: Vector3,
		r0: float, r1: float, arch: GemInclusionArchetype) -> void:
	prims.append_array(PackedFloat32Array([
		pos.x, pos.y, pos.z, float(type),
		axis.x, axis.y, axis.z, r0,
		r1, arch.scatter_density, arch.tint.r, arch.tint.g,
		arch.tint.b, 0.0, 0.0, 0.0,
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
