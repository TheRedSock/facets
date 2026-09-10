# Lapidary Kernel Contract (v8 — physical surface finishes and nested material boundaries)

The single interface between the data model and the GPU tracer. Everything that
renders — designer preview, clip bake, live board draws, evaluation sheets —
goes through these buffers. Anything not expressible here does not exist visually.

All buffers are std430 float32 unless noted. Stone space: girdle plane at z=0,
crown toward +Z, unit girdle radius. Camera: orthographic, world space, looking
down −Z; the stone quaternion rotates stone→world.

## Plane (8 floats) — the stone body, intersection of half-spaces
| idx | field | notes |
|---|---|---|
| 0–2 | outward unit normal (stone space) | |
| 3 | d — plane offset (`dot(n,x) <= d` is inside) | |
| 4 | zone id | 0 table, 1 crown main/star, 2 upper girdle, 3 girdle, 4 pavilion main, 5 lower girdle, 6 culet, 7 step row (compiler metadata; finish is a separate boundary property) |
| 5–7 | reserved | |

The hull MUST be bounded (compiler responsibility). Facet-meeting error may perturb the plane program. Faceted bodies may keep the
convex backend or compile to a shared, closed triangle surface. Lofted and
cabochon recipes use the triangle backend; concavity is supported.


## Procedural triangle backend

`GemShape` separates outline, aspect and profile from the cut program. Faceted
plane conversion preserves source facet IDs and welds canonical plane intersections.
`GemMesh` stores indexed outward-oriented closed surfaces; validation checks finite
coordinates, indices, nondegeneracy, edge incidence/orientation and positive volume.
It does not yet certify arbitrary global self-intersections.

Triangle (64B): vec4 a, b, c (xyz vertices, w reserved), ivec4 metadata
(facet ID, reserved, reserved, region ID). Region IDs are local to each specimen.
Binding13 contains int32 material indices, addressed by Stone.ranges1.w + region.
Index -1 means air, otherwise it addresses the shared Stones material array.
Host material records are first (one per authored instance), then nested materials.
Each ray tracks up to128 active closed regions in a uvec4. Region0 is the host;
all other regions are clipped to it. The highest active region overrides lower
ones. Overlapping voids therefore subtract their union; a higher filled region
can override a cavity. Coincident boundaries are unsupported: use overlap or a
finite gap. Subpixel populations should use effective media, not unbounded regions.
Node (48B): vec4 low/high bounds, ivec4 left/right/first/count. Count=0 denotes
an internal node. Child and triangle indices are absolute in their shared buffers.
The deterministic median BVH has four triangles per leaf; GPU traversal stack=64.
Stone `ranges1.z=0` selects planes, otherwise it is the BVH root index plus one.

General transport tracks air/host segments and handles external re-entry.
Deterministic Fresnel escape splitting is only used after visibility proves a
branch reaches the environment; coupled branches use weighted roulette. Curved
surfaces currently use geometric triangle normals; tessellation can be visible in
sharp highlights. Nested absorption/scattering and relative-index dielectric interfaces are supported.
Rough interfaces use the surface model below. Mathematical region boundaries that do not
change material are skipped for visibility and coverage. Transport still processes
their segments to preserve optical length and scattering state.

## Light (8 floats) — analytic rig, world space
| idx | field |
|---|---|
| 0–2 | direction TOWARD the light |
| 3 | cos(outer angular radius) |
| 4 | kelvin (Planck-relative SPD, normalized at 560 nm) |
| 5 | power (BLOCKER: darkening strength 0..1) |
| 6 | cos(inner radius) |
| 7 | role: 0 key, 1 fill, 2 rim, 3 bounce, 4 blocker |

`GemRigCompiler.pack()` is the only packer. The shader indexes per-role power
multipliers by this role field (not by buffer index).

## Boundary surface finish (32 bytes, binding14)
Each region has one record at the same offset as binding13. Two vec4s contain
GGX alpha_u/alpha_v/reserved/reserved and object-space polish direction.xyz/reserved.
The direction is projected onto the geometric tangent plane at the actual hit.
`GemSurface` is independent of the bulk material: a cavity wall, a filled inclusion
and the host can have different finishes. Zero slopes select a perfect interface.

Visible-normal GGX sampling and correlated Smith masking use consistent reflection
and transmission weights (G2/G1 after proposal cancellation). Radiance transmission
includes the squared incident/transmitted index ratio. Macroscopic hemisphere tests
reject invalid sampled branches. Index-matched boundaries ignore finish entirely.
The single-scattering microfacet model is accepted only as a light-polish foundation;
strong frosting loses unresolved microfacet multiple scattering and is not enabled
in automatic grade recipes. Furnace and directional checks: tools/surface_check.gd.

The nonphysical inclusion primitive backend has been removed. Binding4 and Stone
ranges0.zw are unassigned. Explicit geometry/material regions replace its fake discs,
RGB-tinted clouds, and density-derived reflection probabilities.

## Stone struct (128 bytes, std430 — array `Stones`, one per distinct stone)
| vec4 | contents |
|---|---|
| 0 | sellmeier_b.xyz, size_mm |
| 1 | sellmeier_c_um2.xyz, signed birefringence Δn |
| 2 | scatter σ_s/mm, HG g, zoning frequency, zoning contrast |
| 3 | zoning axis.xyz, zoning phase |
| 4 | optic axis.xyz, fluorescence strength |
| 5 | fluorescence nm (disabled), absorb_scale, nested_volume_present, rough_present |
| ivec4 6 | plane_offset, plane_count, reserved, reserved |
| ivec4 7 | absorb_offset, stone_flags (bit0 has_eray, bit1 dispersion_strong), bvh_root_plus_one, region_offset |

Explicit surface condition reaches the kernel through binding14. Automatic scalar
clarity/surface grade mapping is still disabled; cut/crystal remain legacy recipes.

Absorption buffer: concatenated 81-sample blocks (α/mm, 380–780 @ 5 nm, concentration
applied). If `has_eray`, the e-ray block directly follows the o-ray block (offset+81).

Polarisation (GIA G&G Spring 2021): with `c2 = cos²(φ)` for angle φ between ray and
optic axis, `α_k = c2 α_o + (1-c2) α_e`. Unpolarised stones use `0.5 T_o + 0.5 T_k`.
Birefringent fork (rung + |Δn| > 0.015): o-pass uses α_o, e-pass uses α_k. Index of
the e-pass uses the indicatrix: `1/n_e(φ)² = c2/n_o² + (1-c2)/n_e²`.

## Instance struct (64 bytes — array `Insts`, one per grid cell)
| vec4 | contents |
|---|---|
| 0 | stone→world quaternion |
| 1 | rig_yaw (radians), ortho_half, key_mult, fill_mult |
| 2 | rim_mult, bounce_mult, camera_distance, 0 |
| ivec4 3 | stone_index, 0, 0, 0 |

Pixels map to instances via an equal-cell grid (push constants `grid`, `cell_px`);
grid 1×1 = single stone.

## Bindings (set 0)
0 Planes, 1 Lights, 2 Absorb, 3 Accum (vec4 XYZ+coverage), 4 unassigned, 5 Stones, 6 Insts,
7 legacy scatter field (`image3D` in pre-pass, `sampler3D` in trace; production policies disable it).
Trace-only bindings: 8 guides (two vec4 per pixel: normal/depth sums, residual Y squared/Y sum/min-max facet IDs), 9 zero-scatter XYZ/coverage sums, 10 residual XYZ/coverage sums, 11 triangles, 12 BVH nodes, 13 region-to-material indices, 14 boundary finishes.

Reconstruction (`gem_denoise.glsl`) uses bindings 0 input sums, 1 guides, 2 output sums, 3 zero-scatter sums. Push constants (32B): resolution ivec2, step int, sample count float, phi float, normal exponent float, vec2 padding. Step zero composites filtered residual with untouched zero-scatter light for smooth hosts. Rough boundaries instead reconstruct the entire stochastic signal; their ballistic buffer is zero. Other steps run positive, variance/normal-guided a-trous filtering. Coverage is never filtered. This is a biased optional reconstruction; `read_xyz` and `read_linear_master` always expose the unchanged reference accumulation.

Kernel push constants (96 B): resolution, sample_base, spp, seed, max_bounces, flags
(bit0 dispersion_split, bit1 birefringence approximation, bit2 volume, bit4 reserved, bit5 full wavelength geometry),
light_count, grid, cell_px, bg zenith/horizon/below, spectral_norm, rad_clamp,
env_filter_rad, field_exits, field_grid, row_origin, field_insts, bg_kelvin, throughput_epsilon.

Scatter-field push constants (48 B): grid_n, field_exits, light_count, inst_count,
dirs, band_group, env_filter_rad, texel_base, bg (zenith, horizon, below, kelvin).

Print push constants (112 B): output resolution, inv_samples, exposure, raw, white_point,
contrast, black_point, chroma_ceiling, chroma_soft, highlight_desat, pad, then the
XYZ→linear-sRGB matrix as three vec4 columns (includes the rig's as-shot white
balance, see below), then source resolution (ivec2) and padding (ivec2).
The print resolves coverage-associated linear XYZ over each output pixel's source
footprint, divides XYZ by covered sample weight, then applies the display transform.
The output is straight sRGB RGBA8. `read_linear_master()` returns associated XYZ
and coverage as RGBAF without any display transform.

## Environment
`env_radiance_ex(dir, wl, rig_yaw, role_mult, fp, with_lights, bg, light_count)`
(gem_common.glsl) is the one analytic rig evaluator, shared by the kernel and the
scatter-field pre-pass. Background = zenith/horizon/below gradient; its spectrum is
Planckian at `bg.w` kelvin (flat when 0). Lights are Planck-relative cones widened by
the footprint `fp` (flux-conserving `R² / (R² + fp²)` — the same cone_omega formula
on both sides). Blockers multiply everything in their cone by `1 - power·w`.

`GemRigCompiler.environment(rig)` → `{bg: Vector4, white_kelvin}` feeds
`GemTracer.set_environment()`. `white_kelvin` is the rig's as-shot neutral: the host
builds Bradford(CAT) from that Planckian white to D65 (`core/lapidary/lighting/
colorimetry.gd`, same CIE fit as the shaders) and folds it into the print matrix, so a
colourless stone under the rig's dominant light prints white and every other light
keeps its relative warmth. Exposure is the house print's `exposure` only — tools and
bakes pass 1.0.

## Estimator (v4)
- Global sample index `n = sample_base + s` drives per-pixel Cranley-Patterson-rotated
  Halton for pixel filter, wavelength, unified free flight + medium choice, and the
  first scatter direction (field-off only). PCG covers remaining dimensions.
- Deterministic Fresnel split at every interior surface: the transmitted branch
  evaluates the environment immediately, the reflected/TIR branch continues.
  The first inclusion surface hit splits deterministically too.
- Angular footprint `fp` (radians) grows with the orthographic pixel footprint and
  the path's divergence; the environment cones are widened by it.
- Volume: repeated sampled scatter events per path (homogeneous milk + cloud primitives,
  unified free flight). With `field_exits > 0` the scattered radiance is read from
  the SH scatter field (l ≤ 3, 16 × 25 nm bands, HG convolution `g^l`), and the
  path ends: the field is the whole continuation. `field_exits = 0` keeps the
  stochastic HG continuation with a fresh exponential free flight after each event.
  The reference includes multiple scattering; the current field remains an
  approximation under evaluation. After a
  scatter, the environment footprint floor is `env_filter_rad` on both sides.
- Scatter field pre-pass (`gem_scatter_field.glsl`): per texel of a
  `field_grid³` lattice over `[-1.25, 1.25]³` stone space, `field_dirs` Fibonacci
  directions each traced through the Fresnel chain for `field_exits` hull hits with
  Beer-Lambert absorption (no extinction by σ_s: higher orders are delivered
  forward, matching the kernel). Rebuilt whenever orientation, rig, background or
  stone set changes; the host chunks it (4 bands × texel ranges) for TDR safety.

## Rung flags (engineering policy — `core/lapidary/tracer/rung.gd`)
dispersion_split (per-λ paths), birefringence fork, volume, max_bounces, spp per
dispatch (`batch`), internal resolution → output size, rad_clamp, env_filter_rad,
field_exits / field_grid / field_dirs. Denoise always off.

## Clip sample (what a render call receives)
time_norm, stone quaternion (rest ∘ motion), rig yaw (radians), per-role power
multipliers (vec4: key, fill, rim, bounce), effect values (exposure_pulse),
camera ortho half-width.

## Host API (`gem_tracer.gd`)
`create(w, h, rd=null)` → tracer (null in headless).
Full path: `configure_stone(instance, lights, policy)` /
`configure_stones(instances, lights, policy, grid)` where `instance` is
`LapidaryStoneCompiler.compile()` output and `policy` is `GemRung.policy()`.
Per-frame: `set_stone_orientation(q)`, `set_clip_sample(q, rig_yaw, role_mult,
ortho_half)`, `set_instances(states)` (batch), `set_environment(env)` (from
`GemRigCompiler.environment(rig)`), `set_seed(s)`.
Dispatch: `accumulate(spp) -> ms` (adaptive TDR-safe chunking; rebuilds the scatter
field first when dirty), `build_scatter_field() -> ms`, `reset_accumulation()`.
Output: `finalize_print(print: GemPrint, raw := false, exposure := 1.0)`
(GPU print pass; house print via `GemPrint.load_house()`), `read_xyz()` (physics tests).
`release()` frees GPU resources.

## Determinism contract
Seeded QMC + PCG from (pixel, frame, stone seed). Reproducible on the same GPU
family + driver. NOT bit-exact across vendors — cache keys carry
`look_version`; foreign caches regenerate. Physics tests assert with
tolerances, never bit equality.

Production policies use repeated scattering with no post-scatter environment blur. Full spectral geometry splits all four sampled wavelengths, not just high-dispersion species. `REFERENCE` is unfiltered but does not cure the still-approximate anisotropic model. Fluorescence is not rendered. `accumulate()` returns total wall time including any field work; `profile()` separates trace, field, reconstruction, and print/readback.

## Authoring boundary
`GemMaterial` owns reusable species/chromophore and optional bulk scattering.
`GemShape` owns outline/profile/cut-independent dimensions. `GemCondition` owns
realized millimeter-scale `GemDefect` boundaries. The old `GemGrade` remains a
catalog recipe for cut proportions and haze, not a physical or gemological grade.
Automatic clarity/surface recipes remain disabled. Explicit chip/fracture/crystal
boundaries can be authored and filled with another GemMaterial. Their morphology
is procedural, not a stress or crystal-growth simulation; current fractures have
not passed low-SPP visual acceptance. Surface polish fields are not yet rendered.

## Analytic curved hosts (v7)
Round/oval cabochons use exact-form ellipsoid, elliptical girdle cylinder and flat
base intersections. Stone.ranges0.y=-1 identifies an analytic host; the Plane
record at ranges0.x is a tagged geometry parameter block: n_d=(x radius, y radius,
dome height, base z<0), aux reserved. ranges1.z=-1 denotes no mesh BVH; positive
values allow the same analytic host plus mesh defect regions. The analytic host
is region0, and the shared priority medium state also handles its cavities and
fillings. General boundary surface IDs are negative for analytic patches (-1
dome, -2 girdle, -3 base), nonnegative for BVH triangles. Other outlines retain
procedural triangle surfaces.

Instance.rig2.z is an outside-bound camera distance, derived from an enclosing
sphere of all host and defect geometry. It remains valid under rotation. The
orthographic framing half-width remains a separate authoring/clip parameter.
